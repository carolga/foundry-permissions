# Private Foundry Standard Agent Setup in Terraform

This creates a **new Foundry account and project**, not a migration of the
existing Bicep validation environment. Storage, Cosmos DB and Search can be new
or existing resources. It uses Terraform and AzAPI with a dedicated VNet and
does not deploy HOA business logic, APIM, a hosted container, or automatic DR.

Open the [editable draw.io architecture diagram](../../docs/architecture/foundry-terraform.drawio)
for the private network paths, project capability host, backing stores, and optional components.

## Folder and file map

`infra/terraform` is the **Foundry Terraform root**. All `.tf` files directly
in this directory are part of the same configuration and state:

| Location | Objective |
|---|---|
| `foundry.tf`, `data.tf` | Foundry account, project, capability host, connections, model, and new/existing data service selection |
| `synthetic-agent.tf` | Optional Terraform-managed synthetic HOA intake prompt agent |
| `network.tf`, `rbac.tf` | Private networking, DNS, and project access to data services |
| `bastion.tf`, `validation-vm.tf`, `windows-desktop.tf` | Optional private validation access and desktops |
| `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` | Resource group, inputs, outputs, and provider requirements |
| [`backing-stores/`](backing-stores/README.md) | Optional first-stage Storage, Cosmos DB and Search deployment; **separate Terraform root and state** |
| `scripts/` | Deployment, credential, and private runtime validation helpers |
| `tests/` | Terraform contracts and Python tests |

Use the Foundry root to deploy everything together, or deploy the optional
backing-stores root first and provide its resource IDs to the Foundry root.
Both roots can also be used independently of the Bicep example. Keep existing
Terraform state and workspace locations intact unless performing a deliberate
state migration.

## API choice

Every ARM API version used by these Terraform configurations is non-preview.
The Foundry account, project, connections and capability hosts use `2025-06-01`.
An API version being non-preview does not establish the availability or support
status of every product feature in every region. Microsoft describes the
capability-host flow as backward-compatible and retains its host article for
reference; confirm its long-term support requirements for production.
The optional agent uses the Foundry **data-plane** API `Microsoft.Foundry/agents@v1`;
this is not an ARM API version.

| Resource provider | ARM API versions |
|---|---|
| Foundry account, project, connections, hosts and model deployment | `2025-06-01` |
| Storage | `2025-01-01` |
| Cosmos DB and SQL role assignments | `2025-04-15` |
| Azure AI Search | `2025-05-01` |
| Network and private DNS | `2024-05-01`, `2024-06-01` |
| Resource groups and subscription locations | `2024-03-01`, `2022-12-01` |
| Role assignments | `2022-04-01` |
| Optional validation VM | `2024-07-01` |

Network injection creates the account host, commonly named
`<account>@aml_aiagentservice`. Empty connection arrays on that account host are
not by themselves a failure. The **project capability host** selects the project's
BYO data resources. This configuration reads and checks the auto-created account host; it
does not create or update that account host.

The actual Search configuration is:

```hcl
# Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01
properties = {
  authType = "AAD"
  category = "CognitiveSearch"
  target   = "https://<search-service>.search.windows.net"
  metadata = { ResourceId = "<full Search ARM resource ID>" }
}

# Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-06-01
properties = {
  capabilityHostKind       = "Agents"
  storageConnections       = ["conn-hoa-storage"]
  threadStorageConnections = ["conn-hoa-cosmos"]
  vectorStoreConnections   = ["conn-hoa-search"]
}
```

The newer account/project `capabilitySettings` contract is not used. An isolated
test of its `2026-07-15-preview` API returned `LinkedInvalidPropertyId` for a
full Search ARM ID at `properties.capabilitySettings.vectorStore`, before the
account was created. This capability-host deployment is an alternative, not a
fix or validated workaround for that preview API.

## Deployment order

