# Foundry infrastructure validation

This repository contains two independent infrastructure examples:

| Objective | Infrastructure | Start here |
|---|---|---|
| Validate permissions across two projects in one Foundry account | Bicep and `azd` | [Bicep deployment instructions](#deployment-instructions) |
| Deploy a private Foundry project with new or existing backing services | Terraform and AzAPI | [Terraform deployment guide](infra/terraform/README.md) |

See the [infrastructure folder map](infra/README.md) for the purpose of each
directory and the separate Terraform state roots.

The Bicep example validates hosting multiple Microsoft Foundry projects in one private, hardened Foundry account while isolating each team's Foundry User access to its own project. It also shows how to configure a hardened Foundry environment with private networking, disabled public access, disabled local/shared-key authentication, project-specific backing stores, explicit diagnostics, and controlled portal compatibility exceptions. The sample deployment uses two project children:

- `hoa-project`
- `one-to-four-residential-contract-project`

The environment is intentionally small and validation-focused. It proves which permissions are required for Foundry portal authoring, agent runtime, evaluations, Foundry IQ/Knowledge, and private network access while keeping each project's backing data estate separate.

## Bicep validation status

The validation environment is deployed in `rg-foundry-permissions-validation`. Agent creation, playground thread execution, evaluation creation/rubric generation, and Foundry IQ/Knowledge access have been tested through a private Windows validation VM reached through Azure Bastion.

The important result is that **strict sibling non-discoverability is not achievable with the current `ai.azure.com` portal flow**. The portal requires account-scope Reader for project groups to navigate and load project blades, and that Reader assignment exposes sibling project discovery. The environment now documents and codifies this as a portal-compatibility exception while preserving project-specific data/action isolation.

## Architecture diagram

Open the diagrams.net source file in draw.io:

- [`docs/architecture/foundry-permissions.drawio`](docs/architecture/foundry-permissions.drawio)

The diagram shows the network, Foundry account/projects, project data estates, validation VM, and the role assignments that were required during live testing.

## Resource inventory and purpose

| Resource type | Deployed resources | Why it is needed |
|---|---|---|
| Resource group | `rg-foundry-permissions-validation` | Dedicated validation boundary for all resources and deployments. |
| Microsoft Foundry account | `aifpvalov7f2p` | Parent Foundry resource for both validation projects, model deployments, project management, private endpoint, and network injection. |
| Foundry projects | `hoa-project`, `one-to-four-residential-contract-project` | Project-level workspaces for the two isolated document extraction domains. Each project has its own system-assigned managed identity and capability host. |
| Model deployments | `hoa-gpt-5-4-mini`, `contract-gpt-5-4-mini` | Account-level model deployments used by project agents and evaluations. Version, SKU, and capacity are parameterized. |
| Capability hosts | `agents` under each project | Standard Agent Setup capability host that binds each project to its own Storage, Cosmos DB, and Azure AI Search connections. |
| Storage accounts | `stfpvalhoaov7f2p`, `stfpvalcontractov7f2p` | Project-specific blob/file asset storage for agents, evaluations, and temporary evaluation/rubric artifacts. Public network access and shared-key access are disabled. Trusted Azure services bypass is enabled because evaluation asset/rubric generation uses a Microsoft service path. |
| Azure AI Search services | `srch-fp-val-hoa-ov7f2p`, `srch-fp-val-contract-ov7f2p` | Project-specific vector/knowledge index service for Foundry IQ/Knowledge and Search-backed agent tools. Project groups need Search Service Contributor and Search Index Data Contributor on only their matching service for the Foundry IQ/Knowledge UI. |
| Cosmos DB accounts | `cosmos-fp-val-hoa-ov7f2p`, `cosmos-fp-val-contract-ov7f2p` | Project-specific thread storage for agent conversations and runs. Cosmos uses serverless capacity and local auth is disabled. |
| Log Analytics workspaces | `law-fp-val-hoa-ov7f2p`, `law-fp-val-contract-ov7f2p` | Project-specific log stores for Foundry/project diagnostics and Application Insights telemetry. |
| Application Insights components | `appi-fp-val-hoa-ov7f2p`, `appi-fp-val-contract-ov7f2p` | Project-specific telemetry for traces/evaluation monitoring paths. Public ingestion/query are disabled and AMPLS/private endpoint is used. |
| Virtual network | `vnet-foundry-permissions-validation-ncus` | Private network boundary for Foundry access, private endpoints, Agent Service network injection, Bastion, and the validation VM. |
| Subnets | `agent-subnet`, `private-endpoint-subnet`, `AzureBastionSubnet`, `validation-subnet` | Dedicated subnets for Agent Service injection, private endpoints, Azure Bastion, and the validation VM. The validation subnet allows only Bastion-originated RDP inbound before a deny-all inbound rule. |
| Private endpoints | Foundry, Storage, Search, Cosmos DB, Azure Monitor | Private Link access to the account and project backing services. |
| Private DNS zones | Foundry, OpenAI, Services AI, Storage Blob, Search, Cosmos DB, Azure Monitor, Agent Service | Ensures the validation VM and injected agent runtime resolve private endpoints instead of public endpoints. |
| Azure Bastion Standard | `bas-validation-ov7f2p` plus `pip-bastion-ov7f2p` | Browser-based RDP path into the private validation VM without giving the VM a public IP. |
| Windows validation VM | `vm-validation-ov7f2p`, `nic-validation-ov7f2p`, `osdisk-validation-ov7f2p` | Private jumpbox for validating Foundry portal behavior from inside the VNet. Uses Entra login, no public IP, and daily shutdown. |
| DevTest Labs shutdown schedule | `shutdown-computevm-vm-validation-ov7f2p` | Daily 19:00 Central shutdown to control validation VM cost. |
| Defender for Storage settings | One setting per project Storage account | Keeps Defender enabled while disabling on-upload malware scanning to prevent unwanted system-topic/event-grid side effects in validation. |

## Permission model

| Principal | Scope | Role | Why it is needed |
|---|---|---|---|
| `hoa-group` | `hoa-project` | Foundry User | Build, test, run agents and evaluations in the HOA project. |
| `One-to-Four-Residential-Contract` | Contract project | Foundry User | Build, test, run agents and evaluations in the contract project. |
| `hoa-group` | Foundry account | Reader | Required by `ai.azure.com` portal navigation and Agents page loading. This exposes sibling project discovery and is a documented compatibility exception. |
| `One-to-Four-Residential-Contract` | Foundry account | Reader | Same portal compatibility exception for the contract group. |
| `hoa-group` | HOA Search service | Search Service Contributor; Search Index Data Contributor | Required for Foundry IQ/Knowledge UI to list/create knowledge bases on the matching Search service. |
| `One-to-Four-Residential-Contract` | Contract Search service | Search Service Contributor; Search Index Data Contributor | Same Foundry IQ/Knowledge UI requirement for the contract Search service. |
| Each project managed identity | Its own project | Foundry User | Required by Foundry services when the project identity performs project data-plane operations. |
| Each project managed identity | Matching Storage | Storage Account Contributor; Storage Blob Data Owner | Required for project asset storage, evaluation temporary data references, and agent artifacts. |
| Each project managed identity | Matching Search | Search Service Contributor; Search Index Data Contributor | Required for Search-backed knowledge/vector operations. |
| Each project managed identity | Matching Cosmos DB | Cosmos DB Operator; Cosmos DB Built-in Data Contributor | Required for project thread/run storage. |
| Each project managed identity | Matching Application Insights | Monitoring Metrics Publisher; Monitoring Reader | Required for project telemetry and evaluation monitoring paths. |
| Each project group, optional | Its own Application Insights | Log Analytics Reader | Read its own project traces when explicitly enabled. |
| Operator user | Validation VM | Virtual Machine Administrator Login | Allows passwordless Entra RDP through Bastion to the private validation VM. |

### Private tracing

The Bicep deployment already provisions a private Application Insights
component and Log Analytics workspace per project, their project connections,
and a shared Azure Monitor Private Link Scope. It also retains its existing
account and project diagnostics, which use a preview ARM API. Set
`grantProjectGroupsTraceRead = true` on `infra/access.bicep` or the
`infra/azd/main.bicep` wrapper only after approving trace access: each project
group then receives Log Analytics Reader on its own component. This is disabled
by default. Protected tables may require additional permissions. Trace content
can include prompts, responses and customer data; review access, retention and
costs before enabling or granting access. Viewers also need private-network
access. Verify a fresh agent invocation appears in the project's Traces view;
resource creation alone does not verify ingestion.

## Network and portal compatibility exceptions

The environment keeps `publicNetworkAccess` disabled for Foundry, Storage, Search, Cosmos DB, monitoring, and the validation VM. The following exceptions were proven necessary by live testing:

1. **Foundry account `networkAcls.bypass = AzureServices`**  
   Supports `ai.azure.com` portal resolver calls while public access remains disabled.

2. **Project Storage `networkAcls.bypass = AzureServices`**  
   Required for Foundry evaluation asset/rubric generation. Without it, rubric generation failed with `ResourceMsiTokenDoesntHavePermissionsOnStorage` even though the project managed identity had Storage roles.

3. **Project groups receive account-scope Reader**  
   Required for `ai.azure.com` Agents page and project-blade navigation. This exposes sibling project names and therefore fails the original strict non-discoverability goal.

4. **Project groups receive matching Search roles**  
   Required for the Foundry IQ/Knowledge UI to list and create knowledge bases against each project's own Search service.

## Cost considerations

This validation environment is not free. The largest recurring cost drivers are:

| Cost driver | Why it costs money | Cost control notes |
|---|---|---|
| Azure Bastion Standard | Hourly charge for Standard Bastion plus scale units and a Standard public IP. | Required for browser-based private RDP. Delete or stop using when validation ends if no longer needed. |
| Windows VM `Standard_B2s` and OS disk | VM compute while running plus managed disk storage. | Auto-shutdown is enabled daily at 19:00 Central. Deallocate manually when idle. |
| Foundry model deployments | Model deployment capacity and token usage. | Capacity is parameterized; recheck quota and right-size capacity before long-running tests. |
| Azure AI Search Standard services | Two Standard Search services, one per project. | One replica/one partition each for validation. Scale only if needed. |
| Cosmos DB serverless accounts | Request-unit consumption and storage. | Serverless minimizes idle cost for validation workloads. |
| Storage accounts | Blob storage, transactions, private endpoint traffic, Defender for Storage. | LRS is used by default. On-upload malware scanning is disabled; Defender sensitive data discovery remains enabled. |
| Log Analytics and Application Insights | Data ingestion and retention. | Retention defaults to 30 days. Verbose diagnostics increase cost. |
| Private endpoints | Hourly private endpoint charges plus data processing. | Needed for private networking; one private endpoint exists per protected service path. |
| Azure Monitor Private Link Scope | Private monitoring path and associated private endpoint/DNS. | Needed because public ingestion/query are disabled. |

### Sample North Central US monthly estimate

The table below is a directional sample using Azure Retail Prices queried for `northcentralus` on 2026-08-02 and a 730-hour month. It excludes model/token usage, Storage transactions, Cosmos DB request units, Private Link data processing, and Log Analytics/Application Insights ingestion volume because those are workload-dependent.

| Item | Quantity / assumption | Retail meter used | Sample monthly cost |
|---|---:|---|---:|
| Azure Bastion Standard | 1 gateway for 730 hours | Standard Gateway, `$0.29/hour` | `$211.70` |
| Azure Bastion extra scale unit | 1 additional scale unit for 730 hours because the template uses `scaleUnits: 2` | Standard Additional Gateway, `$0.14/hour` | `$102.20` |
| Bastion public IP | 1 Standard static public IP for 730 hours | Standard IPv4 Static Public IP, `$0.005/hour` | `$3.65` |
| Windows validation VM | `Standard_B2s`, 176 hours/month as an 8-hour weekday validation host | Windows B2s, `$0.0496/hour` | `$8.73` |
| Windows validation VM if left running | Same VM for 730 hours/month | Windows B2s, `$0.0496/hour` | `$36.21` |
| Azure AI Search | 2 Standard S1 services, 1 unit each, 730 hours | Standard S1 Unit, `$0.336/hour` | `$490.56` |
| Log Analytics ingestion | Example 1 GB/month | Analytics Logs Data Ingestion, `$2.76/GB` | `$2.76` |
| Application Insights ingestion | Example 1 GB/month | Enterprise Overage Data, `$2.30/GB` | `$2.30` |

With the validation VM running only during an 8-hour weekday test window, the sample above is about **`$819/month` plus workload-dependent charges**. If the VM is left running 24x7, the sample is about **`$846/month` plus workload-dependent charges**. Azure AI Search and Bastion dominate the fixed-cost baseline.

Pricing varies by region and can change over time. For example, the same Retail Prices query returned Windows `Standard_B2s` at `$0.0496/hour` in `northcentralus`, `eastus`, and `westus2`, but `$0.0579/hour` in `southcentralus`. Always rerun the Azure Pricing Calculator or Retail Prices API for the target region before using this pattern outside validation.

For a complete estimate, use the Azure Pricing Calculator with the target region and include Bastion Standard, one B2s Windows VM, two Standard Search services, two Cosmos DB serverless accounts, two StorageV2 accounts, model deployment capacity and token usage, private endpoints, Log Analytics ingestion/retention, and Application Insights.

## Validation summary

Validated through live testing:

- Private DNS/TCP from the validation VM to Foundry account endpoints, OpenAI endpoint, Services AI endpoint, Agent Service endpoint, and project backing services.
- Agent creation and Playground thread execution for the HOA project.
- Evaluation creation and rubric generation after Storage trusted-services bypass.
- Foundry IQ/Knowledge UI after assigning Search roles to the matching project group.
- Cosmos-backed thread storage.
- Portal compatibility behavior requiring account-scope Reader.

Known limitation:

- Account-scope Reader is required for `ai.azure.com` portal usability and exposes sibling project discovery. The current environment demonstrates **portal-compatible project data/action isolation**, not strict sibling non-discoverability.

## Key files

| File | Purpose |
|---|---|
| `.azure/deployment-plan.md` | Detailed deployment decisions, evidence, and validation log. |
| `infra/main.bicep` | Main resource-group infrastructure deployment. |
| `infra/access.bicep` | Project group RBAC and portal/Search compatibility assignments. |
| `infra/validation-vm.bicep` | Separate private Windows validation VM entry point. |
| `infra/tests/Invoke-LocalValidation.ps1` | Local Bicep build and static assertion gate. |
| `docs/runbooks/validation.md` | Operational validation and post-deployment test runbook. |
| `docs/architecture/foundry-permissions.drawio` | diagrams.net source diagram for the deployed architecture and permissions. |

## Deployment instructions

For a separate private, network-injected Terraform deployment using
project capability hosts and non-preview ARM API versions, see
[`infra/terraform/README.md`](infra/terraform/README.md). It creates a new
Foundry account and can use new or existing data services without taking over
this Bicep validation environment.

This repository supports `azd up` through `azure.yaml` and the subscription-scope wrapper in `infra/azd/main.bicep`. The wrapper orchestrates resource-group bootstrap, private Foundry infrastructure, access role assignments, and the private validation VM.

The Entra security groups are intentionally **not** created by this deployment. They must be created before deployment, and their immutable object IDs must be known.

### Prerequisites

- Azure Developer CLI (`azd`)
- PowerShell 7
- Azure CLI with Bicep support
- An Azure subscription and tenant where the required providers are registered
- Permission to create infrastructure and role assignments, typically Owner for validation or Contributor plus Role Based Access Control Administrator/User Access Administrator at the required scopes
- Pre-created Entra security groups:
  - `hoa-group`
  - `One-to-Four-Residential-Contract`
- The immutable object IDs for those groups
- The operator user's object ID for VM-scoped Entra login
- A secure temporary local administrator password for the validation VM

### 1. Sign in

```powershell
azd auth login
az login
```

### 2. Create/select an azd environment

Use `validation` if you want resource names to match the validation examples.

```powershell
azd env new validation
azd env set AZURE_LOCATION northcentralus
```

### 3. Set required deployment values

Do not commit these values. They are required because group creation and operator identity selection are intentionally external governance steps.

```powershell
azd env set HOA_GROUP_OBJECT_ID <hoa-group-object-id>
azd env set CONTRACT_GROUP_OBJECT_ID <contract-group-object-id>
azd env set OPERATOR_OBJECT_ID <operator-user-object-id>
azd env set VALIDATION_ADMIN_PASSWORD <secure-password-from-approved-workflow>
```

The `azd` wrapper uses the resource group name `rg-foundry-permissions-${AZURE_ENV_NAME}`. For `azd` environment `validation`, that becomes `rg-foundry-permissions-validation`.

### 4. Run local validation

```powershell
pwsh -NoProfile -File .\infra\tests\Invoke-LocalValidation.ps1
```

### 5. Deploy everything with azd

```powershell
azd up
```

`azd up` deploys:

- the resource group;
- the private Foundry account, projects, model deployments, VNet, private endpoints, private DNS, project Storage/Search/Cosmos/monitoring, Bastion, and diagnostics;
- project group role assignments, including the documented portal and Foundry IQ/Search compatibility exceptions;
- the private Windows validation VM and its VM-scoped operator login role.

### Advanced fallback: deploy with Azure CLI

Use this path when you want to run individual entry points instead of `azd up`.

Create the resource group:

```powershell
az deployment sub create `
  --location <azure-region> `
  --template-file .\infra\bootstrap\main.bicep
```

Deploy the private Foundry infrastructure:

The checked-in `validation.bicepparam.example` is safe and contains no group object IDs, passwords, or user principal IDs. For a non-validation environment, copy it and adjust names, model settings, capacity, network CIDRs, tags, and region as appropriate.

```powershell
$paramCopy = ".\infra\environments\validation.deploy.bicepparam"
Copy-Item .\infra\environments\validation.bicepparam.example $paramCopy

az deployment group create `
  --resource-group <resource-group-name> `
  --template-file .\infra\main.bicep `
  --parameters $paramCopy

Remove-Item $paramCopy
```

Deploy project access roles:

Supply real group object IDs only at execution time. Do not commit them.

```powershell
az deployment group create `
  --resource-group <resource-group-name> `
  --template-file .\infra\access.bicep `
  --parameters `
    foundryAccountName=<foundry-account-name> `
    hoaGroupObjectId=<hoa-group-object-id> `
    contractGroupObjectId=<contract-group-object-id> `
    hoaSearchServiceName=<hoa-search-service-name> `
    contractSearchServiceName=<contract-search-service-name>
```

Deploy the private Windows validation VM:

The VM entry point deliberately has no checked-in parameter file. It requires a secure local administrator password and the operator user's object ID at deployment time.

```powershell
az deployment group create `
  --resource-group <resource-group-name> `
  --template-file .\infra\validation-vm.bicep `
  --parameters `
    validationAdminPassword=<secure-password-from-approved-workflow> `
    operatorObjectId=<operator-user-object-id>
```

Prefer an approved secure parameter workflow for the password. Do not paste secrets into shell history, transcripts, files, or commits.

## Local validation

Run from the repository root:

```powershell
pwsh -NoProfile -File .\infra\tests\Invoke-LocalValidation.ps1
```

The validation gate builds all Bicep entry points and checks topology, tags, secret safety, Windows validation VM controls, Defender for Storage settings, policy compatibility, and required role-assignment shapes.
