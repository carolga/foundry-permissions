# Bicep deployment implementation plan

**Owner:** Basher, Infrastructure-as-Code  
**Status:** Approved design translated into an implementation plan; no Bicep or Azure resources created  
**Plan date:** 2026-07-31  
**IaC standard:** Bicep  
**Target region:** `northcentralus`, subject to live capability, model, quota, and policy checks

## 1. Purpose and non-negotiable design

This plan defines how to implement, validate, and operate a repeatable Bicep deployment for one Microsoft Foundry resource containing exactly:

- `hoa-project`
- `one-to-four-residential-contract-project`

The matching Microsoft Entra security groups are exactly:

- `hoa-group`
- `One-to-Four-Residential-Contract`

Each group receives Foundry User only at its matching project scope. The deployment must not grant either group Reader, Foundry User, Contributor, Owner, or another permission at the subscription, resource group, shared Foundry resource, or sibling project.

Strict sibling-project non-discoverability is a release gate, not an optimization. If the portal, ARM, Foundry API, SDK, CLI, resource selectors, or error details reveal the sibling project without a broader permission, stop and escalate. Do not add parent Reader or weaken the requirement to make deployment or portal access easier.

The implementation will use:

- private endpoints and private DNS;
- public network access disabled at resource creation where the provider supports it;
- separate project data resources and project-scoped connections;
- managed identities and Microsoft Entra authentication instead of keys;
- immutable principal object IDs for role assignments;
- non-secret parameters and outputs only.

This document is planning-only. It does not authorize resource provider registration, group creation, role assignment, Bicep generation, validation against a live subscription, or deployment.

## 2. Recommended repository structure

Future implementation should use the following structure. File names describe responsibilities; they are not Bicep files created by this planning task.

```text
infra/
├─ bicepconfig.json
├─ bootstrap/
│  └─ main.bicep
├─ main.bicep
├─ access.bicep
├─ modules/
│  ├─ foundry/
│  │  ├─ account.bicep
│  │  ├─ projects.bicep
│  │  └─ project-connections.bicep
│  ├─ data/
│  │  ├─ project-data.bicep
│  │  ├─ storage.bicep
│  │  ├─ search.bicep
│  │  └─ cosmos.bicep
│  ├─ network/
│  │  ├─ network.bicep
│  │  ├─ private-dns.bicep
│  │  └─ private-endpoints.bicep
│  ├─ identity/
│  │  ├─ project-managed-identity-access.bicep
│  │  └─ project-group-access.bicep
│  └─ observability/
│     └─ diagnostics.bicep
├─ environments/
│  ├─ dev.bicepparam
│  ├─ test.bicepparam
│  └─ prod.bicepparam
└─ tests/
   ├─ assert-template.ps1
   ├─ assert-what-if.ps1
   └─ assert-no-secrets.ps1
```

### File responsibilities