1. Optionally create Storage, Cosmos DB and Search in the independent `backing-stores` Terraform root.
2. Create a new resource group, dedicated VNet and subnets for Foundry.
3. Create the network-injected Foundry account, private endpoints and private DNS.
4. Create the project and grant its identity roles on the backing services.
5. Create AAD project connections and the project capability host.
6. Deploy an optional model and private validation VM.
7. Optionally create the synthetic prompt agent from a runner with private project access.

AzAPI polls long-running operations, with a 60-minute capability-host timeout.
Do not treat the initial HTTP acceptance as deployment success. Role assignments
can require propagation; inspect the actual failure rather than blindly
recreating a host.

For new Storage accounts only, `blobServices/default` retention/versioning is
managed with `azapi_update_resource`, not a second create/import. The existing
Storage account's blob-service settings are not managed.
Cosmos location names are resolved to Azure's display-name form, and Search uses
the service-returned `Disabled` casing to avoid perpetual Terraform updates.
The connection `peRequirement` hint is omitted because this API returns
`NotRequired` even when `Required` was submitted; network isolation is enforced
by the actual private endpoints and disabled public access, not that hint.

## Prerequisites

- Terraform >= 1.11; `terraform init` installs the pinned AzAPI provider.
- Azure CLI signed in to the intended tenant/subscription.
- PowerShell 7 for the validation wrapper; Python 3.10+ for the local script tests
  (the optional Ubuntu validation VM already includes Python).
- Owner, or infrastructure deployment rights plus RBAC assignment rights on the
  resource group and backing resources.
- Providers registered: `Microsoft.CognitiveServices`, `Microsoft.DocumentDB`,
  `Microsoft.Storage`, `Microsoft.Search`, `Microsoft.Network`, `Microsoft.App`,
  `Microsoft.KeyVault`, `Microsoft.MachineLearningServices`, and
  `Microsoft.ContainerService`. The optional validation VM also needs
  `Microsoft.Compute`.
- An Agent Service-supported region, available Search capacity, and model quota
  if a model is requested. Default region is `westus3`.
- Nonoverlapping private CIDRs; the agent subnet cannot be shared with another
  Foundry account. This example uses Azure-provided DNS. Enterprise custom DNS
  requires equivalent forwarding/private-zone integration.

## Run from PowerShell

To create Foundry and its backing services together:
```powershell
Set-Location C:\source\foundry-permissions\infra\terraform
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit subscription_id, resource_group_name, tags, model and optional public key.
az login
terraform init
terraform fmt -check -recursive
terraform validate
terraform test
python -B -m unittest discover -s tests -p 'test_*.py'
terraform plan '-out=deployment.tfplan'
terraform apply deployment.tfplan
terraform output
```

### Reproduce with separately created backing services

The first script plans or applies `backing-stores`, a separate Terraform root and
state. The second reads its three outputs and passes them as existing resource
IDs to the Foundry root. Both scripts default to **plan**; inspect each saved
plan before running the corresponding apply. The test services have public
access disabled and become privately reachable after the Foundry stage creates
the private endpoints.

```powershell
Set-Location C:\source\foundry-permissions\infra\terraform
Copy-Item .\backing-stores\terraform.tfvars.example .\backing-stores\terraform.tfvars
# Edit the subscription, new backing-services resource group and location.
.\scripts\Deploy-BackingStores.ps1 -Action plan -VarFile .\backing-stores\terraform.tfvars
# Review the plan before applying.
.\scripts\Deploy-BackingStores.ps1 -Action apply

terraform init
terraform workspace new existing-services
Copy-Item .\terraform.tfvars.example .\foundry-existing.tfvars
# Edit the subscription, NEW Foundry resource group, location, CIDRs and optional model/VM.
.\scripts\Deploy-FoundryWithExistingStores.ps1 -Workspace existing-services -Action plan -VarFile .\foundry-existing.tfvars
# Review the plan; it must not create or delete the three backing parent resources.
.\scripts\Deploy-FoundryWithExistingStores.ps1 -Workspace existing-services -Action apply
terraform output
```

For services managed outside the first root, skip the first script and set the
three `existing_*_id` inputs in the Foundry variable file; use ordinary
`terraform plan` and `terraform apply`. Do not point a new state at an existing
Foundry account or switch an existing state's backing-resource ownership.

