# Microsoft Foundry topology and capability plan

**Owner:** Rusty, Foundry architecture  
**Plan date:** 2026-07-31  
**Status:** Planning only; no tenant validation or provisioning has occurred

## 1. Decisions and boundaries

The target design uses:

- One Microsoft Foundry resource in `northcentralus`.
- Two child projects:
  - `hoa-project`
  - `one-to-four-residential-contract-project`
- Two Microsoft Entra security groups:
  - `hoa-group`
  - `One-to-Four-Residential-Contract`
- Bicep for infrastructure as code.
- Private endpoints, disabled public network access, and project-specific data connections.
- Agents limited initially to document extraction and quality control. They must not provide legal advice, make eligibility/credit decisions, or autonomously approve or reject a transaction.
- Domain authorities, form versions, jurisdictions, field dictionaries, and human review owners remain TBD.

Microsoft documents a Foundry resource as the top-level governance boundary and projects as child resources and development boundaries for files, agents, and evaluations. This supports access isolation, but **strict non-discoverability of the sibling project is not yet proven**. Microsoft’s documented enterprise portal mapping adds `Reader` on the parent Foundry resource to a project-scoped `Foundry User`. Parent Reader can expose account and project metadata, so it is not approved for the two member groups.

## 2. Evidence labels

| Label | Meaning |
|---|---|
| **Documented** | Current Microsoft documentation explicitly supports the statement. |
| **Validate live** | Documentation supports the design direction, but the target tenant, subscription, portal, region, model, quota, or effective RBAC behavior must be tested. |
| **Unsupported assumption** | The platform documentation does not establish the behavior; it must not be represented as a guarantee. |

Azure authentication was unavailable during planning. No interactive login was retried, and no live tenant, quota, feature, model, role-definition, or portal behavior was validated.

## 3. Logical topology

```text
Subscription
└─ Resource group
   ├─ Microsoft Foundry resource (one, northcentralus)
   │  ├─ Account-level governance
   │  │  ├─ Private endpoint / public access disabled
   │  │  ├─ Model deployments and quota
   │  │  ├─ Policies, guardrails, diagnostics
   │  │  └─ No shared customer-data connections
   │  ├─ hoa-project
   │  │  ├─ System-assigned managed identity
   │  │  ├─ Project-scoped connections
   │  │  ├─ Files and evaluation datasets
   │  │  ├─ Extraction / quality-control agents
   │  │  └─ Evaluation runs and results
   │  └─ one-to-four-residential-contract-project
   │     ├─ System-assigned managed identity
   │     ├─ Project-scoped connections
   │     ├─ Files and evaluation datasets
   │     ├─ Extraction / quality-control agents
   │     └─ Evaluation runs and results
   ├─ HOA-only Storage, Azure AI Search, and Cosmos DB if Standard Agent Setup requires them
   ├─ Contract-only Storage, Azure AI Search, and Cosmos DB if Standard Agent Setup requires them
   ├─ Private endpoints and DNS links for Foundry and every backing service
   └─ Admin-only monitoring destination
```

### Azure resource hierarchy and scopes

The stable Bicep resource types documented as of this plan are:

- Parent: `Microsoft.CognitiveServices/accounts@2026-05-01`
  - `kind: 'AIServices'`
  - `sku.name: 'S0'`
  - `properties.allowProjectManagement: true`
  - `properties.publicNetworkAccess: 'Disabled'`
  - local/key authentication should be disabled unless a validated feature requires it.
- Children: `Microsoft.CognitiveServices/accounts/projects@2026-05-01`
  - system-assigned identity
  - exact project names above
  - parent is the single Foundry resource.

Project resource IDs and RBAC scopes are:

```text
/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.CognitiveServices/accounts/{foundryName}/projects/hoa-project

/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.CognitiveServices/accounts/{foundryName}/projects/one-to-four-residential-contract-project
```

The documented project endpoint format is:

```text
https://{foundryName}.services.ai.azure.com/api/projects/{projectName}
```

**Validate live:** Basher must confirm that `2026-05-01` is accepted by the target subscription and Bicep toolchain at implementation time. A newer stable API version may replace it if its schema and behavior are reviewed first.

## 4. Shared versus project-specific assets

