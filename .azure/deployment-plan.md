# Azure Deployment Plan

> **Status:** Ready for Validation

Generated: 2026-07-31  
Last updated: 2026-08-02T09:19:50-05:00

## 1. Approved scope

Extend the deployed `validation` environment with one small private Windows
validation VM for browser-based Foundry testing through the existing Standard
Azure Bastion host. The VM will have no public IP and will not modify Entra
group membership or Foundry project RBAC.

| Attribute | Confirmed value |
|---|---|
| Subscription | `<subscription-id>` |
| Tenant | `<tenant-id>` |
| Location | `northcentralus` |
| Resource group | `rg-foundry-permissions-validation` |
| Foundry topology | One account; `hoa-project` and `one-to-four-residential-contract-project` |
| Workload | Prompt agents and evaluations using an adapted official template 15 standard-agent setup |
| Network | New `192.168.0.0/16` VNet; agent `/24`, private endpoint `/24`, `AzureBastionSubnet` `/26`, validation `/27` |
| Access | Pre-created Entra groups supplied as immutable object IDs; Foundry User at exact project child scopes only |
| Model | Parameterized name, version, deployment names, GlobalStandard SKU, and capacity |
| Validation VM | `vm-validation-ov7f2p`; Windows Server 2022 Azure Edition; `Standard_B2s`; private NIC only |
| VM access | Existing Standard Bastion; passwordless Entra login; operator role at exact VM scope |
| Auto-shutdown | Daily `19:00`, `Central Standard Time`; notifications disabled |
| Portal compatibility exception | Project groups receive account-scope Reader so `ai.azure.com` can navigate/load project blades; this exposes sibling project discovery and is not strict non-discoverability |

Carol confirmed that `192.168.0.0/16` does not overlap connected or reserved networks.

## 2. Confirmed preflight

- Required providers are registered and North Central US supports the planned account, projects, prompt agents, evaluations, VNet injection, data services, Bastion, and monitoring resources.
- Capacity preflight found no blocker. The current validation candidate is `gpt-5.4-mini`, version `2026-03-17`, GlobalStandard, capacity 10 per deployment; this remains a parameter example, not an invariant.
- ProvisionedManaged is policy-denied and is excluded.
- Required Ignore tags suppress applicable governance Deploy/Modify controls.
  Public access, local authentication, and Foundry account/project diagnostics
  are therefore enforced explicitly in Bicep rather than delegated to policy.
- Current Owner authority is accepted only as a time-bound validation bootstrap exception. Steady state targets separate bootstrap, infrastructure, and access identities.
- Entra groups remain outside ARM. Both exact-name groups were independently
  verified and their object IDs were used only as ephemeral, redacted validation
  inputs; no object ID is embedded in repository files.
- Strict sibling non-discoverability remains a post-deployment release gate and is not claimed by template generation.

## 3. Accepted implementation decisions

- Use standalone Bicep with a subscription bootstrap entry point, a
  resource-group infrastructure entry point, a separate access entry point,
  and a separate required-parameter Windows validation VM entry point.
- Adapt official `15-private-network-standard-agent-setup`; do not use `add-project.bicep` shared backing-resource behavior.
- Use stable typed `Microsoft.CognitiveServices` API `2025-06-01` because the Bicep schema service currently exposes it for accounts, deployments, projects, connections, and capability hosts. Current Learn also lists it as stable.
- Keep `networkInjections` at account scope. For fresh injected accounts, rely on the platform-created account capability host to avoid the documented duplicate-host `409`; create one immutable project capability host per project.
- Use AAD project connections only. No keys, connection strings, SAS, passwords, private keys, tokens, list-key calls, or secret outputs.
- Deploy separate Storage, Search, Cosmos DB, Log Analytics, and Application Insights resources for each project.
- Use one private-only Azure Monitor Private Link Scope and one Azure Monitor private endpoint for both project-specific monitoring estates. Associate all five documented AMPLS private DNS zones, including the existing Blob zone. Central policy diagnostics remain separate.
- Use stable `Microsoft.Insights/privateLinkScopes@2021-09-01`; the schema MCP does not return this type, but current Microsoft Learn documents the stable API and its private-only access-mode properties.
- Isolate `Microsoft.Insights/diagnosticSettings@2021-05-01-preview` in the
  monitoring module because no stable diagnostic-settings API is available.
  Emit four unconditional settings: each project sends `allLogs` and
  `AllMetrics` to its matching workspace, while the shared account uses two
  uniquely named settings to send the same complete telemetry symmetrically to
  both isolated project workspaces. Do not accept or invent a central workspace
  ID.
- Deploy Standard Bastion with a static Standard public IP and the complete
  documented four-inbound/four-outbound NSG contract. The original unused
  optional Ubuntu/SSH VM path has been removed. The approved Windows VM is now
  a separate required-parameter deployment entry point, while the validation
  subnet evaluates a priority-100 exact-Bastion TCP 3389 allow before a
  priority-110 catch-all inbound deny. This overrides Azure's default
  priority-65000 `AllowVNetInBound` without changing existing outbound flows.

## 4. Security and access gates

- Public network access and local/shared-key authentication are disabled where supported.
- The Foundry account permits the documented trusted Azure services network ACL
  bypass (`AzureServices`) to support `ai.azure.com` portal resolver calls while
  public network access remains disabled, default action remains deny, and no
  IP or virtual network ACL allowlist is added.
- Storage enforces HTTPS, TLS 1.2+, no blob public access, and no shared-key
  access. Each project Storage account permits the documented trusted Azure
  services network ACL bypass (`AzureServices`) so Foundry evaluation asset and
  rubric generation services can create temporary data references while public
  network access remains disabled, default action remains deny, and no IP or
  virtual network ACL allowlist is added.
- Search uses Microsoft Entra authentication only.
- Cosmos DB disables local authentication and uses project-specific managed-identity access.
- Project managed identities receive roles only on their matching backing resources and matching project monitoring resources.
- Foundry human/group role assignments are emitted only by
  `infra\access.bicep`, use `principalType: Group`, and target exact project
  child IDs for Foundry User. The same access entry point also emits the
  documented portal-compatibility Reader assignment at the Foundry account
  scope for each project group; this enables `ai.azure.com` navigation but
  exposes sibling project discovery. Each project group also receives Search
  Service Contributor and Search Index Data Contributor only on its matching
  Search service so the Foundry IQ/Knowledge UI can list and create knowledge
  bases without granting sibling Search access. The separate VM entry point emits one
  `principalType: User` assignment for the ephemeral operator at exact VM scope.
- No developer access is assigned at subscription, resource-group, Foundry-account, backing-resource, DNS, or monitoring scope.

## 5. Generation checklist

- [x] Read approved planning, preflight, security, Foundry private-network, and secret-handling references
- [x] Confirm official template 15 and current Microsoft Learn guidance
- [x] Query Bicep schemas for Foundry accounts, deployments, projects, project connections, account/project capability hosts, and Azure AI Search
- [x] Record schema-tool limitation for Azure Monitor Private Link Scope and select the documented stable API
- [x] Generate `infra\bootstrap\main.bicep`
- [x] Generate `infra\main.bicep` and `infra\access.bicep`
- [x] Generate Foundry, data, network, monitoring, validation-host, and access modules
- [x] Generate safe validation parameter example and `bicepconfig.json`
- [x] Replace the unused Ubuntu/SSH path with a separate required-parameter Windows validation VM entry point
- [x] Add Windows VM, Entra login, VM-scoped operator RBAC, managed OS-disk tagging, and daily auto-shutdown assertions
- [x] Update the validation runbook with the portal Bastion and two-clean-identity browser procedure
- [x] Build/lint every entry point and parse generated ARM JSON locally
- [x] Record meaningful IaC decisions in `.squad\decisions\inbox\basher-generated-iac.md`
- [x] Complete independent reviewer approval after two lockout-enforced revisions
- [x] Set status to **Ready for Validation**