Terraform also loads `terraform.tfvars` automatically if it exists. Values in
the explicit `-var-file` take precedence, as do the second script's explicit
backing IDs; review the plan for all inherited values. Use the same workspace
and variable file for subsequent plans.

Review the plan before applying. Do not use `-target` for normal deployment. The
subscription is explicit in the provider and all resource IDs; this example does
not change the Azure CLI's default subscription.

AzAPI's optional ARM preflight is disabled because it substitutes an invalid
placeholder for a not-yet-created subnet ID during a fresh single-pass plan.
Provider schema validation remains enabled except for the documented
capability-host schema gap. Azure validates the real resource IDs during apply.

`model = null` avoids model deployment. For runtime testing, select a supported
model/version/SKU/capacity from your subscription's current regional inventory.
The example selects GPT-5.4 mini `2026-03-17`, GlobalStandard, with 10 capacity
units. Capacity is model-specific token/request quota, not an assurance of
immediate runtime availability. A model can remain listed in the catalog while
new deployments are rejected as deprecating; inspect the deployment error and
select a currently deployable version rather than repeatedly retrying that model.

Setting `validation_ssh_public_key` creates an optional private Ubuntu VM. Use an
SSH **public** key generated outside the repository. The VM has no password or
public IP. Without Bastion, inbound access is denied and Azure VM Run Command
can run the smoke test inside the VNet. With Bastion enabled, only SSH from its
subnet is allowed. The VM's managed identity receives Foundry User only on this
project; anyone with access to the VM can use that identity.

Terraform state and plans can contain sensitive operational information. Local
state, `.tfvars`, plans and caches are gitignored. Configure an organization-owned,
access-controlled remote backend for production. Commit `.terraform.lock.hcl`.

### Optional synthetic prompt agent

The Bicep deployment configures Agent Service but does not define an agent.
This optional Terraform resource creates a simple prompt agent for **synthetic
data only**. It summarizes supplied intake information and flags missing fields;
it has no knowledge source or file-search tool and is not the customer's
production HOA agent.

First deploy the infrastructure with `synthetic_prompt_agent_name = null`. Then
choose an unused name and set `synthetic_prompt_agent_name`, keeping the existing
`model` configuration. Run subsequent plans and applies from a runner that can
resolve and reach the Foundry project through its private endpoint. The runner
must use the **same Terraform workspace, state and variable values** and an
identity authorized for agent management (for example, Foundry User on the
project), as well as the required ARM permissions. Protect the state and plans;
do not copy them to an untrusted jumpbox or create a second state for the same
infrastructure. Keep public access disabled.

For example, after preparing that runner, add the following to the existing
deployment's variable file:

```hcl
synthetic_prompt_agent_name = "hoa-intake-test"
```

Use the same workspace and all other original inputs for a normal Terraform
plan and apply. If the Windows desktop is enabled, the runner also needs the
ephemeral administrator password supplied through an approved secret mechanism.

Review the plan before applying and confirm the name does not already belong to
an agent managed elsewhere. An existing agent needs a deliberate ownership
and import decision, not a second writer. Definition changes can create new
versions. Terraform's `prevent_destroy` protects the named agent and its version
history from an accidental disable, rename or destroy; removal requires an
explicitly reviewed change to that protection. Agent instructions are stored in
Terraform state, so do not put secrets or customer data in them.

### Connect to the optional private jumpbox

Set `validation_ssh_public_key` and `bastion_subnet_prefix` to enable Azure
Bastion Basic. The prefix must be an unused IPv4 `/26` or larger inside the
VNet. Bastion has a Standard public IP for HTTPS; the VM remains private. The
VM subnet permits TCP 22 only from the Bastion subnet and denies other inbound
traffic. Bastion Basic and its public IP incur ongoing charges, even when the
VM is deallocated.

Generate an RSA key pair outside the repository in PEM format for portal-based
SSH. Supply **only the public key** to Terraform. Keep the matching private key
secure; it is not deployed to the VM. After applying, start the VM and install
the test tools from the selected Foundry workspace:

```powershell
az vm start --subscription <subscription-id> --resource-group <resource-group> --name <validation-vm>
.\scripts\Install-JumpboxTools.ps1
```

In the Azure portal, open the VM and select **Connect** > **Bastion**. Choose
**SSH Private Key from Local File**, username `azureuser`, and the matching
RSA PEM private key. The operator needs Reader on the VM, its NIC, and Bastion.
Bastion Basic provides browser SSH, not a graphical desktop or native-client
tunnel. Inside the VM:

```bash
python3 ~/foundry-jumpbox/chat_agent.py --list
python3 ~/foundry-jumpbox/chat_agent.py --agent <agent-name>
```

Type `/quit` to exit. The chat uses the VM's project-scoped managed identity and
creates a conversation in Foundry. Use synthetic data for this validation
environment. `--message "text"` sends one message without an interactive chat.

### Optional Windows desktop over Bastion

Set `windows_desktop_enabled = true`, `bastion_subnet_prefix`, and
`windows_entra_login_principal_id` to the operator's Entra user object ID to
enable the desktop; the Linux VM is not required. This enables or upgrades Bastion to
**Standard** and creates a separate private
Windows Server 2025 desktop, with Trusted Launch and TCP 3389 permitted only
from the Bastion subnet to the desktop's private IP. Bastion Standard, its
public IP, the Windows VM and disk incur charges. The Linux VM is unchanged.
The desktop's managed identity receives Foundry User on this project; anyone
with desktop access can use that identity. The Entra login extension and
VM-scoped Virtual Machine Administrator Login role are configured for the
specified user, as in the reference Windows desktop.

In the Azure portal open the Windows VM and choose **Connect** > **Bastion**,
protocol **RDP**, and authentication **Microsoft Entra ID (Preview)**. Sign in
with the authorized organizational account; no local VM password is needed for
this path. Entra authentication for portal-based Bastion RDP is **public
preview**, even though the ARM API versions used here are non-preview. Actual
interactive sign-in must be verified by the operator. Inside the desktop, sign
in to Foundry with a user who has project access.

The deployment still creates a local administrator password, like the reference
Windows VM, for provisioning and recovery. On Windows, create the credential
outside the repository. It is DPAPI-protected
for the current Windows user and cannot be recovered on another machine/user.
Back it up using an approved secret-management process. Do not lose or overwrite
it, print it, or put it in a `.tfvars` file. Use the same credential for both
plan and apply; the password is ephemeral and AzAPI sends it via its write-only
`sensitive_body`, not Terraform state or the saved plan.

```powershell
$credential = "$env:USERPROFILE\.azure\foundry-permissions\desktop.credential.xml"
$plan = "$env:USERPROFILE\.azure\foundry-permissions\desktop.tfplan"
.\scripts\New-WindowsDesktopCredential.ps1 -CredentialPath $credential
.\scripts\Invoke-FoundryWindowsDeployment.ps1 -Workspace <workspace> -CredentialPath $credential -VarFile <variables.tfvars> -PlanFile $plan
# Review the saved plan, then:
.\scripts\Invoke-FoundryWindowsDeployment.ps1 -Workspace <workspace> -CredentialPath $credential -PlanFile $plan -Action apply
```

For local-password recovery only, choose **Password** in Bastion and username
`foundryadmin`. Copy the password without printing it using the command below,
paste it into Bastion, then clear the clipboard.

```powershell
.\scripts\Copy-WindowsDesktopPassword.ps1 -CredentialPath $credential
```

## Security and production differences

- Public access and local/key authentication are disabled on Foundry and newly
  created backing stores. Existing stores must have public access disabled;
  their key-auth settings are not changed. Private endpoints provide data-plane access.
- Newly created Storage and Foundry use trusted Azure service bypass, matching
  this repository's evaluation/portal compatibility pattern. Review these
  exceptions with customer security; they are not blanket egress isolation.
- The VNet has no firewall/UDR/custom egress restriction. Enterprise egress controls
  must allow documented identity and service dependencies.
