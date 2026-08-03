# Microsoft Foundry capability preflight

**Environment:** validation  
**Region:** `northcentralus`  
**Evidence timestamp:** 2026-07-31T11:39:49-05:00  
**Mode:** read-only; no Azure resources were created, changed, or deleted  
**Overall outcome:** **CONDITIONAL**

There is no regional, provider-registration, core resource-quota, or candidate-model-capacity blocker to generating parameterized Bicep. Deployment remains blocked on connected-network overlap validation, Azure Policy/what-if, template adaptation review, and the previously approved strict sibling-isolation gate.

## 1. Live context

| Check | Result | Evidence |
|---|---|---|
| Azure cloud | **PASS** | Azure public cloud (`AzureCloud`) |
| Subscription | **PASS** | `carolga` (`<subscription-id>`), enabled |
| Tenant | **PASS** | `<tenant-id>` |
| Azure CLI | **PASS** | Azure CLI 2.81.0 |
| Quota extension | **PASS** | `quota` 1.0.0 already installed; no installation was performed |
| Current operator deployment permissions | **PASS, with isolation caveat** | Subscription Owner is present. The operator also has broad inherited access and must not be used as either project-isolation test identity. |
| Foundry MCP discovery | **BLOCKED, fallback successful** | MCP authentication failed without an interactive prompt. Management-plane Azure CLI and current Microsoft Learn were used instead. |

No principal name, email address, token, or resource name from unrelated tenant inventory is recorded here.

## 2. Capability and region matrix

| Capability | Status | Finding |
|---|---|---|
| Foundry resource and projects | **PASS** | Microsoft Learn lists North Central US for Foundry projects. Live provider metadata lists `Microsoft.CognitiveServices/accounts` and `accounts/projects` in North Central US with stable API `2026-05-01`. |
| AIServices SKU | **PASS** | Live `list-skus` returned unrestricted `AIServices` **S0 / Standard** in North Central US. |
| Foundry Agent Service prompt agents | **PASS** | Agent Service and Responses API are documented in North Central US. Prompt agents are covered by account-level network injection. |
| Agent tool region support | **CONDITIONAL** | North Central US supports Azure AI Search, File Search, MCP, OpenAPI, Code Interpreter, and web/grounding tools. The Functions tool and Computer Use are not supported there. Private-network tool limitations still apply. |
| Agent playground evaluations | **PASS** | North Central US is documented as supported. |
| Batch evaluations | **PASS** | North Central US is documented as supported. |
| Evaluation BYO VNet | **PASS** | North Central US is documented for evaluation network injection. |
| Safety evaluations | **CONDITIONAL** | Core safety evaluators and AI red teaming are supported. Groundedness Pro and Protected Material aren't supported in North Central US and must not be selected without a region change. |
| BYO Storage | **PASS** | Provider registered; live regional quota has ample capacity. |
| BYO Azure AI Search | **PASS** | Provider registered and service resource type is available in North Central US. Two planned S1 services fit the documented per-region limit. |
| BYO Cosmos DB | **PASS** | Provider registered and account resource type is available in North Central US. Two planned accounts fit documented subscription limits. |
| Private endpoints and DNS | **PASS** | Required providers are registered and live networking quota is ample. Actual DNS resolution can only be validated after deployment from the validation host. |
| BYO VNet injection | **CONDITIONAL** | Platform and region support are confirmed. Deployment requires create-time configuration, an exclusive delegated subnet, non-overlap approval, and policy/what-if validation. |
| Validation host and Bastion | **PASS** | `Standard_B2s` is live with no SKU restrictions; compute/network quota is sufficient. Bastion requires its dedicated `/26` subnet and normally one Standard static public IP unless Private-only Bastion is selected. |
| Monitoring | **PASS, design conditional** | Application Insights, Log Analytics, and Azure Monitor Private Link Scope providers/resource types are registered and regionally available. Final AMPLS/DNS topology must be included in Bicep. |