## 6. Generated files

| File | Purpose |
|---|---|
| `infra\bootstrap\main.bicep` | Subscription-scope resource-group bootstrap |
| `infra\main.bicep` | Resource-group infrastructure composition |
| `infra\access.bicep` | Separate exact-project group RBAC entry point |
| `infra\modules\foundry\account.bicep` | One private, local-auth-disabled Foundry account with account-level network injection |
| `infra\modules\foundry\model-deployments.bicep` | Two parameterized account-level GlobalStandard model deployments |
| `infra\modules\foundry\project.bicep` | Fixed project child creation with system-assigned identity |
| `infra\modules\foundry\project-connections.bicep` | Project-only AAD connections to data and monitoring |
| `infra\modules\foundry\project-capability-host.bicep` | One immutable Agents capability host per project |
| `infra\modules\data\project-data.bicep` | Separate Storage, Search, and Cosmos DB estate per project |
| `infra\modules\network\core-network.bicep` | New VNet, four subnets, delegation, and four NSGs |
| `infra\modules\network\private-dns.bicep` | Foundry, data, and Azure Monitor private DNS zones and links |
| `infra\modules\network\private-endpoints.bicep` | Foundry and project-data private endpoints and DNS zone groups |
| `infra\modules\monitoring\monitoring.bicep` | Separate project monitoring, four explicit Foundry account/project diagnostic settings, private-only AMPLS, and monitoring endpoint |
| `infra\modules\validation\bastion-host.bicep` | Existing Standard Bastion only; no VM credential surface |
| `infra\validation-vm.bicep` | Separate Windows VM deployment entry point with required secure password and ephemeral operator object ID |
| `azure.yaml` | Azure Developer CLI project file for `azd up` orchestration |
| `infra\azd\main.bicep` | Subscription-scope azd wrapper that deploys bootstrap, main infrastructure, access roles, and validation VM |
| `infra\azd\main.parameters.json` | azd ARM parameter file that reads group IDs, operator object ID, password, and location from azd environment variables |
| `infra\modules\validation\windows-vm.bicep` | Private Windows Server VM, NIC, Entra extension, VM-scoped login RBAC, OS-disk tags, and shutdown schedule |
| `infra\modules\access\project-managed-identity.bicep` | Project identity roles on matching backing resources only |
| `infra\modules\access\project-groups.bicep` | Exact project-scope Foundry User assignments |
| `infra\environments\validation.bicepparam.example` | Safe base-infrastructure example with no VM credential or operator ID |
| `infra\bicepconfig.json` | Core analyzer policy |
| `infra\tests\Assert-WindowsValidationVm.ps1` | Windows image, identity, disk, network, Entra, RBAC, shutdown, and no-Linux/SSH assertions |
| `.squad\decisions\inbox\basher-generated-iac.md` | Meaningful generation decisions |

## 7. Validation Proof (historical pre-tag-change evidence)

The evidence below is preserved from the artifact validated before the required
tagging change. It does not validate the current IaC revision.

- [x] All validation checks pass
  - [x] Core validation: bootstrap, infrastructure, and live access validation passed
  - [x] Bicep linting for every standalone and validation-only entry point
  - [x] Parameter compilation for the safe `.bicepparam.example`
  - [x] Azure Policy assignments retrieved and compatibility reviewed
  - [x] Static role assignment verification completed
  - [x] Exact-name Entra group shape and owner verification completed without recording object IDs
  - [x] No-change post-check confirmed validation and what-if created no resource group or deployment record

**Evidence timestamp:** `2026-08-01T04:40:54Z`  
**Azure context:** subscription `<subscription-id>`,
tenant `<tenant-id>`, region
`northcentralus`; the planned resource group remained absent.

### Commands and results

| Command | Result |
|---|---|
| `pwsh -NoProfile -File .\infra\tests\Invoke-LocalValidation.ps1` | **PASS**: all three implementation entry points built; secret-safety, identity-bootstrap, topology, and policy-compatibility assertions passed. |
| `az bicep lint --file <entry-point>` and `az bicep build --file <entry-point>` for bootstrap, infrastructure, access, and `infra\tests\subscription-validation-wrapper.bicep` | **PASS** with Bicep CLI `0.45.15`. |
| Temporary same-directory copy of `validation.bicepparam.example`; `az bicep build-params` | **PASS**; the temporary `.bicepparam` and compiled artifacts were removed. |
| Shared `validate-deployment.ps1 -Scope sub` against `infra\bootstrap\main.bicep` | **OVERALL: PASS**: CLI, authentication, build, subscription validation, and what-if passed. |
| Shared `validate-deployment.ps1 -Scope sub` against `infra\tests\subscription-validation-wrapper.bicep` | **OVERALL: PASS**: the absent resource group and `infra\main.bicep` validated at subscription scope without deployment. |
| `az deployment sub what-if ... --result-format ResourceIdOnly --no-pretty-print --output json` | **PASS**; authoritative counts recorded below. |
| Azure Policy MCP `policy_assignment_list` plus read-only `az policy assignment`, `definition`, `set-definition`, and `exemption` queries | **PASS**: eight effective assignments reviewed; no subscription exemption found. |
| `az role definition list --name <role-guid>` for all Azure RBAC GUIDs | **PASS**: all eight pinned GUIDs resolved to the expected live built-in roles. |
| `pwsh -NoProfile -File .\infra\tests\Assert-IdentityBootstrap.ps1 -SourcePath <repo>` | **PASS**: focused lockout assertions passed, including mocked post-create and rollback URI checks. |
| Read-only Microsoft Graph exact-name queries using an ephemeral `azd auth token` | **PASS**: each required name resolved exactly once; both groups are security-enabled, mail-disabled, assigned-membership groups; owner reads succeeded and showed one owner reference per group. Object IDs were retained only in process memory and were never printed or persisted. |
| Subscription-scope ARM `validate` and `whatIf` for a temporary wrapper around `infra\access.bicep` | **PASS** using ephemeral group IDs: validate succeeded; what-if proposed Create `3`, Modify `0`, Delete `0`. The temporary wrapper and compiled artifact contained no object IDs and were removed. |
| Read-only ARM post-check for the resource group and validation deployment name | **PASS**: the resource group remained absent and no deployment record existed. |
| In-process repository persistence scan using the independently resolved group IDs | **PASS**: neither object ID exists in repository files. |
| Deployment-plan capacity gate review | **NOT DUE FOR VALIDATED STATUS**: model capacity/quota recheck is explicitly retained for immediately before deployment. |