| Future file | Scope | Responsibility |
|---|---|---|
| `infra/bootstrap/main.bicep` | Subscription | Create the environment resource group and only the minimum bootstrap resources needed before the resource-group deployment. Keep this separate so the steady-state infrastructure identity does not need subscription-wide Contributor. |
| `infra/main.bicep` | Resource group | Orchestrate network, DNS, project-specific data resources, the one Foundry account, two projects, private endpoints, managed-identity access, project connections, and diagnostics. It must not grant human/group access. |
| `infra/access.bicep` | Resource group deployment with extension resources at exact child/resource scopes | Orchestrate only approved Azure role assignments. This separation allows an access identity and approval path distinct from infrastructure deployment. |
| `foundry/account.bicep` | Resource group | Create one `Microsoft.CognitiveServices/accounts` resource with `kind: AIServices`, project management enabled, managed identity, local authentication disabled where supported, and public network access disabled. |
| `foundry/projects.bicep` | Resource group; child resources | Create exactly the two named `accounts/projects` children with system-assigned identities. Return child IDs, endpoints, and principal IDs. Do not accept an arbitrary project array in production. |
| `foundry/project-connections.bicep` | Project child scope | Create only project-scoped, managed-identity/AAD connections to that project's resources. Reject secret-bearing authentication types and any resource-level/shared customer-data connection. |
| `data/project-data.bicep` | Resource group | Deploy one project's isolated data estate by calling Storage, Search, and Cosmos modules as required by the approved agent pattern. Invoke it once for HOA and once for contract data. |
| `data/storage.bicep` | Resource group | Create a project-specific Storage account/container with public access and shared-key access disabled where supported, private access, retention/recovery controls, and identity-based authorization. |
| `data/search.bicep` | Resource group | Create a project-specific Azure AI Search service with public access disabled, managed-identity authorization, and no sibling-project role assignment. |
| `data/cosmos.bicep` | Resource group | Create a project-specific Cosmos DB account/database required by Standard Agent Setup, with public access and local/key authentication disabled where supported. Use service-native data-plane role assignments in the access phase. |
| `network/network.bicep` | Resource group | Create or reference the approved VNet and subnets, including any delegated agent subnet. It must not assume that one account supports separate injected subnets per project. |
| `network/private-dns.bicep` | Resource group or central-network resource group | Create or reference approved private DNS zones and VNet links. Support a central-DNS mode through existing zone IDs rather than duplicating zones. |
| `network/private-endpoints.bicep` | Resource group | Create private endpoints and DNS zone groups for Foundry and every project backing resource. Inputs must identify the exact target resource and supported subresource/group ID. |
| `identity/project-managed-identity-access.bicep` | Exact backing-resource and project scopes | Grant each project managed identity only the roles proven necessary on its own project and backing resources. No account-wide shortcut is allowed without passing the isolation gate. |
| `identity/project-group-access.bicep` | Exact Foundry project child scopes | Assign Foundry User to `hoa-group` at `hoa-project` and to `One-to-Four-Residential-Contract` at the contract project. Use deterministic IDs and `principalType: Group`. |
| `observability/diagnostics.bicep` | Resource group/resources | Emit project diagnostics to matching isolated workspaces and duplicate shared-account diagnostics symmetrically to both workspaces. Use unique setting names, `allLogs`, and `AllMetrics`; do not depend on inherited policy deployment. |
| `bicepconfig.json` | Repository | Enable recommended analyzers, treat secret/output and unused-resource warnings appropriately, and configure any approved module registry aliases. |
| `environments/*.bicepparam` | Deployment environment | Hold non-secret environment values and immutable object IDs. Production values are protected and reviewed. No credentials, keys, tokens, connection strings, or personal identifiers are allowed. |
| `tests/*.ps1` | CI | Inspect compiled templates and what-if JSON for exact counts/scopes, prohibited parent assignments, unexpected public access, secrets, and destructive changes. Tests are not deployment scripts. |

Use Azure Verified Modules only when the reviewed, pinned AVM version exposes all required Foundry, identity, network, and security properties. Otherwise use a small local module rather than bypassing a locked control. Record the AVM version; do not consume a floating tag.

## 3. Control-plane boundaries and Entra groups

Microsoft Entra groups are tenant-directory objects, not native Azure Resource Manager resources. Standard ARM resource providers cannot create them.

The generally available Microsoft Graph Bicep extension supports `Microsoft.Graph/groups@v1.0`, but that is a separate Microsoft Graph control plane. A pipeline creating groups through the extension requires Microsoft Graph permissions such as `Group.ReadWrite.All`, in addition to Azure deployment permissions. Deleting an Azure resource group does not delete Graph resources, and Graph lifecycle, ownership, access reviews, and replication behavior differ from Azure resources.

### Recommended safest pattern

1. The identity-governance process pre-provisions and owns the two exact security groups.
2. The identity team verifies that each group is security-enabled, mail-disabled, assigned-membership, non-dynamic, non-nested for the initial release, and has approved owners.
3. The identity team supplies immutable object IDs through protected, non-secret deployment parameters:
   - `hoaGroupObjectId`
   - `contractGroupObjectId`
4. A pre-deployment Graph read verifies that each object ID still maps to the expected exact display name and expected group properties.
5. The core Bicep deployment uses only those object IDs for Azure role assignments.

Do not use display-name lookup inside deployment logic. Do not use an ARM deployment script to create or discover groups. Deployment scripts add imperative state, require elevated Graph permissions, complicate idempotency, and can leak directory data through logs.

If the organization later mandates declarative group lifecycle, place Microsoft Graph Bicep in a separate identity-owned repository/module and pipeline with its own approvals, drift process, and least-privileged Graph permissions. Do not couple it to the Foundry infrastructure or access deployment. This project should still consume its resulting object IDs.

## 4. Deployment scopes and sequence

### Phase 0 — Preflight gates