- The project identity has Storage Account Contributor + Blob Data Owner,
  Search Service Contributor + Search Index Data Contributor, Cosmos DB Operator
  + Cosmos SQL Data Contributor, and Foundry User on its own project. These are
  account-wide, including on any shared existing stores, for bootstrap;
  production can narrow to provisioned containers/database after validation.
- This focused deployment omits Application Insights/AMPLS, diagnostics, business
  application deployment, CMK, governance policies and private operator access
  infrastructure. Keep the existing Bicep deployment for the broader reference.
- Search uses one Standard replica for inexpensive testing, not production
  read/write availability. Serverless Cosmos and LRS Storage are test choices,
  **not** a cross-region recovery solution.
- Account-scope Reader for portal navigation is not granted automatically. It
  exposes sibling project discovery; see the root README for that tradeoff.

## Existing Storage, Cosmos DB and Search

Set any of `existing_storage_account_id`,
`existing_cosmos_account_id`, and `existing_search_service_id` to the full ARM
ID; leave an input null to create that service. The services must be in the
same subscription and region, have public network access disabled, and use
standard Azure public-cloud endpoints. Cosmos must be NoSQL; Search must support
private endpoints and Microsoft Entra data-plane authentication. An explicit
Cosmos account throughput limit must be unlimited (`-1`) or at least 3,000 RU/s.
Confirm available headroom for the project's three to five Cosmos containers
(at least 1,000 RU/s each) and Search capacity; the limit check alone does not
establish available capacity.

The existing service **parent resources are read, not imported or managed**.
However, the deployment creates private endpoint connections and grants roles
on them; Foundry can create project-specific containers, databases and indexes.
The project identity receives account-wide roles in this example. Review those
changes, private DNS integration and the impact on shared data with the resource
owners before applying. Destroying the new project may affect its
service-managed data; review its data lifecycle separately before cleanup.

This root always creates a new Foundry account/project and VNet. It cannot adopt
an existing customer account or reuse its network; an ownership and migration
plan is needed for that separate scenario. Do not apply it over an existing
customer Terraform state.

Capability hosts cannot be updated in place. `replace_triggers_refs = ["body"]`
makes intended host body changes replacements instead of unsupported PATCHes.
A replacement can interrupt access to existing agent data. Do not approve it
for an active customer project without a recovery plan. Do not use
`create_before_destroy`: there can be only one host per scope.

If provisioning fails after subnet association, preserve the error and inspect
the capability host and subnet service-association link. Prefer a new test
resource group/VNet for a clean reproduction; do not delete a customer's host or
force-remove a service-association link as a retry shortcut.

## Verification and cleanup

Verify both hosts and the project connection names and
`metadata.ResourceId`. Confirm provisioning succeeded, all private
endpoints are `Approved`, and public access is disabled.
From the VNet, verify private DNS and create an agent, conversation, uploaded
file and vector store. Inspect the matching Cosmos, blob and Search artifacts;
a successful resource deployment alone is not proof of working agents or DR.

An example smoke script and validation commands accompany this configuration.
Runtime model calls incur usage charges. Keep test content synthetic.

```powershell
.\scripts\Invoke-Validation.ps1
```

The script checks live ARM state and uses VM Run Command to execute the
standard-library Python test from inside the VNet. It authenticates with the
VM's managed identity (never copies your Azure CLI credentials), uploads a
synthetic file, indexes it in a vector store, creates an ordinary Prompt agent,
and requires a completed conversation response with a `file_search_call` and the
exact marker from that file. Artifacts remain in the test project for inspection.
This tests runtime storage paths, not the HOA application's business behavior.

The script uses the current Responses API `agent_reference` field, not the
deprecated `agent` field, and bounds response output to 2,048 tokens. It retries
only the initial agent-list read for up to five minutes when VM RBAC is
propagating (403) or the service reports the specific agent-index timeout
observed during bootstrap. Each retry is logged, and a persistent failure still
fails validation. Other errors and all artifact-creation requests fail explicitly.
Do not treat that initial timeout as proof of a DNS or RBAC defect without
checking the live configuration.