Required providers are all **Registered**: `Microsoft.CognitiveServices`, `Microsoft.App`, `Microsoft.ContainerService`, `Microsoft.Network`, `Microsoft.Storage`, `Microsoft.Search`, `Microsoft.DocumentDB`, `Microsoft.MachineLearningServices`, `Microsoft.KeyVault`, `Microsoft.Insights`, and `Microsoft.OperationalInsights`. `Microsoft.App` and `Microsoft.ContainerService` are mandatory for the account capability host and delegated agent subnet.

## 3. Candidate model and capacity

The live North Central US model catalog and Agent Service compatibility table support **`gpt-5.4-mini` version `2026-03-17`**, `GlobalStandard`. It is GA, supports the required prompt-agent tool patterns, and has no current subscription quota consumption.

Recommended **validation candidate**, not a production quality decision:

| Parameter | Validation value |
|---|---|
| `modelName` | `gpt-5.4-mini` |
| `modelVersion` | `2026-03-17` |
| `modelSkuName` | `GlobalStandard` |
| `modelCapacity` | `10` per deployment |
| Deployment count | Two account-level deployments, one logical deployment name per project |

Live quota reports 1,000 available capacity units for this model/SKU. Current quota documentation maps that pool to 1,000,000 TPM; the conservative validation plan uses 20 units total (20,000 TPM). Keep all four model fields parameterized. Promotion requires extraction-quality, latency, cost, and safety evaluation; model deployments remain account-level and aren't project-isolated.

## 4. Quota and service-limit results

`az quota` was used first. `Microsoft.CognitiveServices` and `Microsoft.DocumentDB` returned `BadRequest`; `Microsoft.Search` returned no quota records. Per the quota workflow, those rows use service-specific read APIs, sanitized resource counts, and current Microsoft Learn limits.

| Resource / limit | Source | Usage | Limit | Available | Planned | Gap |
|---|---|---:|---:|---:|---:|---|
| Resource groups | Resource count + ARM limits | 11 | 980 | 969 | 1 | None |
| AIServices S0 accounts | Cognitive Services usage API | 1 | 100 | 99 | 1 | None |
| `gpt-5.4-mini` GlobalStandard capacity units | Cognitive Services usage API | 0 | 1,000 | 1,000 | 20 | None |
| Managed environments | `az quota`, `Microsoft.App` | 0 | 50 | 50 | 1 | None |
| Virtual networks | `az quota`, `Microsoft.Network` | 0 | 1,000 | 1,000 | 1 | None |
| Subnets per VNet | `az quota`, `Microsoft.Network` | N/A | 3,000 | 3,000 | 4 | None |
| Private endpoints | `az quota`, `Microsoft.Network` | 0 | 65,536 | 65,536 | 8 base | None |
| Standard IPv4 public IPs | `az quota`, `Microsoft.Network` | 0 | 1,000 | 1,000 | 1 for Bastion | None |
| Network security groups | `az quota`, `Microsoft.Network` | 0 | 5,000 | 5,000 | 4 | None |
| Private DNS zones | Resource count + Private DNS limits | 0 | 1,000 | 1,000 | At least 6, plus AMPLS zones | None |
| Storage accounts | `az quota`, `Microsoft.Storage` | 0 regional | 250 | 250 | 2 | None |
| Azure AI Search S1 services | Count + Search service limits | 0 regional | 16 per region | 16 | 2 | None |
| Cosmos DB accounts | Count + Cosmos DB limits | 0 | 250 | 250 | 2 | None |
| Regional VM vCPUs | `az quota`, `Microsoft.Compute` | 0 | 100 | 100 | 2 | None |
| B-series vCPUs | `az quota`, `Microsoft.Compute` | 0 | 100 | 100 | 2 | None |
| Virtual machines | `az quota`, `Microsoft.Compute` | 0 | 25,000 | 25,000 | 1 | None |
| Batch evaluation rows | Evaluation service limit | N/A per run | 100,000/run | 100,000/run | Cap parameter at 100,000 | None |
| Batch evaluation row size | Evaluation service limit | N/A per row | 2 MB | 2 MB | Enforce under 2 MB | None |