No template implementation begins until all gates in section 7 pass. Confirm target tenant/subscription, policy assignments, provider registrations, API versions, regional availability, quota, private-link subresources, role definitions, and the selected agent/data pattern.

### Phase 1 — Identity prerequisite

**Control plane:** Microsoft Graph / Microsoft Entra, outside the core ARM deployment.

- Pre-provision the two exact groups through the governed identity process.
- Record only object IDs and expected non-PII properties in protected deployment configuration.
- Do not add users during infrastructure deployment.
- Verify no duplicate display names are being used as a substitute for object-ID validation.

### Phase 2 — Resource-group bootstrap

**Deployment scope:** Subscription.

- Deploy `infra/bootstrap/main.bicep`.
- Create one environment resource group in `northcentralus`.
- Apply mandatory non-PII tags and any policy-required locks only after their operational effects are reviewed.
- Output the resource group ID and name.

Steady-state CI should not run this phase unless the resource group is absent or approved bootstrap configuration changes.

### Phase 3 — Network and private DNS foundation

**Deployment scope:** Resource group, or explicit existing central-network resource group.

- Create/reference VNet, private-endpoint subnet, and the delegated agent subnet if live feature validation requires VNet injection.
- Create/reference and link these zones as applicable:
  - `privatelink.cognitiveservices.azure.com`
  - `privatelink.openai.azure.com`
  - `privatelink.services.ai.azure.com`
  - `privatelink.blob.core.windows.net`
  - `privatelink.search.windows.net`
  - `privatelink.documents.azure.com`
- Validate central DNS ownership and cross-resource-group permissions before implementation.
- Output subnet and zone IDs.

DNS zones must exist before DNS zone groups, but private endpoints can only be created after their target resources exist.

### Phase 4 — Project-specific supporting resources

**Deployment scope:** Resource group.

- Deploy separate HOA and contract Storage, Search, and Cosmos resources when required by the approved Standard Agent Setup/tool pattern.
- Create each resource with public network access and local/key access disabled where supported.
- Do not create a shared customer-data store merely to reduce module count.
- Output resource IDs, service endpoints needed for managed-identity connections, and private-link targets. Do not output keys or connection strings.

The selected agent feature may not need every candidate resource. Omit unused services only after the capability design is approved; do not replace separate stores with shared stores.

### Phase 5 — Foundry account and projects

**Deployment scope:** Resource group.

1. Deploy exactly one Foundry account.
2. Enable project management, managed identity, approved network injection, private access posture, and local-auth restrictions supported by the selected stable API.
3. Deploy exactly two child projects with system-assigned identities:
   - `hoa-project`
   - `one-to-four-residential-contract-project`
4. Output both project child resource IDs, endpoint values returned or deterministically documented by the provider, and managed-identity principal IDs.

The project module must fail template tests if a third project is added or either exact name changes.

### Phase 6 — Private endpoints and DNS zone groups

**Deployment scope:** Resource group.

- Create the Foundry account private endpoint using the live-verified group ID.
- Create separate private endpoints for every HOA backing resource.
- Create separate private endpoints for every contract backing resource.
- Attach each endpoint to the correct private DNS zone through a DNS zone group.
- Verify the approved DNS path from CI runners, admin workstations, and agent/evaluation runtime paths before disabling any temporary bootstrap route. Public access should already be disabled where creation supports it; do not use an open-public-network deployment window as the normal pattern.

### Phase 7 — Project managed-identity access

**Deployment scope:** Each exact project and backing-resource scope.

- Grant each project identity only the documented roles required on its own Storage, Search, Cosmos, monitoring, and project scope.
- Attempt Foundry User for a project managed identity at its own project first.
- Do not assign a project identity Foundry User at the shared account merely because a starter sample does so.
- If the service requires account-scope access, stop and prove that the identity cannot enumerate or access sibling assets. Failure blocks the one-resource design.

Azure RBAC and service-native data-plane assignments, such as Cosmos DB data roles, should be separate modules because their providers and propagation behavior differ.

### Phase 8 — Project-scoped connections

**Deployment scope:** Each project child.

- Create only managed-identity or AAD project connections to that project's resources.
- Set no project connection as shared across projects.
- Do not create account/resource-level customer-data connections.
- Do not permit `ApiKey`, `AccountKey`, `SAS`, `ServicePrincipal` client-secret, username/password, OAuth client-secret, or other secret-bearing connection variants.
- Treat role-assignment propagation as eventually consistent. Use an idempotent retry at the orchestration/pipeline layer for a connection validation failure; do not insert arbitrary sleeps into Bicep.