| Asset | Scope | Plan and rationale | Evidence |
|---|---|---|---|
| Foundry resource, private endpoint, policy, quota | Shared account | Required by the one-resource decision; centrally administered. | Documented |
| Model deployments | Account-level | Project members consume approved deployments through project endpoints but cannot create or modify deployments. Consider separate deployment names per project when content filters, versions, chargeback, or release cadence differ. | Documented; deployment choice validate live |
| Customer-data connections | Project-specific only | Do not create resource-level Storage, Search, database, or domain connections. Shared connections are convenient but weaken the isolation story and can grant indirect access to shared data. | Documented connection scopes; design decision |
| Storage | Separate per project | Separate accounts or equivalently strong physical stores, containers, identities, private endpoints, and RBAC. Separate accounts are preferred for simplest negative-access evidence. | Documented BYO support; topology validate live |
| Azure AI Search | Separate per project | Separate services or, only if approved, strongly isolated indexes with identity and negative tests. Separate services are preferred because network and data-plane boundaries are clearer. | Documented BYO/private-link support |
| Cosmos DB / agent state | Separate per project when Standard Agent Setup is used | Avoid shared conversation, vector, and agent-state stores. Bind through project capability hosts. | Documented Standard Agent Setup pattern |
| Project managed identities | Project-specific | Each identity receives access only to its project’s stores and connections. No identity receives access to the sibling stores. | Documented |
| Files, datasets, agents, evaluations | Project-specific | These are documented project assets and must never be copied or referenced across projects without a separately governed export/import process. | Documented |
| Key Vault / credentials | Prefer no shared customer secrets | Use managed identity connections. If customer-managed secrets are unavoidable, use project-specific vaults or prove secret-level isolation; do not assume a resource-level vault connection hides sibling secrets. | Validate live |
| Monitoring | Shared admin-only sink allowed | Central operations may aggregate diagnostics, but project groups receive no access to cross-project logs. Project-level evidence must retain project identity. | Documented metrics scoping; validate configuration |

Microsoft-managed basic agent storage is logically separated, but strict isolation and private networking favor Standard Agent Setup with customer-owned resources where the selected agent feature supports it. Standard Agent Setup requires BYO Storage, Azure AI Search, and Cosmos DB.

## 5. Identity and strict-isolation model

1. Assign built-in **Foundry User** (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) to:
   - `hoa-group` at the `hoa-project` resource ID only.
   - `One-to-Four-Residential-Contract` at the `one-to-four-residential-contract-project` resource ID only.
2. Do not assign either group Foundry User, Reader, Contributor, Owner, Foundry Project Manager, Foundry Account Owner, or Foundry Owner at management group, subscription, resource group, or Foundry-resource scope.
3. Audit direct assignments, transitive group membership, PIM eligible/active assignments, and inherited roles. A child assignment cannot cancel a broader inherited allow.
4. Assign each project managed identity only the account-level inference permission and backing-resource data roles that Microsoft documents as necessary. Never assign one project identity to the sibling’s stores.
5. Use Microsoft Entra ID authentication. Key authentication bypasses granular RBAC and is excluded from the member workflow.

### Mandatory non-discoverability gate

Start with **no parent-resource Reader assignment** for project member groups. Test direct API/SDK access and a bookmarked project URL with fresh tokens.

Pass requires that a member:

- can open and use only the assigned project;
- cannot list, search, resolve, open, or infer the existence of the sibling project through portal, ARM, Foundry API, SDK, CLI, activity, connection pickers, or error detail;
- cannot read sibling project names, IDs, tags, identities, agents, files, datasets, evaluations, or connections.

Microsoft’s sample enterprise mapping recommends project-scoped Foundry User plus parent-resource Reader. If the portal requires parent Reader, or if Foundry User’s effective read actions reveal sibling metadata, then **one resource plus strict sibling non-discoverability is not proven feasible with the documented standard portal pattern**. Stop at the gate and escalate the conflict; do not weaken “not discoverable” to “cannot modify.”

Custom roles are a possible investigation path, not an approved solution. Their exact actions, data actions, portal dependencies, and supportability require live validation.

## 6. Project-member capability matrix

This matrix assumes only Foundry User at the assigned project scope and no parent Reader.