For model 429 responses, inspect the returned token/request limits. Model
capacity updates can reach the management plane before the runtime adopts them.
Wait for propagation and rerun the synthetic test; do not enable public access
or change capability-host bindings to address a model quota error.

### Observed live validation: 2026-11-18

The fresh West US 3 deployment passed the complete smoke test with GPT-5.4 mini
`2026-03-17`, GlobalStandard, capacity 10:

| Check | Observed result |
|---|---|
| Terraform convergence | No changes after apply |
| Account and project capability hosts | Both `Succeeded`; project host bound to all three connection names |
| Network isolation | All four services have public access disabled, approved private endpoints and private IPv4 DNS |
| Backing stores | Project-prefixed Cosmos containers and blob containers provisioned; synthetic vector-store file indexing completed |
| Runtime | Agent and conversation created; response completed with an actual `file_search_call` and the file-only marker `HOA-INTAKE-TF-READY-7391` |
| Local checks | Terraform validation, three mocked contract tests and three Python readiness tests passed |

Two eventual-readiness conditions were observed: the first new-agent list
timed out against Cosmos after host provisioning, then recovered without any
network or binding change; after scaling model capacity from 1 to 10, runtime
429 headers continued reporting the old 1,000-token limit for several minutes
before inference succeeded. Neither is evidence that enabling public access is
necessary. The fresh configuration's model example starts at capacity 10.

### Observed existing-resource reproduction: 2026-11-18

In a second West US 3 test, the backing-services root created Storage, Cosmos DB
and Search in a separate resource group before the Foundry root connected them.
Both roots converged with no changes. The project host succeeded with the three
connection names, all four private endpoints were approved, and private DNS
resolved correctly from the VM. Foundry provisioned a Cosmos database and blob
containers in the existing accounts; synthetic file indexing and an agent
file-search conversation succeeded. An initial agent-list Cosmos timeout
recovered without changing the network or host bindings.

The Bastion Basic add-on was subsequently provisioned for the private Linux VM.
Network Watcher confirmed that its subnet can reach SSH while other inbound SSH
is denied, and the installed jumpbox client listed and invoked the synthetic
agent. A browser-based Bastion login was not tested automatically.

This result applies to the capability-host path only. It does not reproduce or
resolve the customer's separate newer capability-settings API error, certify
production readiness, or validate DR.

Resources keep incurring charges after deployment. Deallocate the optional VM
when not testing (its disk still costs money). Search and private endpoints
remain billable even with the VM stopped, as do an enabled Bastion and its
public IP. To remove **only a test stack**,
select its original workspace and variables, review `terraform plan -destroy`,
and obtain approval before `terraform destroy`. The backing-services root has
separate state and must be reviewed separately; it can contain data used by the
Foundry project.
Foundry account soft deletion and subnet service-association cleanup can delay
name/subnet reuse; do not purge or force-delete resources without approval.

If the validation VM is deallocated, start it before rerunning validation:

```powershell
$projectId = terraform output -raw project_id
$subscription = ($projectId -split '/')[2]
$resourceGroup = terraform output -raw resource_group_name
$vm = terraform output -raw validation_vm_name
az vm start --subscription $subscription --resource-group $resourceGroup --name $vm
.\scripts\Invoke-Validation.ps1
az vm deallocate --subscription $subscription --resource-group $resourceGroup --name $vm
```

## Authoritative references

- [Capability hosts, hierarchy, names and REST payloads](https://learn.microsoft.com/azure/foundry/agents/concepts/capability-hosts)
- [Capability-host Terraform schema, 2025-06-01](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2025-06-01/accounts/projects/capabilityhosts)
- [Use existing data services](https://learn.microsoft.com/azure/foundry/agents/how-to/use-your-own-resources)
- [Private networking, provisioning identity differences and Terraform guidance](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [Standard setup and runtime roles](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup)

The private-network article documents the capability-host flow's project
identity as the provisioning identity. Do not substitute resource IDs for
connection names in the project capability-host payload.