The eight base private endpoints are one Foundry account endpoint, two Storage Blob endpoints, two Search endpoints, two Cosmos SQL endpoints, and one Azure Monitor private endpoint. Add endpoints only for extra services that enter scope.

GlobalStandard model quota is a subscription-level shared pool under the current quota model. AIServices account usage is likewise a service quota view and isn't the same as the sanitized count of resources physically located in North Central US.

## 5. Network plan and limitations

The approved `192.168.0.0/16` is valid RFC 1918 Class C space. No VNet currently exists in this subscription, so no subscription-local overlap was found. This does **not** prove compatibility with peered subscriptions, VPN/ExpressRoute networks, on-premises networks, or reserved enterprise address plans.

Recommended subnet allocation:

| Subnet | Prefix | Requirement |
|---|---|---|
| Agent delegated subnet | `192.168.0.0/24` | Exclusive to this Foundry account; delegate to `Microsoft.App/environments` |
| Private endpoint subnet | `192.168.1.0/24` | Foundry, project data resources, and monitoring private endpoints |
| `AzureBastionSubnet` | `192.168.2.0/26` | Dedicated Bastion subnet |
| Validation host subnet | `192.168.3.0/27` | Private-IP-only validation VM |

A `/27` is the supported minimum agent subnet, but `/24` is recommended because both projects share the account-level subnet, prompt-agent infrastructure can consume a small project-level pool, evaluations also use network injection, the subnet can't be resized safely after assignment, and platform upgrades need temporary headroom.

Limitations that must remain explicit:

- Network injection is an account create-time decision and applies to both projects.
- All projects in the account share the delegated subnet and account-level model deployments; VNet injection doesn't provide project-level layer-3 isolation.
- The agent subnet can't be shared with another Foundry account.
- Foundry and the VNet must be in the same region.
- Private endpoints for Storage, Search, and Cosmos aren't created automatically by Foundry.
- Blob-backed File Search isn't supported in this BYO private-network pattern. Code Interpreter file upload/download is limited. North Central US doesn't support the Functions agent tool.
- Deny-by-default NSGs/UDRs require the documented Azure Container Apps and identity egress allowances. TLS inspection that substitutes certificates can break provisioning.
- Bastion NSGs must retain the documented control-plane, health-probe, session, and target-VM flows.

## 6. Supported template recommendation

Use the official Bicep sample **`15-private-network-standard-agent-setup`** as the supported base and **adapt it**. Template `15a` is evaluation-only and doesn't supply full prompt-agent state/resources. Template `19` is only required if privately hosted MCP, OpenAPI, Functions, or A2A tool servers enter scope.

Required adaptation:

1. Keep one network-injected Foundry account and one shared delegated `/24`.
2. Create the exact two project children.
3. Duplicate Storage, Search, Cosmos, project capability host, private endpoints, and project connections so each project owns a separate data estate.
4. Parameterize model name, version, SKU, and capacity; don't retain the sample's automatic fixed model assumption.
5. Add the Bastion/validation-host subnets and admin-only monitoring/AMPLS design.
6. Keep project-member RBAC at exact project scopes; don't copy the sample into a broader parent-scope assignment.
7. Use the official deployment-tools preflight and cleanup ordering before any deployment.

## 7. Exact blockers and remediation

### Before Bicep generation

- **No quota or regional blocker.** Generation may proceed only as a reviewed adaptation of template 15, not as an unmodified sample.
- Keep model/evaluator/tool choices parameterized. Do not encode Groundedness Pro, Protected Material, Functions tool, or Computer Use in the North Central US baseline.

### Before deployment