Compiled artifact SHA-256 values from the explicit build were:
bootstrap `ECA715D1CDECA81CFA32BA468F02FF3BE900EA9A17A36B2AA1245EC1B5021790`,
infrastructure `EC12746F4A187A0B5B77CE31B86471BA387907507F34CC7A530FAFAAA983A53A`,
access `C79107B81DE4DDF3727A39B01A666736C01173C9716A759887DE0ACCA03B6E89`,
and parameters `3482122876E439022DDAE6434552A1E93F56BD4459850E54FA45C539F00CEA5D`.

### Management-plane validation and what-if

| Scope | Validate | Authoritative what-if |
|---|---|---|
| Subscription bootstrap | **PASS** | Create `1`, Modify `0`, Delete `0`, Unsupported `0` |
| Subscription validation wrapper for resource-group infrastructure | **PASS** | Create `76`, Modify `0`, Delete `0`, Unsupported `16` |
| Access entry point through a temporary subscription validation wrapper | **PASS** | Create `3`, Modify `0`, Delete `0`; real group IDs were ephemeral and redacted |

The shared helper's text parser printed Create `2` for bootstrap and Create `77`
for infrastructure. JSON `changes[].changeType` is authoritative. The 16
infrastructure `Unsupported` changes are exactly the two project managed
identities' eight runtime-principal-dependent assignments each: seven Azure
RBAC assignments and one Cosmos DB native data-role assignment. No Modify or
Delete was proposed.

### Azure Policy validation

- Eight effective assignments were returned: five inherited management-group
  assignments and three subscription Defender initiatives; enforcement mode is
  `Default`.
- `ProvisionedManaged` is denied; the template allows only `GlobalStandard`.
- No effective allowed-location deny was found; `northcentralus` is not
  policy-blocked. `Standard_B2s` is outside the denied H/M/N VM SKU lists.
- Cognitive Services, Storage, and Cosmos local/public-auth modify policies
  align with explicit disabled public access, disabled local auth, and disabled
  Storage shared-key access. No `SecurityControl=Ignore` bypass tag is present.
- Governance policy deploys separate `allLogs`/`AllMetrics` diagnostics for the
  Foundry account and projects to the central `McapsGovernance` storage
  destination. The template's optional central-workspace diagnostics remain
  disabled, so no duplicate destination is asserted.
- No reviewed deny targets the planned resource types, private endpoints,
  private DNS zones, or subnet delegation. Baseline subnet NSG audit aligns
  with all four subnets having NSGs; the Foundry agent subnet has the required
  `Microsoft.App/environments` delegation.
- The public-IP append policy may add its governance IP tag; it does not require
  a template bypass or broaden network access.

### Role Assignment Verification

- **Status:** Static verification passed; live creation/effective-access proof
  remains a postdeployment gate as described below.
- **Project managed identities:** each project principal receives the same
  eight assignments only on its matching Storage, Search, Cosmos DB, and
  Application Insights resources. No assignment targets the sibling estate,
  resource group, subscription, shared Foundry account, DNS, or network.
- **Roles confirmed:** Storage Account Contributor plus Storage Blob Data Owner;
  Search Service Contributor plus Search Index Data Contributor; Cosmos DB
  Operator plus Cosmos DB Built-in Data Contributor; Monitoring Metrics
  Publisher plus Monitoring Reader. Management-plane roles are resource-scoped
  and paired with the required data-plane roles.
- **Developer groups:** `principalType: Group`; pinned live Foundry User GUID
  `53ca6127-db72-4b80-b1b0-d745d6d5456d`; HOA group scope is exactly
  `hoa-project`, and contract group scope is exactly
  `one-to-four-residential-contract-project`. No parent or sibling assignment
  is emitted.
- **Least-privilege caveat:** the live Foundry User role includes broad
  Cognitive Services reads/data actions and `listkeys/action`. Project scope,
  disabled local auth, and the clean-user sibling-isolation release gate remain
  mandatory; static validation does not claim feature authorization or
  non-discoverability.

### Retained predeployment and postdeployment gates

1. Record the approved split bootstrap/infrastructure/access identities or an
   explicit time-bound deployment exception before deployment.
2. Recheck model quota/capacity immediately before deployment. After deployment,
   perform private DNS/connectivity, effective role, clean-user positive access,
   sibling non-discoverability, and cross-project managed-identity denial tests.

No implementation defect was found in that previously validated artifact. The
subsequent required-tag change returns the current plan to **Ready for
Validation** and does not authorize deployment or satisfy any retained
predeployment or postdeployment release gate.

## 8. Required-tag change awaiting revalidation

Carol's mandatory directive was attested at
`2026-08-01T00:56:55.852-05:00` and is recorded in
`.squad\decisions\inbox\copilot-directive-2026-08-01-required-ignore-tags.md`.
It governs regardless of the earlier policy assessment; neither required tag
may be omitted.

- [x] Lock `SecurityControl=Ignore` and `CostControl=Ignore` after caller tags
  in both bootstrap and infrastructure entry points.
- [x] Pass the protected common tag object through all nested modules.
- [x] Cover resource-group bootstrap, conditional validation resources, private
  DNS virtual network links, and Foundry capability-host property tags.
- [x] Preserve existing environment, workload, ownership, region,
  data-boundary, criticality, and other caller-supplied governance tags.
- [x] Add static coverage for every taggable resource declaration and an
  explicit allowlist for known non-taggable child/extension types.
- [x] Replace the suppressed policy-owned diagnostics assumption with four
  unconditional Bicep diagnostic settings.
- [x] Route each project only to its matching Log Analytics workspace and route
  the shared account symmetrically to both workspaces with unique setting names.
- [x] Enable `allLogs` and `AllMetrics` on every explicit setting without a
  central workspace parameter.
- [x] Re-run local Bicep build/lint and targeted static tests after the
  telemetry mitigation.
- [x] Reviewer re-runs Azure validation and what-if; no deployment is
  authorized by this plan.

The earlier hashes, what-if counts, policy review, and validation proof remain
historical evidence only. The proof below is authoritative for the tagged
telemetry-mitigated revision.

Telemetry-mitigation local result: **PASS** with Bicep CLI `0.45.15`.
Bootstrap, infrastructure, and access entry points built; bootstrap,
infrastructure, access, and the subscription validation wrapper linted; the
validation parameter example compiled; and all secret-safety,
identity-bootstrap, required-tag, topology, explicit-diagnostics, and
policy-compatibility assertions passed. No Azure validation, what-if,
deployment, resource creation, Graph write, or secret access was performed.

### Final tagged-revision validation proof

**Evidence timestamp:** `2026-08-01T01:18:04-05:00`  
**Independent result:** **APPROVE**  
**Tooling:** Azure CLI `2.81.0`; Bicep CLI `0.45.15`

- Full local validation passed: secret-safety, identity-bootstrap,
  required-tag inventory, topology, explicit diagnostics, and policy
  compatibility.
- Bootstrap, infrastructure, access, and the subscription validation wrapper
  linted and built. The validation parameter example compiled.
- Compiled SHA-256 values:
  - bootstrap: `D3108EA1FBD8F9D186E7C3301BA7855F7590ED49F0582CF62C0B5D51989D14A8`
  - infrastructure: `5C2C52306BB9257BD83EF9182753350CB6488987231327C2E4CBCAE08A4B3F32`
  - access: `C79107B81DE4DDF3727A39B01A666736C01173C9716A759887DE0ACCA03B6E89`
  - subscription validation wrapper:
    `255131596A776573889086E2814AD87C7DBEAD8AF8803B4DFC66BA38EA7EEC88`
  - validation parameters:
    `A048B52770162CA9AE3993663A428910A3419DDDAE47278A8ED84B5531572996`