### Phase 9 — Human/group Azure RBAC

**Deployment scope:** Exact project child resources through `infra/access.bicep`.

- `hoaGroupObjectId` → Foundry User → `hoa-project`
- `contractGroupObjectId` → Foundry User → `one-to-four-residential-contract-project`

The assignment name must be deterministic from project ID, principal object ID, and fully qualified role-definition ID. The template must set `principalType: Group`.

No developer-group assignment may target the Foundry account, resource group, subscription, management group, sibling project, project backing resource, private DNS zone, or monitoring sink.

### Phase 10 — Validation and membership

- Complete effective-access and inherited-role audits before adding test users.
- Add one clean test user to only one group through the identity process.
- Wait for documented propagation, obtain fresh tokens, and execute the positive and negative authorization matrix.
- Remove bootstrap elevation after acceptance.

## 5. Parameter and output contracts

### 5.1 Bootstrap parameters

| Parameter | Type/constraint | Notes |
|---|---|---|
| `environmentName` | Allowed controlled values such as `dev`, `test`, `prod` | Used for environment separation, not project/group renaming. |
| `location` | Allowed value `northcentralus` | Any change is an architecture decision and requires renewed availability review. |
| `resourceGroupName` | Valid Azure resource-group name | Stable per environment. |
| `tags` | Object of approved non-PII strings | Merged first; locked `SecurityControl=Ignore` and `CostControl=Ignore` values are applied last and cannot be overridden. |

### 5.2 Infrastructure parameters

| Parameter | Type/constraint | Notes |
|---|---|---|
| `foundryAccountName` | Provider-valid, globally unique custom-subdomain-compatible name | Stable and environment-specific. |
| `hoaProjectName` | Constant `hoa-project` | Prefer a module constant rather than an overridable production parameter. |
| `contractProjectName` | Constant `one-to-four-residential-contract-project` | Same rule. |
| `networkMode` | Approved enum: deploy or existing | Existing mode requires exact VNet/subnet resource IDs. |
| `privateEndpointSubnetId` | Resource ID | Required in existing-network mode. |
| `agentSubnetId` | Resource ID or omitted until feature gate passes | Must match delegation and size requirements. |
| `privateDnsZoneIds` | Object keyed by service | Exact existing IDs or outputs from the DNS module. |
| `projectDataConfig` | Strongly typed object with `hoa` and `contract` keys only | Contains resource names, SKUs, retention, and approved feature flags; no credentials. |
| `connectionConfig` | Strongly typed project-specific object | Contains names, categories, target resource IDs/FQDNs, and managed-identity mode only. |
| `tags` | Object | Same protected merge behavior as bootstrap; the two locked control tags always win. |

No central diagnostic destination parameter is accepted. The monitoring module
uses the two repository-created project workspaces directly: each project
targets its own workspace, and two separate account settings target one
workspace each.

### 5.3 Access parameters

| Parameter | Type/constraint | Notes |
|---|---|---|
| `hoaGroupObjectId` | GUID | Expected to resolve to `hoa-group`; identifier, not a secret. |
| `contractGroupObjectId` | GUID | Expected to resolve to `One-to-Four-Residential-Contract`; identifier, not a secret. |
| `hoaProjectId` | Full child ARM resource ID | Prefer infrastructure output passed by the pipeline. |
| `contractProjectId` | Full child ARM resource ID | Same. |
| `hoaProjectPrincipalId` | GUID | Used for project-specific data access. |
| `contractProjectPrincipalId` | GUID | Used for project-specific data access. |
| `foundryUserRoleDefinitionId` | Pinned built-in role GUID | Verify live definition before deployment; do not accept a display name. |
| `approvedBackingResourceRoleMap` | Reviewed object | Explicit principal/role/scope tuples; no broad generated role list. |

Object IDs may be outputs because they are identifiers, but logs and evidence should still avoid associating them with personal data. UPNs, user object IDs, raw membership exports, and test-user credentials are outside this repository.

### 5.4 Required non-secret outputs