| Capability | Expected member result | Basis | Required validation / qualification |
|---|---|---|---|
| Create, update, delete prompt agents | **Allow in assigned project** | Foundry User has project data actions; Microsoft explicitly documents agent creation as a data-plane action allowed to Foundry User. | Validate selected agent type and every operation through portal and API. |
| Invoke assigned-project agents | **Allow** | Foundry User can interact with agent endpoints. | Validate project endpoint and private DNS path. |
| Publish agent applications / hosted-agent deployment | **Deny for initial phase** | Publishing requires Foundry Project Manager or higher and hosted scenarios add ARM, ACR, and monitoring permissions. | Out of initial extraction/QC boundary. |
| Create and run evaluations | **Allow in assigned project** | Evaluation documentation requires Foundry User on the project. | Validate chosen evaluator, evaluation model connection, private networking, quota, and result access. |
| Create/use evaluation datasets and upload files | **Allow in assigned project** | Files and evaluations are project assets; uploading files is a documented data-plane operation. | Test create/list/read/update/delete and cross-project denial. File Search is not supported under current network isolation guidance. |
| Create/manage project connections | **Technically allow; govern as IaC-first** | Microsoft documents Foundry User as sufficient to add a project connection. | Built-in role may permit unapproved connections. Precreate allowlisted managed-identity connections; test whether policy/custom role is needed to prevent ad hoc connections. |
| Use project-specific connections | **Allow** | Projects can use project connections and connected data without direct user access to the backing store. | Validate no inherited resource-level connections or sibling connection enumeration. |
| Read approved model deployments / run inference | **Allow as needed** | Project developers build with predeployed models; Foundry User can read deployment/quota metadata but not manage deployments. | Validate inference through the project endpoint without parent Reader. |
| Create, update, or delete model deployments | **Deny** | Model deployment is account-level control plane; Foundry User and Foundry Project Manager do not manage models. | Admin/deployment principal only. |
| Create projects | **Deny** | Foundry User cannot create projects. Projects are deployed by Bicep. | Validate no inherited control-plane role. |
| Assign roles | **Deny** | Foundry User cannot complete role assignments. | Validate Azure IAM and Foundry Admin UI denial. |

The initial extraction/QC solution must not assume that built-in **File Search** works with private networking; Microsoft currently lists it as unsupported. Supported design candidates include project-specific private Azure AI Search, a private MCP/OpenAPI tool, or an external extraction service reached through the project’s approved private connection. The final tool path is a live feature and security gate.

## 7. Networking and DNS assumptions

### Inbound

- Disable public network access on the Foundry account.
- Create a private endpoint targeting the Foundry **account** subresource. The same public endpoint names resolve to private IPs inside the connected network.
- Provide developer and automation access through approved VPN, ExpressRoute, or a private build/administration host.
- Validate port 443, private endpoint approval, and private resolution from every client network.

### Outbound for agents and evaluations

- Use VNet injection where the selected agent/evaluation path requires private outbound access.
- The delegated agent subnet must use `Microsoft.App/environments`, be at least `/27`, and should be sized closer to `/24` for production growth.
- Create private endpoints separately for each project’s Storage, Search, and Cosmos DB resources; Foundry deployment does not create those endpoints automatically.
- Do not assume one Foundry resource can bind each project to a different delegated agent subnet. If VNet injection is account-wide, network reachability is shared and isolation depends on project identity, connections, and backing-resource RBAC. This must be validated before topology approval.

### Required DNS planning

Link and validate the zones required by deployed services:

- Foundry account:
  - `privatelink.cognitiveservices.azure.com`
  - `privatelink.openai.azure.com`
  - `privatelink.services.ai.azure.com`
- Azure AI Search: `privatelink.search.windows.net`
- Cosmos DB SQL: `privatelink.documents.azure.com`
- Storage Blob: `privatelink.blob.core.windows.net`
- Add ACR and Azure Monitor Private Link zones only if those components enter scope.

Custom or on-premises DNS must forward the corresponding public zones to Azure DNS (`168.63.129.16`) or otherwise resolve each service FQDN to its private endpoint. Acceptance evidence must include `nslookup` results and port-443 connectivity from the actual client and agent paths.

### Current tooling and feature limitations

- Public-network-disabled deployments can require SDK, CLI, Azure portal, or Bicep operations that are not available in every Foundry portal screen.
- Foundry MCP discovery could not be used because Azure authentication was unavailable. This plan does not claim tenant discovery.
- Synthetic data generation for evaluations and traces are currently not supported with network isolation. Bring approved evaluation data.
- File Search is currently unsupported in network-isolated agents.
- Code Interpreter is partial: file upload/download is unsupported; its SDK container workaround is not available in the portal.
- Some agent tools use public endpoints even when Foundry is private. Bing Grounding, Web Search, and SharePoint Grounding are excluded unless a later compliance decision permits public egress.
- Outbound VNet injection cannot currently be added to an existing deployment or moved to a different delegated subnet. Treat network topology as a create-time, redeployment-level decision.
- `northcentralus` is documented for Foundry projects, hosted agents, agent playground evaluations, batch evaluations, several safety evaluators, and AI red teaming. Exact model/version/deployment-type capacity and subscription quota still require live validation.