- Read-only ARM validation and authoritative what-if passed:

| Scope | Validate | Create | Modify | Delete | Unsupported |
|---|---:|---:|---:|---:|---:|
| Subscription bootstrap | PASS | 1 | 0 | 0 | 0 |
| Subscription infrastructure wrapper | PASS | 80 | 0 | 0 | 16 |
| Subscription access wrapper | PASS | 3 | 0 | 0 | 0 |

The four-resource increase from the earlier infrastructure proof is exactly the
four unconditional Foundry account/project diagnostic settings. The 16
unsupported changes remain the runtime-principal-dependent project managed
identity assignments.

Both required groups resolved exactly once, passed immutable shape checks, and
were supplied only as ephemeral in-process validation parameters. Their object
IDs were not printed or persisted. The planned resource group remained absent,
and validation/what-if left no subscription deployment records.

Effective policy versions were rechecked: MCAPS Audit, Deploy/Modify, and Deny
remain `20260629-1` with enforcement `Default`; Azure Security Baseline is
`57.58.0`. The mandatory Ignore tags suppress applicable MCAPS Modify/Deploy
controls, including policy-owned diagnostics, but do not suppress the reviewed
MCAPS Audit initiative, Azure Security Baseline, or Block Azure RM Resource
Creation. Explicit Bicep hardening and four diagnostics are therefore mandatory
compensating controls.

## 9. Deployment authorization resolution

Carol supplied explicit deployment authorization for the confirmed
subscription, tenant, `northcentralus`, and
`rg-foundry-permissions-validation`, including cost/security impact and the
time-bound current-Owner exception. Immediately before deployment, the active
context, providers, regional model catalog, quota, resource-group state,
deployment-name state, and both exact Entra groups were rechecked. The model
quota showed 1,000 available units against 20 required.

## 10. Deployment execution

**Execution completed:** `2026-08-01T10:19:53-05:00`

### Stage results

| Stage | Deployment name | Terminal result |
|---|---|---|
| Subscription bootstrap | `fpval-bootstrap-20260801T132727Z` | **Succeeded** |
| Infrastructure, initial attempt | `fpval-infrastructure-20260801T132727Z` | **Failed**; retained for diagnostics |
| Infrastructure, retry 1 | `fpval-infrastructure-retry1-20260801T132727Z` | **Failed**; retained for diagnostics |
| Infrastructure, corrected retry | `fpval-infrastructure-retry2-20260801T132727Z` | **Succeeded** |
| Project access | `fpval-access-20260801T132727Z` | **Succeeded** |

All three required stages reached a successful terminal outcome. No resource,
resource group, deployment record, or role assignment was deleted.

### Predeployment and revalidation proof

- Final predeployment what-if matched the validated proof exactly:
  bootstrap Create `1`; infrastructure Create `80` plus Unsupported `16`;
  access Create `3`; all scopes Modify `0`, Delete `0`.
- After surgical remediation, the local validation suite, all entry-point
  linting, validation-parameter compilation, ARM validation, and resource-group
  what-if passed.
- Final deployed-state what-if is no-change: bootstrap Create/Modify/Delete
  `0/0/0`; infrastructure `0/0/0` with Deploy `79`, Unsupported `16`, Ignore
  `11`; access `0/0/0`.
- The `ProjectManagedIdentity` connection auth value produces a Bicep type
  warning because the current local schema is behind the live API. The live API
  explicitly required this value, ARM accepted it, and deployment succeeded.

### Failures and safe remediation

1. The initial infrastructure attempt found that `Standard_ZRS` is not
   available for `StorageV2` accounts in North Central US, although the generic
   storage SKU listing includes ZRS for the legacy `Storage` kind. Deployment
   parameters and defaults were changed to the already allowed,
   lower-cost `Standard_LRS` SKU.
2. Concurrent account-level model deployment writes returned a parent-resource
   conflict. The deployment collection now uses `@batchSize(1)` to serialize
   those writes without changing model, version, SKU, or capacity.
3. The live Foundry API rejected `AAD` for Application Insights project
   connections and required `ProjectManagedIdentity`. Only those two
   monitoring connections were corrected; all other AAD connections remain
   unchanged.
4. Three platform-created, taggable smart-detection resources lacked the two
   mandatory tags. `SecurityControl=Ignore` and `CostControl=Ignore` were
   merged onto them after creation.

No security control was weakened, no region or subscription changed, no SSH
key was created, and no RBAC scope was broadened. Group object IDs and all
principal IDs remained ephemeral and a repository scan found no persisted
matches.

### Safe outputs and resource counts

- Foundry account: `aifpvalov7f2p`
- Projects: `hoa-project`,
  `one-to-four-residential-contract-project`
- Model deployments: `hoa-gpt-5-4-mini`,
  `contract-gpt-5-4-mini`; both `gpt-5.4-mini` version `2026-03-17`,
  `GlobalStandard`, capacity `10`, provisioning state `Succeeded`
- Validation VM deployed: `false`
- Project endpoints:
  - `https://aifpvalov7f2p.services.ai.azure.com/api/projects/hoa-project`
  - `https://aifpvalov7f2p.services.ai.azure.com/api/projects/one-to-four-residential-contract-project`
- ARM-listed resources: `60`
- Additional verified child/extension resources: model deployments `2`,
  project connections `8`, project capability hosts `2`, diagnostic settings
  `4`, private-endpoint DNS zone groups `8`, AMPLS scoped resources `4`, Blob
  services `2`, Azure role assignments `16`, Cosmos DB native role assignments
  `2`
- Verified footprint: `108` resources

### Live verification

- Mandatory tags: **PASS**, `60/60` ARM-listed resources.
- Foundry: **PASS**, one hardened account and both exact system-identity
  projects succeeded.
- Data estates: **PASS**, two Storage (`Standard_LRS`), two Search, and two
  Cosmos DB resources; public access/local or shared-key authentication is
  disabled as applicable. Blob versioning, change feed, and delete retention
  are enabled.
- Foundry composition: **PASS**, two model deployments, eight project
  connections, and two project capability hosts.
- Network: **PASS**, one four-subnet VNet, four NSGs, eight approved private
  endpoints, ten private DNS zones, ten VNet links, and fourteen private DNS
  zone configurations.
- Bastion: **PASS**, Standard SKU with the required NSG contract. No validation
  VM or validation NIC exists.
- Monitoring: **PASS**, two project workspaces, two Application Insights
  components, private-only AMPLS with four scoped resources, and exactly four
  `allLogs`/`AllMetrics` diagnostic settings.
- Developer RBAC: **PASS**, each exact group has one Foundry User assignment
  only at its matching project. There is no developer assignment at account,
  resource-group, or subscription scope.
- Project managed identities: **PASS**, each has seven Azure roles plus one
  Cosmos DB native data role on its matching data estate only; no unexpected
  or sibling-estate assignment was found.
- Active deployments: `0`.

### Remaining postdeployment release gates

1. Private DNS resolution, TCP 443, and authenticated own-project operations
   must be tested from an approved private client. The validation VM was
   intentionally omitted because no pre-approved SSH public key was supplied.
2. Public-path failure must be proven from a client without the private route
   or private DNS.