1. **Connected-network overlap approval — BLOCKED.** The network owner must prove `192.168.0.0/16` doesn't overlap any peered, routed, VPN, ExpressRoute, on-premises, or reserved enterprise range. Change the VNet CIDR before deployment if any overlap exists.
2. **Azure Policy and what-if — BLOCKED.** Select the validation resource group, generate the Bicep, run validation and resource-group what-if, and resolve deny policies for public access, private DNS, subnet delegation, allowed regions/SKUs, managed identities, diagnostics, and tags.
3. **Template delta review — BLOCKED.** Verify the adapted resource graph contains exactly one account, two projects, two disjoint data estates, the shared account-level injection, and no shared customer-data connection.
4. **Name/soft-delete preflight — BLOCKED.** Run the official template preflight for provider registration, name conflicts, soft-deleted Cognitive Services accounts, and subnet service-association conflicts.
5. **Private DNS/egress design — BLOCKED.** Approve DNS ownership, conditional forwarding, AMPLS zones, NSG rules, UDR/firewall behavior, and the validation-host management path.

### Before validation release

1. **Strict sibling non-discoverability — BLOCKED.** Use clean, non-admin test identities with fresh tokens. The current broad operator identity is unsuitable. Prove positive authoring and negative sibling discovery/access through portal, ARM, API, SDK, connection pickers, and backing resources.
2. **Model quality and safety — CONDITIONAL.** Run approved synthetic/gold extraction and safety evaluations before promoting the validation candidate.
3. **Private feature proof — CONDITIONAL.** From the Bastion-reached validation host, prove private DNS, TCP 443, prompt-agent CRUD/invoke, evaluation CRUD/run, inference, Search/Cosmos/Storage access, monitoring, and public-path denial.

## 8. Conceptual read-only commands

The live checks used these command families with JSON queries that omitted identities and resource names:

```text
az cloud show
az account show
az extension show --name quota
az provider show --namespace <provider>
az quota list|show|usage show --scope <subscription/provider/region>
az cognitiveservices account list-skus --kind AIServices --location northcentralus
az cognitiveservices model list --location northcentralus
az cognitiveservices usage list --location northcentralus
az resource list                    # aggregated to counts locally
az vm list-skus --location northcentralus --size Standard_B2s
az role assignment list             # roles/scopes only; identity omitted
```

No write-capable Azure command was run.

## 9. Evidence

- [Feature availability across regions](https://learn.microsoft.com/azure/foundry/reference/region-support)
- [Agent Service quotas, regions, models, and tools](https://learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions)
- [Networking options for Agent Service](https://learn.microsoft.com/azure/foundry/agents/concepts/networking-options)
- [Set up private networking for Agent Service](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [Agent networking deep dive and subnet sizing](https://learn.microsoft.com/azure/foundry/agents/concepts/agents-networking-deep-dive)
- [Foundry private-link configuration and limitations](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link)
- [Evaluation regions, limits, and virtual-network support](https://learn.microsoft.com/azure/foundry/concepts/evaluation-regions-limits-virtual-network)
- [Foundry Models sold by Azure](https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure)
- [Azure OpenAI quotas and limits](https://learn.microsoft.com/azure/foundry/openai/quotas-limits)
- [Official Bicep template 15](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup)
- [Official Bicep template 15a](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15a-private-network-evaluation-only-setup)
- [Azure AI Search limits](https://learn.microsoft.com/azure/search/search-limits-quotas-capacity)
- [Azure Cosmos DB limits](https://learn.microsoft.com/azure/cosmos-db/concepts-limits)
- [Azure Private DNS limits](https://learn.microsoft.com/azure/dns/private-dns-privatednszone)
- [Azure Bastion configuration](https://learn.microsoft.com/azure/bastion/configuration-settings#subnet)
- [Azure Bastion NSG rules](https://learn.microsoft.com/azure/bastion/bastion-nsg)