## 8. Bicep resource/output contract for Basher

Basher should consume exact names and emit only non-secret values.

### Inputs owned by this plan

| Input | Value / constraint |
|---|---|
| `location` | `northcentralus` |
| `foundryResourceName` | Parameter; globally valid custom subdomain name, final value coordinated by Basher |
| `hoaProjectName` | `hoa-project` |
| `contractProjectName` | `one-to-four-residential-contract-project` |
| `hoaGroupDisplayName` | `hoa-group` |
| `contractGroupDisplayName` | `One-to-Four-Residential-Contract` |
| `hoaGroupObjectId` | Supplied by Livingston; validate display name before assignment |
| `contractGroupObjectId` | Supplied by Livingston; validate display name before assignment |
| `foundryUserRoleDefinitionId` | `53ca6127-db72-4b80-b1b0-d745d6d5456d` |
| Data resource IDs / subnet IDs / DNS zone IDs | Separate per project where applicable; supplied by networking/data modules |

### Required outputs

| Output | Contract |
|---|---|
| `foundryResourceId` | Full parent account ARM ID |
| `foundryResourceName` | Deployed account name |
| `foundryResourcePrincipalId` | System-assigned identity object ID |
| `hoaProjectId` | Full `accounts/projects/hoa-project` ARM ID |
| `contractProjectId` | Full `accounts/projects/one-to-four-residential-contract-project` ARM ID |
| `hoaProjectPrincipalId` | HOA project system-assigned identity object ID |
| `contractProjectPrincipalId` | Contract project system-assigned identity object ID |
| `hoaProjectEndpoint` | `https://{foundryName}.services.ai.azure.com/api/projects/hoa-project` |
| `contractProjectEndpoint` | `https://{foundryName}.services.ai.azure.com/api/projects/one-to-four-residential-contract-project` |
| `hoaFoundryUserRoleAssignmentId` | Deterministic role-assignment resource ID |
| `contractFoundryUserRoleAssignmentId` | Deterministic role-assignment resource ID |
| `hoaConnectionIds` / `contractConnectionIds` | Project-scoped connection resource IDs, separated by project |
| `hoaDataResourceIds` / `contractDataResourceIds` | Storage, Search, Cosmos, and optional vault IDs, separated by project |
| `privateEndpointIds` | Foundry and backing-service endpoint IDs |
| `privateDnsZoneIds` | Zone IDs used by the deployment |
| `agentSubnetId` or per-project subnet IDs | Actual supported VNet-injection topology, after validation |

Do not output connection secrets, keys, tokens, connection strings, document contents, user identifiers, or test-user credentials. Linus should consume IDs, endpoints, and role-assignment IDs for evidence collection.

## 9. Dependencies and risks

### Dependencies

- **Livingston:** exact Entra group object IDs; direct, transitive, PIM, and inherited-access audit design.
- **Basher:** stable Bicep schema validation, private endpoint/DNS modules, deterministic role assignments, and non-secret outputs.
- **Reuben:** authoritative document taxonomy, jurisdictions/forms, field dictionary, provenance requirements, and gold cases.
- **Rai:** privacy, prompt-injection, legal-overreach, uncertainty, escalation, and evaluation thresholds.
- **Linus:** fresh-token positive/negative tests across ARM, portal, Foundry API, SDK/CLI, networking, and backing stores.
- **Carol/Danny:** resolution if strict non-discoverability conflicts with required parent metadata access.

### Principal risks