3. Run the clean-user own-project positive tests, sibling non-discoverability
   tests, prompt-agent/evaluation CRUD matrix, fresh-token/PIM audit, and
   cross-project managed-identity denial tests.
4. The live connection API reports `peRequirement=NotRequired` even though the
   template requested `Required`. All backing services are private-only and all
   eight private endpoints are approved, but the private-connectivity tests
   above remain the release gate for this platform normalization.
5. End the time-bound Owner exception and establish the intended split
   bootstrap, infrastructure, and access deployment identities before any
   steady-state or production use.

## 15. Approved Windows validation VM addition

**Requested:** `2026-08-02T08:54:16.190-05:00`
**Approval status:** Approved by Carol Garcha
**Preparation status:** **Ready for Validation**; no Azure or Graph mutation performed

### Approved and prepared change

- Replace the unused optional Ubuntu/SSH validation-host path with one
  Windows Server 2022 Datacenter: Azure Edition validation VM sized
  `Standard_B2s`.
- Attach one private NIC to the existing `validation-subnet`; no public IP.
- Permit inbound TCP 3389 only from the exact `AzureBastionSubnet` prefix,
  followed by the existing catch-all inbound deny.
- Retain the existing Standard Bastion host and private DNS links.
- Install `AADLoginForWindows` and enable a system-assigned managed identity.
- Assign `Virtual Machine Administrator Login` only to the approved deployment
  operator at the exact VM scope, using an ephemeral principal object ID.
- Use Microsoft Entra passwordless authentication through the Azure portal;
  generate any required emergency local-admin credential only as a secure,
  ephemeral deployment parameter and never commit or record it.
- Apply all required tags, including `SecurityControl=Ignore` and
  `CostControl=Ignore`.
- Use a Standard SSD OS disk and no data disk.
- Enable daily auto-shutdown at `19:00` using
  `Central Standard Time`, with email and webhook notifications disabled.

### Security and cost impact

- Adds ongoing Windows VM compute and OS-disk charges until stopped or deleted.
- Adds one VM, one NIC, one OS disk, one Entra login extension, and one
  VM-scoped login role assignment.
- The VM can reach private Foundry and backing-service endpoints and is
  therefore an approved administrative test client. It must contain no live
  customer documents, saved browser passwords, tokens, or persistent test
  evidence.
- The VM will be used only to launch an InPrivate browser for the two clean
  test identities. Those identities remain members only of their respective
  Foundry groups and receive no VM or parent-scope Azure role.
- Trusted Launch, Secure Boot, vTPM, managed boot diagnostics, automatic OS
  updates, and VM-agent extension operations are enabled.
- The emergency local administrator password is a required `secureString` with
  no default or output. The operator object ID is also required with no
  default. Neither appears in the checked-in parameter example.
- The existing validation-subnet outbound contract is unchanged so Windows
  activation, Microsoft Entra registration/login, Azure management, private
  DNS, HTTPS browser access, and stateful return traffic retain their current
  behavior.

### Prepared architecture

- Live read-only naming confirmed suffix `ov7f2p`; the deterministic resources
  are `vm-validation-ov7f2p`, `nic-validation-ov7f2p`,
  `osdisk-validation-ov7f2p`, and
  `shutdown-computevm-vm-validation-ov7f2p`.
- `infra\main.bicep` continues to own the deployed shared infrastructure and
  changes only the validation NSG SSH rule to the approved Bastion-only RDP
  rule.
- `infra\validation-vm.bicep` is a separate resource-group entry point. This
  keeps the safe checked-in base parameter example compilable without making a
  VM deployable using placeholders.
- The VM entry point requires `validationAdminPassword` and
  `operatorObjectId`; deployment must supply both ephemerally.
- The VM module uses `Microsoft.Compute/virtualMachines@2024-11-01`,
  `Microsoft.Compute/virtualMachines/extensions@2024-11-01`,
  `Microsoft.Authorization/roleAssignments@2022-04-01`,
  `Microsoft.DevTestLab/schedules@2018-09-15`, and
  `Microsoft.Resources/tags@2023-07-01`.
- The image URN
  `MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest`
  resolved in `northcentralus` to a Generation 2 x64 image; the latest
  observed version during preparation was `20348.5386.260711`.
- `Standard_B2s` is available in `northcentralus`, has no listed restriction,
  supports Generation 2, and belongs to a Trusted Launch-supported family.
- The `AADLoginForWindows` image catalog exposes handler `2.2.0.0`; Bicep uses
  `typeHandlerVersion: '2.2'` with automatic minor version upgrades. The
  provider rejects `enableAutomaticUpgrade`, so the extension omits it.
- The live built-in role lookup confirmed
  `Virtual Machine Administrator Login`
  (`1c0163c0-47e6-4577-8991-ea5c82e286e4`).
- Because a VM-created managed OS disk does not inherit VM tags reliably, a
  post-VM `Microsoft.Resources/tags` extension applies the locked tag object to
  the deterministic OS disk.

### Prepared files

- `infra\validation-vm.bicep`
- `infra\modules\validation\windows-vm.bicep`
- `infra\modules\validation\bastion-host.bicep`
- `infra\modules\network\core-network.bicep`
- `infra\main.bicep`
- `infra\environments\validation.bicepparam.example`
- `infra\tests\subscription-validation-wrapper.bicep`
- `infra\tests\Assert-WindowsValidationVm.ps1`
- `infra\tests\Assert-Template.ps1`
- `infra\tests\Assert-NoSecrets.ps1`
- `infra\tests\Assert-RequiredTags.ps1`
- `infra\tests\Invoke-LocalValidation.ps1`
- `docs\runbooks\validation.md`

### Local preparation proof

- Read-only Azure inspection confirmed the approved subscription, tenant,
  `northcentralus`, existing resource group, existing
  `bas-validation-ov7f2p`, existing validation NSG, and absence of any
  validation VM or user-created validation NIC.
- Current live validation NSG state was the historical priority-100
  Bastion-originated TCP 22 allow plus priority-110 deny; no live change was
  made.
- Bicep CLI `0.45.15` linted and built bootstrap, infrastructure, access,
  Windows VM, and subscription-validation entry points.
- Final compiled SHA-256 values were bootstrap
  `D3108EA1FBD8F9D186E7C3301BA7855F7590ED49F0582CF62C0B5D51989D14A8`,
  infrastructure
  `37D4E8AE2F98554CC6912C0D4995E39309D56EC1D7079E8AE108526B4623F098`,
  access
  `C79107B81DE4DDF3727A39B01A666736C01173C9716A759887DE0ACCA03B6E89`,
  Windows VM
  `95989AEDA01FAB6839127E56057B5B34B963323D6831DCB5D25E399548681F56`,
  subscription wrapper
  `342883DC7C05B3725AD45036CB9516E468F54006DD94BFE93D0E28DFDEFA1574`,
  and parameters
  `E14DD6D944A58B402EEFCA255FB0F89D16F9683823497E222997D4A602D73094`.
- The safe `validation.bicepparam.example` compiled successfully and contains
  no VM password, SSH key, or operator object ID.
- `Invoke-LocalValidation.ps1` passed secret-safety, identity-bootstrap,
  required-tag, topology, Windows VM, Defender, and policy-compatibility
  assertions.