- `resourceGroupId`
- `resourceGroupName`
- `foundryResourceId`
- `foundryResourceName`
- `foundryResourcePrincipalId`
- `hoaProjectId`
- `contractProjectId`
- `hoaProjectPrincipalId`
- `contractProjectPrincipalId`
- `hoaProjectEndpoint`
- `contractProjectEndpoint`
- `hoaGroupObjectId`
- `contractGroupObjectId`
- `hoaFoundryUserRoleAssignmentId`
- `contractFoundryUserRoleAssignmentId`
- `hoaConnectionIds`
- `contractConnectionIds`
- `hoaDataResourceIds`
- `contractDataResourceIds`
- `privateEndpointIds`
- `privateDnsZoneIds`
- `agentSubnetId` or the live-approved subnet contract

No template, deployment output, CI artifact, log, or evidence bundle may contain:

- keys, tokens, passwords, client secrets, SAS values, or connection strings;
- bearer tokens or credentials;
- document contents or customer data;
- email addresses, UPNs, or test-user personal identifiers.

## 6. Environment separation, naming, and tagging

### Environment boundaries

- Treat each environment as a separate deployment unit containing exactly one Foundry account and the same two exact project child names.
- Prefer separate subscriptions and resource groups. At minimum, use separate resource groups, Foundry accounts, VNets/subnets, private endpoints, DNS links, data resources, managed identities, and deployment histories.
- Do not place development/test projects inside the production Foundry account.
- Microsoft Entra groups are tenant-global. Production uses the two exact locked groups. A lower environment must either use a separate tenant with the same exact names or receive an explicit governance decision for environment-specific groups. Never bind a non-production deployment to production groups for convenience.
- Keep a separate `.bicepparam` file and protected CI environment per deployment environment.
- Production deployment requires manual approval and a reviewed what-if artifact.

### Naming

Use stable names derived from `{resource-type}-{workload}-{environment}-{region-code}` where the provider permits:

- workload token: `foundry-permissions`
- region code: `ncus`
- example resource group: `rg-foundry-permissions-prod-ncus`

Globally unique or length-constrained resources should append a deterministic `uniqueString` derived from stable scope inputs, never a timestamp or random value. Storage names remain lowercase alphanumeric. Project names remain the exact locked names without environment suffixes because the parent Foundry account provides the environment boundary.

Connection names should identify project and target without customer data, for example an HOA storage connection and a contract search connection. Final names must pass the live provider's length and character rules.

### Mandatory tags

Apply supported tags consistently:

- `SecurityControl=Ignore` (locked)
- `CostControl=Ignore` (locked)
- `environment`
- `workload=foundry-permissions`
- `managedBy=bicep`
- `region=northcentralus`
- `dataBoundary=hoa`, `contract`, or `shared-admin`
- `criticality`
- approved `costCenter`/`businessUnit` values if organizational policy requires them

Caller-supplied tags are merged before locked tags. Preserve all approved
governance tags, but never permit either locked control value to be omitted or
overridden. Apply tags only to resource types and API versions that support
them; known unsupported child and extension resources remain untagged.

Do not put people's names, email addresses, customer names, document identifiers, or secrets in tags.

## 7. API version and provider-support gates

Implementation must stop if any gate fails.

1. **Bicep toolchain gate:** Pin and record Azure CLI and Bicep CLI versions in CI. Run restore/build/lint using the same versions locally and in CI.
2. **Foundry account/project API gate:** Microsoft Learn listed stable `2026-05-01` for `Microsoft.CognitiveServices/accounts` and `accounts/projects` on 2026-07-31. The Bicep schema tool used during this planning session returned `2025-06-01`, demonstrating possible schema-cache/tooling lag. Before coding, confirm that the pinned Bicep CLI has types for the selected stable version and that the target subscription provider accepts it. Use the newest reviewed stable version, not a preview merely because it is newer.
3. **Connection API gate:** Confirm stable `accounts/projects/connections` support, managed-identity/AAD connection schema, create/update/delete behavior, and secret-free deployment. Microsoft Learn lists stable versions through `2026-05-01`; the planning schema tool returned `2025-06-01`. Reconcile this before implementation.
4. **Provider registration gate:** Confirm required resource types/API versions for `Microsoft.CognitiveServices`, `Microsoft.Network`, `Microsoft.Storage`, `Microsoft.Search`, `Microsoft.DocumentDB`, `Microsoft.Authorization`, and the selected diagnostics providers. Registration is a separate approved action.
5. **Regional feature gate:** Validate projects, selected agent type, evaluation type, VNet injection, private networking, and every backing service in `northcentralus`.
6. **Model and quota gate:** Check the exact model, version, deployment type, capacity/quota, evaluator dependencies, and subscription restrictions live. General regional documentation is not capacity evidence.
7. **Private-link gate:** Query each target's supported private-link resource/group IDs and confirm the DNS zones. Do not hardcode a group ID copied from an unrelated quickstart.
8. **Network-injection gate:** Confirm whether the one Foundry account can support the required per-project runtime path. If injection is account-wide, prove identity and connection controls prevent cross-project data use. If Layer-3 separation is mandatory and unsupported, escalate the one-account topology.
9. **Role-definition gate:** Retrieve the live Foundry User definition for GUID `53ca6127-db72-4b80-b1b0-d745d6d5456d`; compare name, actions, data actions, conditions, and assignable scopes with the approved baseline.
10. **Managed-identity role gate:** Prove the minimum roles for agent authoring, evaluation, Storage, Search, Cosmos, and telemetry. Do not infer permissions from a sample.
11. **Policy gate:** Review Azure Policy assignments and deny effects at management-group, subscription, and resource-group scopes before finalizing properties and names.
12. **AVM gate:** Inspect current AVM metadata and module interfaces. Use a pinned AVM only if it preserves all required controls and child-resource outputs.
13. **Graph boundary gate:** Confirm the deployment identities have no Microsoft Graph write permission because groups are pre-provisioned. If Graph Bicep is later approved, it receives a separate threat model and pipeline.