| Risk | Impact | Control / gate |
|---|---|---|
| Portal requires parent Reader | Sibling project metadata could become discoverable. | Do not grant it; test direct access first; escalate if required. |
| Built-in Foundry User can create project connections | Members could attach unapproved targets. | IaC-first connections, Azure Policy/custom-role investigation, and negative tests. |
| Shared account model/deployment metadata | Cross-project infrastructure metadata may be visible. | Test listing behavior; use admin-only deployment management and separate logical deployment names if needed. |
| Account-wide VNet injection | Both projects may have network paths to both data estates. | Enforce identity/RBAC and private endpoint controls; validate project-specific subnet support; reconsider topology if policy requires L3 separation. |
| Network-isolated File Search unsupported | Planned document workflow might not work as assumed. | Select private Search/MCP/OpenAPI/extraction-service pattern and prove end to end. |
| Region/model/quota mismatch | Required model or evaluator cannot deploy/run in `northcentralus`. | Live catalog, capacity, quota, and evaluator checks before deployment approval. |
| Project role does not provide portal usability without broader read | Strict isolation and portal UX may be incompatible. | Mandatory non-discoverability gate; no hand-waving. |
| Project connections indirectly expose shared data | Cross-domain leakage. | No resource-level customer-data connections; separate stores and identities. |
| Preview behavior changes | Capability or permission drift. | Pin reviewed API versions, capture role definitions, rerun acceptance tests on every release. |

## 10. Milestones and acceptance evidence

### M0 — Pre-provision validation

- Confirm Bicep stable API versions and naming constraints.
- Confirm `northcentralus` project, agent, evaluator, model/version, deployment type, quota, and private-network support.
- Capture current built-in role definitions by ID.
- Decide the private extraction tool path without relying on File Search.
- Resolve whether the platform supports per-project VNet injection/subnets under one resource.

### M1 — IaC review

- What-if contains exactly one Foundry account and exactly two project children.
- Exact project and group names are represented.
- Member roles are only at corresponding project scopes.
- Customer-data stores and connections are project-specific.
- Public network access is disabled and every required private endpoint/DNS link is represented.
- Outputs satisfy the contract above and contain no secrets or PII.

### M2 — Connectivity and capability proof

For each project, capture:

- private DNS result and TCP 443 connectivity;
- project endpoint authentication;
- agent create/read/update/delete/invoke;
- file and dataset create/list/read/update/delete;
- project connection use;
- evaluation create/run/read/delete;
- inference against the approved deployment.

Each record must include timestamp, principal/object ID, token acquisition time, operation, scope, expected result, actual result, HTTP/status detail, correlation ID, and evidence artifact location.

### M3 — Strict isolation proof

Using one test principal in only one group at a time and fresh tokens, prove denial of:

- sibling project discovery and metadata;
- sibling agents and endpoints;
- sibling files and datasets;
- sibling evaluations and results;
- sibling connections;
- sibling Storage, Search, Cosmos, vault, and monitoring data;
- sibling create/update/delete/invoke operations.

Repeat through the Foundry portal, Azure portal/ARM, direct Foundry API, SDK/CLI, resource graph/search, and connection/resource pickers. Parent Reader remains unapproved unless Carol explicitly changes the isolation requirement.

### M4 — Domain and safety acceptance

- Only approved extraction and quality-control use cases are enabled.
- Outputs include source/provenance, document/form version, confidence, missing-field flags, and required human review.
- Synthetic or governed evaluation data is used.
- Tests cover omission, hallucination, prompt injection in documents, cross-document leakage, unsupported legal conclusions, and escalation.
- Domain authorities and human approvers sign off before production use.

## 11. Official Microsoft documentation

- [Microsoft Foundry architecture](https://learn.microsoft.com/azure/foundry/concepts/architecture)
- [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry)
- [Elevated-role tasks in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/concepts/administrator-guide)
- [Create a project for Microsoft Foundry](https://learn.microsoft.com/azure/foundry/how-to/create-projects)
- [Run evaluations from the Microsoft Foundry portal](https://learn.microsoft.com/azure/foundry/how-to/evaluate-generative-ai-app)
- [Evaluation regions, limits, and virtual network support](https://learn.microsoft.com/azure/foundry/concepts/evaluation-regions-limits-virtual-network)
- [Add a new connection to a project](https://learn.microsoft.com/azure/foundry/how-to/connections-add)
- [Connect to your own storage](https://learn.microsoft.com/azure/foundry/how-to/bring-your-own-azure-storage-foundry)
- [Configure network isolation for Microsoft Foundry](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link)
- [Set up private networking for Foundry Agent Service](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [Foundry feature availability across regions](https://learn.microsoft.com/azure/foundry/reference/region-support)
- [Hosted agent permissions](https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agent-permissions)
- [Bicep/ARM schema: Foundry account](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2026-05-01/accounts)
- [Bicep/ARM schema: Foundry project](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2026-05-01/accounts/projects)
- [Microsoft Foundry REST API](https://learn.microsoft.com/rest/api/microsoft-foundry/aiproject)