- The only compiler diagnostic is the preserved pre-existing
  `ProjectManagedIdentity` schema warning in
  `project-connections.bicep`; no new warning or error was introduced.
- Repository scans found no committed VM password, operator object ID, SSH
  parameter surface, Ubuntu image, or Linux VM profile.

### Expected Azure what-if shape

1. Existing infrastructure entry point:
   - one actionable validation NSG modification, replacing
     `AllowSshFromBastion` TCP 22 with `AllowRdpFromBastion` TCP 3389;
   - no VM, NIC, RBAC, data, Foundry, Bastion, private DNS, public IP, or
     outbound-network create/delete;
   - provider normalization and runtime-principal `Unsupported` entries must
     remain separately classified against the historical baseline.
2. Separate validation VM entry point:
   - create one private NIC;
   - create one system-identity Trusted Launch Windows VM with its managed
     Standard SSD OS disk and no data disk;
   - create one OS-disk tag application, one `AADLoginForWindows` extension,
     one exact-VM-scope `Virtual Machine Administrator Login` assignment for
     the ephemeral user object ID, and one enabled notification-disabled
     shutdown schedule;
   - no public IP, broader role assignment, unrelated modify, or delete.

### Required workflow

1. [x] Confirm subscription, region, Entra-login operator interface, and
   cost/security impact.
2. [x] Update Bicep, static tests, parameter example, and validation runbook.
3. [x] Set this plan to **Ready for Validation**.
4. [ ] Run the complete `azure-validate` workflow and require what-if to show only
   the approved VM-related additions and NSG rule replacement.
5. [ ] Run `azure-deploy` only after validation succeeds and separate approval.
6. [ ] Verify Bastion Entra login, no public IP, private DNS/TCP 443, mandatory
   tags, and no unexpected RBAC or resource drift.

## 11. Independent live verification

**Reviewer:** Linus  
**Evidence timestamp:** `2026-08-01T11:29:51-05:00`  
**Release verdict:** **REJECT**

### Deployment lineage and retry review

- The repository has no commits and all current files are untracked, so
  `git diff` is empty and cannot establish history. Deployment exports,
  timestamps, activity logs, and current local builds were used instead.
- The initial and first-retry templates are identical. The initial attempt used
  `Standard_ZRS` and failed both Storage creations with `LocationNotValid`;
  concurrent model writes also failed with `RequestConflict`.
- Retry 1 changed the deployment parameter to `Standard_LRS`. Both Storage
  accounts then succeeded, but concurrent model writes still conflicted and
  both Application Insights connections rejected `AAD`.
- The successful retry contains the two required repository corrections:
  serialized model deployment writes and `ProjectManagedIdentity` for the two
  monitoring connections. ARM validation succeeded and what-if ran before the
  successful retry was started.
- The current repository differs from the successful exported infrastructure
  template only in the Storage parameter default: the successful deployment
  template retained `Standard_ZRS`, while the live retry explicitly supplied
  `Standard_LRS` and the repository default was corrected afterward. Current
  local validation passes. The earlier statement that both parameter and
  default changed before retry should therefore be read with this chronology.
- Bootstrap succeeded with two successful operations. Infrastructure attempts
  ended `Failed`, `Failed`, then `Succeeded`; access succeeded. All were
  incremental, all operations are terminal, and no deployment operation or
  activity-log event performed a delete.

### Verified controls

- The intended Foundry topology, project data separation, two model
  deployments, eight approved private endpoints, ten private DNS zones,
  Standard Bastion, and four exact `allLogs`/`AllMetrics` diagnostic settings
  are present and succeeded.
- Foundry, Storage, Search, Cosmos DB, Log Analytics, Application Insights, and
  AMPLS retain the required public-network and local-auth hardening.
- URL-form account, project, Storage, Search, Cosmos DB, and connection
  endpoints use `https://`. Monitoring connections correctly use ARM resource
  IDs rather than endpoint URLs.
- Both Entra groups resolve exactly once. Each has one `Foundry User`
  assignment only at its matching project. Each project identity has seven
  matching Azure roles and one matching Cosmos DB native role, with no sibling
  or broader assignment. No group or principal identifier was persisted.
- Mandatory tags pass on the resource group, the original 60 ARM-listed
  resources, and both model deployments. Azure-created capability hosts,
  connection resources, diagnostic settings, role assignments, DNS records,
  and similar extension children do not expose owner-supplied ARM tags.
- One expected platform-created account capability host exists. It was omitted
  from the reported 108-resource snapshot and is not an orphan.

### Blocking postdeployment drift

After the reported completion, subscription-level Defender for Storage V2
auto-provisioning modified both Storage accounts. It enabled Defender, on-upload
malware scanning with a 10,000-GB monthly cap, and sensitive-data discovery,
then created one Event Grid system topic and one antimalware event subscription
per account.

This is unplanned cost and resource drift. The ARM-listed inventory increased
from 60 to 62, and both new taggable system topics lack
`SecurityControl=Ignore` and `CostControl=Ignore`. The reported 108-resource
snapshot and 60/60 tag result are therefore no longer current. No deletion
occurred, but the late application-identity writes violate the required stable,
fully tagged deployed state.

### Safe remediation required

1. Have the subscription security and cost owners explicitly choose and record
   whether these two accounts are included in Defender for Storage.
2. If excluded, apply an approved per-account Defender override and remove the
   generated Defender settings, system topics, and event subscriptions through
   controlled change. If retained, accept the cost, codify the resources, and
   automatically apply both mandatory tags to the system topics.
3. Wait for auto-provisioning to stabilize, confirm no further unexpected
   writes, refresh the inventory, and rerun the complete read-only verification.
4. Correct the retry chronology and live resource-count evidence in this plan.

No Azure, Entra, group-membership, or RBAC mutation was performed by the
independent reviewer.

### Tests still requiring private access and clean identities

- Private DNS resolution, TCP 443, and authenticated own-project operations
  from an approved private client.
- Public-path denial from a client without the private route or private DNS.
- Clean non-admin HOA-only and contract-only positive tests, sibling
  non-discoverability/denial, agent and evaluation CRUD, fresh-token/PIM
  verification, and cross-project managed-identity denial tests.

## 12. Defender for Storage remediation validation

**Requested by:** Carol Garcha  
**Authorized option:** `disable_and_remove`  
**Mutation status:** Not deployed; no resource was deleted or modified during
this revision.

### Read-only live finding

The two project Storage accounts currently inherit the subscription-level
Defender for Storage V2 plan. Each live
`Microsoft.Security/defenderForStorageSettings/current` resource has Defender
enabled, `overrideSubscriptionLevelSettings=false`, on-upload malware scanning
enabled with a 10,000-GB monthly cap, and sensitive-data discovery enabled.

Activity-log writes occurred after the successful infrastructure deployment.
The successful infrastructure deployment contains no `Microsoft.Security` or
`Microsoft.EventGrid` operation. The later application-identity sequence was:

1. update each Defender for Storage setting;
2. write one `StorageAntimalwareSubscription` event subscription per account;
3. write one Event Grid system topic per account; and
4. complete the Defender settings writes.

The exact cleanup targets, recorded by name rather than full resource ID, are:

| System topic | Type | Storage source | Child subscription |
|---|---|---|---|
| `stfpvalcontractov7f2p-915fd48a-946d-4505-aef4-279c92af0cd4` | `Microsoft.EventGrid/systemTopics` | `stfpvalcontractov7f2p` | `StorageAntimalwareSubscription` |
| `stfpvalhoaov7f2p-58d779d0-fdf7-40c1-9b50-86066dbfc22c` | `Microsoft.EventGrid/systemTopics` | `stfpvalhoaov7f2p` | `StorageAntimalwareSubscription` |

Both topics are untagged. No unrelated Event Grid topic is in the resource
group.

### IaC decision and security reduction

The remediation uses the latest live-provider stable API,
`Microsoft.Security/defenderForStorageSettings@2025-06-01`, as a non-taggable
extension resource at each Storage-account scope. The resource name is
`current`.

The per-account configuration explicitly sets:

- `overrideSubscriptionLevelSettings=true`;
- `malwareScanning.onUpload.isEnabled=false`;
- `isEnabled=true`; and
- `sensitiveDataDiscovery.isEnabled=true`.

This is narrower than disabling the entire Defender for Storage plan. Microsoft
documents that individual accounts can override inherited subscription
settings and can independently disable malware scanning. Microsoft also
documents that the automatically created Event Grid system topic listens for
blob-upload events and triggers on-upload malware scanning. Therefore disabling
on-upload scanning is the minimum setting that removes the trigger for topic
recreation while retaining Defender threat detection and sensitive-data
discovery.

The accepted security reduction is that new or modified blobs in these two
accounts will no longer receive Defender on-upload malware scanning. Defender
for Storage threat detection and sensitive-data discovery remain enabled.

Official references:

- [Microsoft.Security/defenderForStorageSettings 2025-06-01](https://learn.microsoft.com/azure/templates/microsoft.security/2025-06-01/defenderforstoragesettings)
- [Override Defender for Storage subscription-level settings](https://learn.microsoft.com/azure/defender-for-cloud/advanced-configurations-for-malware-scanning#override-defender-for-storage-subscription-level-settings)
- [Resources deployed by malware scanning](https://learn.microsoft.com/azure/defender-for-cloud/introduction-malware-scanning#resources-deployed-by-malware-scanning)

### Governance compatibility

The subscription remains on Defender for Storage V2 with on-upload malware
scanning and sensitive-data discovery enabled by default. Effective policy
state for both Storage accounts contains storage hardening audit/modify
controls, but no policy state that deploys or modifies
`defenderForStorageSettings`. The documented per-account override prevents the
subscription settings from overrunning the explicit account configuration.

### Validation gates

- [x] Read-only inventory and deployment-operation attribution
- [x] Current stable resource/API and override semantics confirmed
- [x] Explicit per-account on-upload malware-scanning opt-out added to Bicep
- [x] Defender extension resource classified as non-taggable
- [x] Dedicated static test requires exactly two overrides, on-upload scanning
  disabled, no scan-result Event Grid destination, and no invalid tags
- [x] Local Bicep build and static validation
- [x] Entry-point lint/build and validation-parameter compilation
- [x] Repository secrets scan
- [x] Azure resource-group validation
- [x] Azure resource-group what-if reviewed for only the two Defender setting
  modifications and no application-resource delete

### Remediation validation proof

Validation completed against the confirmed subscription, tenant, region, and
existing resource group without starting a deployment:

| Check | Result |
|---|---|
| Local validation | **PASS**: all three implementation entry points built; secret-safety, identity-bootstrap, required-tag, topology, policy-compatibility, and Defender opt-out assertions passed. |
| Bicep lint/build | **PASS**: bootstrap, infrastructure, access, and subscription validation wrapper linted and built with Bicep CLI `0.45.15`. The existing live-API `ProjectManagedIdentity` schema warning remains unchanged. |
| Parameter compilation | **PASS**: a repository-local temporary copy of `validation.bicepparam.example` compiled successfully and was removed. |
| Secrets scan | **PASS**: repository source and compiled-template checks found no committed secret material or tenant-specific group/principal IDs. |
| ARM validation | **PASS**: resource-group validation returned `Succeeded`. |
| Authoritative ResourceIdOnly what-if | **PASS**: Deploy `81`, Ignore `13`, Unsupported `16`, Create `0`, Modify `0`, Delete `0`. |
| Pre-remediation scratch baseline | Deploy `79`, Ignore `13`, Unsupported `16`. The revised template adds exactly two deploy entries. |
| Full-payload differential | Revised: Modify `59`, NoChange `22`, Ignore `13`, Unsupported `16`; scratch baseline: Modify `57`, NoChange `22`, Ignore `13`, Unsupported `16`. The only two additional modifications are the two `Microsoft.Security/defenderForStorageSettings/current` resources. |

For both Defender resources, full-payload what-if showed:

- before: `isEnabled=true`,
  `overrideSubscriptionLevelSettings=false`,
  `malwareScanning.onUpload.isEnabled=true`;
- after: `isEnabled=true`,
  `overrideSubscriptionLevelSettings=true`,
  `malwareScanning.onUpload.isEnabled=false`,
  `sensitiveDataDiscovery.isEnabled=true`.

No application resource has an added Create/Modify/Delete delta, no resource
delete is proposed, RBAC code is unchanged, and the static least-privilege role
assertions still pass. The full-payload provider normalization produces the
same 57 pre-existing Modify entries in the scratch baseline; the two-entry
differential is the remediation.

A final read-only post-check found no new deployment record. Both live settings
remain inherited with on-upload scanning enabled, and both system topics remain
present, confirming that validation and what-if did not mutate Azure.

### Remediation execution evidence

**Execution status:** **Deployed; cleanup complete**  
**Executed:** `2026-08-01T15:02:04-05:00`  
**Deployment:** `fpval-defender-remediation-20260801T200131Z`

- Active Azure context matched the approved subscription and tenant. Live
  owner-managed tags resolved exactly one HOA and one contract project Storage
  account; no target name was guessed.
- A repository-local, execution-only Bicep entry point referenced those two
  existing accounts and declared only their two
  `Microsoft.Security/defenderForStorageSettings@2025-06-01/current`
  resources. Local lint/build and the dedicated Defender assertion passed.
- Dedicated ARM validation succeeded. ResourceIdOnly what-if reported
  Deploy `2`, Ignore `62`, Create/Modify/Delete `0/0/0`. Full-payload what-if
  reported exactly two actionable Modify entries, both Defender settings;
  all 62 other resources were Ignore. No application, RBAC, network, data,
  tag, diagnostic, or delete action was proposed.
- The incremental deployment reached terminal `Succeeded` in about 14 seconds.
  Its only resource operations were the two Defender settings.
- Both accounts now report Defender enabled, subscription override enabled,
  on-upload malware scanning disabled, and sensitive-data discovery enabled.
  No scan-results Event Grid destination is configured. Storage public access,
  shared-key access, default-deny ACLs, and empty IP/VNet rule sets remained
  unchanged. Storage trusted-services bypass is now an explicit validation
  exception for Foundry evaluation asset/rubric generation.
- The two previously validated system topics still mapped one-to-one to the
  two project Storage sources and had only
  `StorageAntimalwareSubscription` children before deployment. Defender
  removed both topics and their children automatically immediately after the
  settings changed; therefore no manual delete command was issued.
- A 502-second, ten-sample stabilization poll found zero system topics and
  stable Defender overrides at every sample. A later final check found zero
  topic-recreation writes, zero active deployments, and the same disabled
  scanning state.

### Refreshed live verification

- ARM-listed inventory returned to the planned `60` resources and contains no
  Event Grid system topic.
- Mandatory tags pass on all `57` owner-managed listed resources. The three
  Azure-created smart-detection resources retain both locked governance tags.
- Verified footprint is `113`: ARM-listed `60`; model deployments `2`;
  project connections `8`; project capability hosts `2`; diagnostic settings
  `4`; private-endpoint DNS zone groups `8`; AMPLS scoped resources `4`; Blob
  services `2`; Azure role assignments `18`; Cosmos DB native assignments
  `2`; Defender settings `2`; and the platform account capability host `1`.
- Security and topology pass: one private/local-auth-disabled Foundry account,
  two exact projects, two succeeded GlobalStandard model deployments, two
  hardened Storage/Search/Cosmos estates, eight approved private endpoints,
  ten private DNS zones, private-only AMPLS, Standard Bastion, and no
  validation VM.
- Exactly four diagnostics remain, each with `allLogs`, `AllMetrics`, and its
  intended isolated workspace.
- RBAC remains exact: two group assignments at the matching project child
  scopes only; fourteen owner-managed project-identity Azure roles plus two
  Cosmos DB native data roles on matching estates; and two retained
  Defender scanner role assignments only at the two Storage accounts. No
  broader or unexpected resource-group child assignment was found.
- Post-remediation full-template what-if reports Deploy `81`, Ignore `11`,
  Unsupported `16`, and Create/Modify/Delete `0/0/0`. The Deploy set includes
  the exact two Defender settings; no unexpected drift remains.

### Remaining release gates

1. From an approved private client, test private DNS, TCP 443, and minimal
   authenticated own-project operations.
2. From a client without private route or DNS, prove public-path failure.
3. Run clean non-admin HOA-only and contract-only positive tests, sibling
   non-discoverability/denial, prompt-agent and evaluation CRUD, fresh-token
   and PIM verification, and cross-project managed-identity denial tests.
4. End the time-bound Owner exception and establish the planned split
   deployment identities before steady-state or production use.

## 13. Final independent acceptance

**Reviewer:** Linus  
**Evidence timestamp:** `2026-08-01T17:44:26-05:00`  
**Verdict:** **APPROVE**  
**Test readiness:** **Infrastructure ready; test identities/access required**

No Azure, Entra, group-membership, RBAC, deployment, deletion, or secret-read
mutation was performed. Exact group and principal identifiers were held only
in process memory and were neither printed nor persisted.

### Remediation and stabilization

- Deployment `fpval-defender-remediation-20260801T200131Z` is terminal
  `Succeeded`, incremental, with two successful Defender-setting resource
  operations. The third operation is only deployment-output evaluation.
- Both project Storage accounts have Defender enabled, subscription override
  enabled, on-upload scanning disabled, sensitive-data discovery enabled, and
  no scan-results Event Grid destination.
- Live inventory has zero Event Grid system topics and zero source-level event
  subscriptions on either Storage account. Activity logs contain no successful
  system-topic or event-subscription write after remediation. This independent
  check occurred more than two hours after deployment and therefore exceeds
  the reported 502-second stabilization interval.

### Live controls and inventory

- ARM-listed inventory is exactly `60`: `57` owner-managed resources plus the
  expected Azure-created smart-detection action group and two alert rules.
  Exact approved type counts match, with no Event Grid topic, VM, managed disk,
  validation NIC, or other unexpected/orphan/cost-bearing resource.
- The verified footprint is `113`, including the expected model deployments,
  connections, capability hosts, diagnostics, DNS zone groups, AMPLS scoped
  resources, Blob services, RBAC assignments, Cosmos native assignments,
  Defender settings, private-endpoint NICs, and platform account capability
  host. No unexplained child or extension resource was found.
- The resource group and all `57` owner-managed resources have the complete
  mandatory tag set. The three Azure-created smart-detection resources retain
  both locked governance tags.
- All `57` resources that expose `provisioningState` report `Succeeded`. The
  three smart-detection resources do not expose that property; their provider
  deployments are terminal `Succeeded`.
- Foundry has one private/local-auth-disabled account, the two exact
  system-identity projects, two succeeded `gpt-5.4-mini` deployments, eight
  correctly isolated project connections, two project capability hosts, and
  the expected platform account capability host.
- Separate HOA and contract Storage, Search, Cosmos DB, Log Analytics, and
  Application Insights estates are present and hardened. Storage, Search,
  Cosmos DB, Foundry, workspaces, Application Insights, and AMPLS retain the
  required public-network/local-auth restrictions.
- Exactly four diagnostics remain. Every setting enables `allLogs` and
  `AllMetrics` and targets the intended isolated workspace.
- Network verification passed: one four-subnet VNet, four NSGs with the exact
  Bastion and validation-subnet rule sets, eight approved/succeeded private
  endpoints, fourteen DNS zone configurations, ten exact private DNS zones
  with one succeeded VNet link each, and one succeeded Standard Bastion.

### Access and no-drift verification

- Both exact Entra groups resolve once and retain the required assigned
  security-group shape. Each has exactly one `Foundry User` assignment at only
  its matching project scope plus one `Reader` assignment at the Foundry account
  scope for portal compatibility. The Reader assignment is known to expose
  sibling project discovery and therefore changes the validation verdict from
  strict non-discoverability to portal-compatible project data/action isolation.
  Each group also has Search Service Contributor and Search Index Data
  Contributor only on its matching Search service for Foundry IQ/Knowledge UI
  operations.
- Each project managed identity has Foundry User at only its matching project,
  plus exactly seven Azure roles and one Cosmos native data role on only its
  matching backing estate. The only other
  descendant Azure assignments are the two expected Defender scanner roles,
  one per Storage account.
- Infrastructure ResourceIdOnly what-if returned Deploy `81`, Ignore `11`,
  Unsupported `16`, and Create/Modify/Delete `0/0/0`. Ignore is exactly the
  eight private-endpoint NICs plus three smart-detection resources.
  Unsupported maps exactly to the runtime-principal-dependent fourteen Azure
  role assignments and two Cosmos native assignments already verified live.
  Deploy matches the declarative baseline and includes both Defender settings.
- Bootstrap and access what-if also returned no Create, Modify, or Delete.
  Local Bicep validation and all static security/topology/tag/Defender
  assertions passed.

### Test-readiness determination

- Private-network infrastructure is ready, but this review host has no route
  to the validation VNet and resolves the tested Foundry/data endpoints only
  through public DNS.
- No validation VM or validation NIC exists, as expected because no approved
  SSH public key was supplied.
- Both required groups currently have zero members, so no clean non-admin test
  identity is available.
- Management-plane, configuration, topology, tag, deployment, RBAC, and
  no-drift checks can be performed now and have passed.
- User/data-plane tests still require:
  1. an approved private client with VNet routing and private DNS, or an
     approved SSH public key plus separate authorization to deploy the
     validation VM; and
  2. one clean enabled non-admin test identity in each exact group, followed by
     fresh-token own-project, sibling-denial, agent/evaluation CRUD,
     public-path-denial, and cross-project managed-identity denial tests.

The time-bound Owner exception and split deployment identities remain a
steady-state/production gate, not a blocker to beginning the above validation
once private access and clean test identities are supplied.