## 8. Validation, deployment, rollback, and idempotency

### Static and compile validation

The future CI pipeline should:

1. restore pinned registry modules;
2. run Bicep formatting checks;
3. run `az bicep lint`/the pinned equivalent;
4. compile every entry point and environment parameter file;
5. run ARM validation at subscription scope for bootstrap and resource-group scope for infrastructure/access;
6. inspect compiled JSON for secret-bearing parameters/outputs and prohibited authentication types;
7. assert exact resource and project counts;
8. assert no developer-group role assignment has a parent or sibling scope.

### What-if strategy

- Produce a subscription-scope what-if for bootstrap.
- Produce a resource-group what-if for infrastructure.
- Produce a separate resource-group what-if for access/RBAC.
- Save sanitized JSON and human-readable summaries as CI artifacts.
- Fail on unexpected deletes, replacements, public-network enablement, shared data resources/connections, a third project, changed exact names, parent-scope developer assignments, or role-definition changes.
- Require manual production approval after reviewers inspect both infrastructure and access what-if results.
- Treat what-if as advisory for provider values that are returned dynamically; maintain a small reviewed suppression list rather than ignoring broad change classes.

### Deployment strategy

- Use incremental deployments. Do not use complete mode against a shared resource group.
- Run bootstrap only through an approved bootstrap stage.
- Deploy infrastructure before access.
- Run access deployment with a separate identity and approval.
- Use stable deployment names containing environment, component, and source revision, not secrets.
- Capture only non-secret outputs and deployment/correlation IDs.
- Do not automatically add group members or execute acceptance tests as personal users from the infrastructure pipeline.

### Rollback

- The primary rollback is redeploying the last approved source revision after reviewing its reverse what-if.
- Roll back RBAC independently by redeploying the prior access definition or explicitly removing only the deterministic assignments introduced by the failed release.
- Never use resource-group deletion as routine rollback.
- A create-time networking or provider change that requires replacement needs a reviewed migration/recreation plan; do not permit CI to replace the Foundry account or data resources automatically.
- Preserve data with service recovery/versioning controls. Bicep rollback does not restore data-plane contents.
- If a deployment creates private endpoints but later steps fail, retain them unless their removal is explicitly reviewed; retry the idempotent deployment after correction.

### Idempotency

- Use deterministic resource names and role-assignment GUIDs.
- Avoid timestamps, random names, display-name discovery, and untracked deployment scripts.
- Model existing central network/DNS resources with explicit IDs and `existing` references.
- Keep arrays and maps stable and sorted.
- Make each module converge on declared state and expose IDs needed by later modules.
- Account for Entra/RBAC eventual consistency with bounded pipeline retries and diagnostics, not duplicate resources or arbitrary sleeps.
- Run a second no-change what-if after deployment; unexplained drift fails completion.

## 9. CI/CD identity and least privilege

Use workload identity federation from the protected CI platform; do not create client secrets, certificates, passwords, access keys, or credentials as part of this plan.

### Bootstrap operator

- Prefer a human using approved PIM activation for the rare subscription-scope bootstrap.
- If automated later, use a dedicated federated bootstrap identity with only resource-group/deployment actions required by the approved bootstrap template, ideally through a reviewed custom role.
- No Foundry data role or Microsoft Graph permission.

### Infrastructure identity

- Dedicated federated identity.
- Contributor only on the target environment resource group after bootstrap.
- Contributor cannot create Azure role assignments because of its built-in `NotActions`; retain that separation.
- No Foundry User role, no backing-resource data-plane role, and no Microsoft Graph permission.
- Private runner/network path must be able to reach management endpoints and any required private validation endpoints.

### Access identity

- Separate federated identity.
- Minimum deployment permission for `Microsoft.Resources/deployments` at the target resource group.
- Role Based Access Control Administrator only at the exact two project scopes and exact project-specific backing resources where it must create assignments. Prefer scope-specific assignments and Azure RBAC conditions where supported.
- No Contributor, Foundry User, Graph permission, or data-plane role.
- It cannot modify Foundry, network, Storage, Search, or Cosmos configuration.

### Approvals and controls

- Protect environment parameter files and workflow definitions with code owners.
- Require separate reviewers for infrastructure and access changes.
- Prevent pull-request jobs from using production federated identities.
- Bind federation claims to the repository, protected branch/tag, workflow, and protected environment.
- Retain sanitized deployment and what-if artifacts according to organizational policy.
- Review identity permissions periodically and after topology changes.

## 10. Milestones, dependencies, and estimates

Estimates are engineering effort ranges after subscription/tenant access is available; they exclude procurement, quota lead time, policy exceptions, and business approval.

| Milestone | Work | Dependencies | Estimate |
|---|---|---|---|
| M0 — Live provider/capability preflight | Reconcile schemas, provider/API support, region, models, quota, policies, private-link group IDs, network injection, role definitions, and connection behavior. | Target tenant/subscription and read access | 1–3 days |
| M1 — Repository and contracts | Add Bicep config, entry points, typed parameters/outputs, naming/tagging library, and compile-time tests. | M0 API choices | 1–2 days |
| M2 — Bootstrap/network/data modules | Implement resource group, network/DNS, separate project data modules, private endpoint modules, and diagnostics. | Network ownership and agent data pattern | 3–5 days |
| M3 — Foundry/projects/connections | Implement one account, two projects, outputs, managed identities, and secret-free project connections. | M0, M2, stable connection support | 2–4 days |
| M4 — Access modules | Implement project-MI permissions and exact project-scoped group assignments with deterministic IDs. | Verified object IDs and live role definitions | 1–3 days |
| M5 — CI validation and what-if | Add lint/build/validate, secret checks, template assertions, what-if policy, federated identity design, and approvals. | M1–M4 | 2–4 days |
| M6 — Controlled deployment and evidence | Bootstrap, deploy, rerun no-change what-if, inherited-access audit, positive tests, and strict sibling non-discoverability tests. | All prior milestones and test identities | 3–6 days |

Expected implementation and validation effort: approximately **12–27 engineering days**, with M0 and M6 carrying the largest external uncertainty.

## 11. Principal risks and responses

| Risk | Impact | Required response |
|---|---|---|
| Parent Reader is required for portal usability | Sibling metadata may be visible. | Do not grant it. Test API/SDK-first operation and escalate the locked-topology conflict. |
| Foundry/project schema differs between documentation, Bicep types, and target provider | Compile or deployment failure; property drift. | Pin only after M0 reconciles all three; use stable API and validation deployment. |
| Project connections require preview behavior or secret auth | Unsupported or insecure deployment. | Use stable managed-identity/AAD support only; block implementation otherwise. |
| Project identity requires account-scope permission | Potential sibling access. | Test project scope first; account scope requires explicit isolation proof or topology escalation. |
| Account-wide VNet injection reaches both data estates | Network path alone cannot enforce sibling isolation. | Separate stores, identities, connections, and RBAC; prove negative access. Escalate if L3 isolation is required. |
| `northcentralus` lacks exact model/evaluator/capacity | Deployment or evaluation cannot run. | Keep region gate open until live checks pass; region change requires design approval. |
| Built-in Foundry User permits ad hoc connections | Members may connect unapproved data. | Pre-create allowlisted connections; test Azure Policy/custom-role options without broadening access. |
| Graph group creation is coupled to Azure deployment | Excess Graph privilege and mismatched lifecycle. | Pre-provision groups; separate identity pipeline if Graph Bicep is ever adopted. |
| RBAC propagation causes transient failures | Connections/tests fail after a successful ARM deployment. | Bounded retry and fresh-token procedure; retain deterministic resources. |
| Shared monitoring reveals sibling data | Cross-project metadata leakage. | Admin-only monitoring, project attribution, no developer log access, and negative tests. |
| Rollback deletes data or identity objects | Irrecoverable loss or orphaned assignments. | Incremental deployment, previous-revision redeploy, independent access rollback, no automatic deletion. |

## 12. Traceability and acceptance gates

| Requirement | Planned implementation | Acceptance evidence/gate |
|---|---|---|
| One Foundry resource | `foundry/account.bicep`; one invocation per environment | Compiled template and what-if contain exactly one account; no replacement. |
| Exact two projects | `foundry/projects.bicep` with fixed names | Template assertion and outputs show exactly the two required child IDs. |
| Exact two Entra groups | Identity prerequisite and object-ID validation | Graph read proves exact display names/properties; no group is created by core ARM/Bicep. |
| Bicep standard | `infra/` entry points/modules and pinned toolchain | Lint/build/ARM validation pass; no Terraform or imperative provisioning path. |
| Strict sibling non-discoverability | Child-scope RBAC only; no parent Reader; separate assets | Portal, ARM, Foundry API, SDK/CLI, resource selector, deep-link, and error-detail negative tests pass with fresh tokens. |
| Private endpoints/DNS | Network, DNS, and private-endpoint modules | Public access disabled; DNS resolves to private IP; TCP 443 and service operations succeed from approved paths. |
| Project-specific data resources | Two invocations of `project-data.bicep` | Resource/connection inventories are disjoint; each project identity is denied sibling resources. |
| Project-specific connections | `project-connections.bicep` under each project | No account-level/shared connection; auth is managed identity/AAD; sibling listing/use denied. |
| Exact Foundry User assignments | `project-group-access.bicep` | Scope/role/principal triples match; inherited/transitive/PIM audit has no broader access. |
| No secrets or PII | Typed contracts, secret scan, managed identity | Source, compiled JSON, parameters, outputs, logs, and artifacts pass scanning. |
| Region `northcentralus` | Restricted location parameter | Live feature/model/quota/private-network checks pass before implementation. |
| Repeatability/idempotency | Deterministic names/IDs and incremental deployment | A second deployment succeeds and post-deployment what-if reports no unexplained change. |
| Least-privilege CI/CD | Separate bootstrap, infrastructure, and access identities using federation | Effective permission review proves no secrets, no Graph write permission, and separated Contributor/RBAC authority. |

### Definition of done

The Bicep implementation is complete only when:

1. all API/provider/region gates are recorded as passed with current evidence;
2. lint, build, ARM validation, template assertions, and secret scans pass;
3. reviewed what-if shows one Foundry account, two exact projects, separate project data resources/connections, private networking, and only exact child-scope member assignments;
4. deployment is repeatable and a second run has no unexplained changes;
5. group object IDs and live Foundry User role definition are verified;
6. public access and local/key authentication are disabled everywhere supported;
7. each project identity can use only its own backing resources;
8. each single-group user can perform approved own-project agent/evaluation operations;
9. each single-group user cannot discover or access the sibling through portal, ARM, Foundry API, SDK/CLI, connections, backing resources, logs, or error details;
10. no bootstrap elevation remains, and infrastructure/access identities retain only approved steady-state permissions;
11. the sanitized evidence pack is reviewed and Danny approves the deployment result.

## 13. References

- [Microsoft Foundry architecture](https://learn.microsoft.com/azure/foundry/concepts/architecture)
- [Microsoft Foundry RBAC](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry)
- [Foundry region support](https://learn.microsoft.com/azure/foundry/reference/region-support)
- [Foundry network isolation](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link)
- [Foundry agent virtual networks](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [Foundry account Bicep reference](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts)
- [Foundry project Bicep reference](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts/projects)
- [Foundry project connection Bicep reference](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts/projects/connections)
- [Bicep Azure RBAC guidance](https://learn.microsoft.com/azure/azure-resource-manager/bicep/scenarios-rbac)
- [Microsoft Graph Bicep permissions](https://learn.microsoft.com/graph/templates/bicep/concept-permissions-and-privileges)
- [Microsoft Graph group Bicep reference](https://learn.microsoft.com/graph/templates/bicep/reference/groups?view=graph-bicep-1.0)
