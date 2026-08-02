# Bicep readiness preflight

**Date:** 2026-07-31  
**Result:** **CONDITIONAL** — the architecture is implementable by adapting official templates, but Bicep generation remains blocked by the gates in [Blockers and conditions](#blockers-and-conditions).  
**Recommendation:** **ADAPT** `15-private-network-standard-agent-setup`; do not use it unchanged and do not classify this repository as EXTEND.

## Scope and safety

This was a read-only preflight for subscription `bcecc00d-409b-4dbc-a910-029bdb668640`, region `northcentralus`, and planned resource group `rg-foundry-permissions-validation`.

- No Azure resources or providers were created, registered, changed, or deleted.
- No deployment, validation deployment, or what-if was run because implementation IaC does not exist yet.
- No `.env` file or secret-bearing file was read.
- No implementation Bicep or deployment script was generated.
- Existing plan files were not changed.

## Approach selection

### Classification: ADAPT

The repository contains planning documents but no user-authored Bicep implementation. Therefore:

- **OFFICIAL** is not appropriate because no single official sample satisfies the complete two-project, physically separate data-estate, Bastion/validation-host, monitoring, and narrow-RBAC design unchanged.
- **EXTEND** is not appropriate because there is no implementation IaC to extend.
- **ADAPT** is correct: start from the official private standard-agent sample and compose reviewed AVM resources around adapted Foundry child-resource modules.

### Official catalog reviewed

Catalog snapshot: `microsoft-foundry/foundry-samples` commit `89e85457a5b9638f763ffbc8cdd84683c22b9b7a`.

| Template | Finding |
|---|---|
| `15-private-network-standard-agent-setup` | Closest base. Provides account-level BYO VNet injection, private endpoints/DNS, Storage, Search, Cosmos DB, project connections, project capability host, model deployment, and monitoring. |
| `15a-private-network-evaluation-only-setup` | Useful only as an evaluation-minimal reference. It deliberately omits Cosmos DB, Search, and the project capability host, so it cannot host the required stateful prompt-agent setup. |
| `43-standard-agent-setup-with-customization` | Useful as a donor for BYO-resource parameterization and monitoring, but it uses public networking and creates one project. It is not the deployment base. |
| `19-private-network-agent-tools` | Not required for prompt agents alone. Use only if future MCP, OpenAPI, Functions, or A2A tool servers must be hosted behind the VNet. |

Official sources:

- [Bicep template catalog](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep)
- [Template 15](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup)
- [Template 15a](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15a-private-network-evaluation-only-setup)
- [Template 43](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/43-standard-agent-setup-with-customization)

## Two-project and network conclusion

One Foundry account can support the two planned projects with separate project capability hosts and separate project connections/data resources, but the official template cannot do so unchanged.

Current Microsoft documentation establishes that:

- VNet injection is configured at the **Foundry account level**.
- All projects in an account share the delegated subnet configuration.
- Each project receives a project-level data proxy.
- Prompt agents use project-level data-proxy infrastructure.
- A project capability host selects that project's Storage, Search, and Cosmos DB connections.
- Capability hosts cannot be updated after creation.

Consequences for this design:

1. Use one account-level `networkInjections` configuration and one dedicated `/24` agent subnet.
2. Do not invent or parameterize unsupported per-project network-injection settings.
3. Create two project child resources, two immutable project capability hosts, and two disjoint connection sets.
4. Deploy the project-data module twice so each project receives separate Storage, Search, and Cosmos DB resources.
5. Share only account-level model deployments and the account-level network injection.

The sample's optional `add-project.bicep` intentionally reuses the first project's Storage, Search, and Cosmos DB resources. That behavior conflicts with the approved project-owned data-estate requirement. It must not be used unchanged.

References:

- [Networking options](https://learn.microsoft.com/azure/foundry/agents/concepts/networking-options)
- [Networking deep dive](https://learn.microsoft.com/azure/foundry/agents/concepts/agents-networking-deep-dive)
- [Standard agent setup](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup)

## Live read-only checks

### Azure context

| Check | Result |
|---|---|
| Subscription | Enabled and matched the requested subscription |
| Cloud | Azure public cloud |
| Region | `northcentralus` |
| Planned resource group | Does not currently exist |
| Bicep CLI | `0.45.15` |
| Foundry project regional documentation | North Central US listed |
| `AIServices` SKU | `S0` listed in North Central US |
| `192.168.0.0/16` overlap with current subscription VNets | None found |

The live provider reports Foundry accounts, projects, project connections, and project capability hosts as available in North Central US. The official templates' hard-coded location allowlists omit `northcentralus`; this is a sample limitation that must be removed or updated during adaptation.

### Provider registrations

| Provider | State |
|---|---|
| `Microsoft.CognitiveServices` | Registered |
| `Microsoft.Network` | Registered |
| `Microsoft.Storage` | Registered |
| `Microsoft.Search` | Registered |
| `Microsoft.DocumentDB` | Registered |
| `Microsoft.OperationalInsights` | Registered |
| `Microsoft.Insights` | Registered |
| `Microsoft.Compute` | Registered |
| `Microsoft.Authorization` | Registered |
| `Microsoft.App` | Registered |
| `Microsoft.ContainerService` | Registered |
| `Microsoft.KeyVault` | Registered |
| `Microsoft.MachineLearningServices` | Registered |

`Microsoft.App` and `Microsoft.ContainerService` are mandatory additions for Foundry network injection even though they were not in the requested nine-provider list.

### Model and quota snapshot

`gpt-5-mini`, version `2025-08-07`, is generally available in North Central US with `GlobalStandard` and `DataZoneStandard` deployment options. The subscription reported:

- `OpenAI.GlobalStandard.gpt-5-mini`: current `0`, limit `1000`
- `OpenAI.DataZoneStandard.gpt-5-mini`: current `0`, limit `300`

Use `gpt-5-mini`/`2025-08-07`/`GlobalStandard` as the initial capacity-driven candidate, not a hard-coded final choice. Recheck catalog status, agent/evaluator compatibility, and quota immediately before generation approval and deployment.

`model-router` `2025-11-18` is also generally available, but no dedicated quota row was returned; it is not the primary preflight recommendation.

### Policy

Inherited subscription and management-group policy assignments exist, including security baseline, audit, deploy/modify, and deny initiatives. A policy named “Block Azure RM Resource Creation” was inspected and only denies legacy classic resource types for selected resource-group tags; it does not deny the modern resources in this design.

The broader initiatives still require a reviewed what-if once templates exist. There are no policy exemptions at the subscription scope.

## AVM assessment

Azure Verified Modules were checked before selecting local module boundaries.

| Concern | AVM candidate | Recommendation |
|---|---|---|
| Foundry account/model/private endpoint | `avm/res/cognitive-services/account` | Candidate; current module supports `allowProjectManagement` and `networkInjections`. Use only after confirming all required properties and outputs in a pinned release. |
| Foundry projects, project connections, capability hosts | None found | Adapt small local modules from official sample 15 using stable APIs. |
| VNet/subnets | `avm/res/network/virtual-network` | Use pinned AVM. |
| Private endpoints | `avm/res/network/private-endpoint` | Use pinned AVM. |
| Private DNS | `avm/res/network/private-dns-zone` | Use pinned AVM. |
| Storage | `avm/res/storage/storage-account` | Use pinned AVM. |
| Azure AI Search | `avm/res/search/search-service` | Use pinned AVM. |
| Cosmos DB | `avm/res/document-db/database-account` | Use pinned AVM; keep Cosmos data-plane role assignment local if needed. |
| Log Analytics | `avm/res/operational-insights/workspace` | Use pinned AVM. |
| Application Insights | `avm/res/insights/component` | Use pinned AVM. |
| Azure Monitor Private Link Scope | `avm/res/insights/private-link-scope` | Use pinned AVM. |
| Diagnostics | `avm/res/insights/diagnostic-setting` | Use pinned AVM where supported. |
| Bastion | `avm/res/network/bastion-host` | Use pinned AVM. |
| Public IP/NIC/NSG | Corresponding `avm/res/network/*` modules | Use pinned AVM. |
| Validation VM | `avm/res/compute/virtual-machine` | Use pinned AVM. |
| Azure RBAC | `avm/res/authorization/role-assignment` | Use when exact child-resource scope and conditions remain expressible; otherwise use a minimal local extension-resource module. |

Do not copy the complete official sample module tree. Retain only Foundry-specific child-resource logic not covered by AVM.

## Recommended resource APIs

Prefer stable APIs. The Foundry provider and Microsoft Learn expose stable `2026-05-01`; the Bicep schema MCP currently returns `2025-06-01`, so generation must compile the chosen stable version with the pinned local Bicep CLI before code review.

| Resource type | Recommended API | Status/notes |
|---|---|---|
| `Microsoft.CognitiveServices/accounts` | `2026-05-01` | Stable; account, identity, project management, private access, account-level network injection |
| `Microsoft.CognitiveServices/accounts/deployments` | `2026-05-01` | Stable; capacity-driven model deployment |
| `Microsoft.CognitiveServices/accounts/projects` | `2026-05-01` | Stable; create exactly two system-assigned projects |
| `Microsoft.CognitiveServices/accounts/projects/connections` | `2026-05-01` | Stable; AAD/managed-identity project connections |
| `Microsoft.CognitiveServices/accounts/projects/capabilityHosts` | `2026-05-01` | Stable; one immutable `Agents` capability host per project |
| `Microsoft.CognitiveServices/accounts/connections` | `2026-05-01` | Stable; only if an account-level monitoring connection is approved |
| `Microsoft.Storage/storageAccounts` | `2025-01-01` | Stable Bicep schema; one per project |
| `Microsoft.Search/searchServices` | `2025-05-01` | Stable; avoid sample's `2024-06-01-preview` |
| `Microsoft.DocumentDB/databaseAccounts` | `2025-04-15` | Stable Bicep schema; one per project |
| `Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments` | `2025-04-15` | Stable; project MI data-plane role |
| `Microsoft.Network/virtualNetworks` and `/subnets` | `2024-07-01` | Stable typed schema |
| `Microsoft.Network/networkSecurityGroups` | `2024-07-01` | Stable |
| `Microsoft.Network/privateEndpoints` | `2024-07-01` | Stable typed schema |
| `Microsoft.Network/privateEndpoints/privateDnsZoneGroups` | `2024-07-01` | Stable |
| `Microsoft.Network/privateDnsZones` | `2024-06-01` | Stable |
| `Microsoft.Network/privateDnsZones/virtualNetworkLinks` | `2024-06-01` | Stable |
| `Microsoft.OperationalInsights/workspaces` | `2025-02-01` | Stable typed schema |
| `Microsoft.Insights/components` | `2020-02-02` | Stable |
| `Microsoft.Insights/privateLinkScopes` and `/scopedResources` | `2021-09-01` | Stable; replaces sample preview |
| `Microsoft.Insights/diagnosticSettings` | `2021-05-01-preview` | **Preview**; current practical API for diagnostic settings. Isolate use in one module. |
| `Microsoft.Network/publicIPAddresses` | `2024-07-01` | Stable; Bastion only |
| `Microsoft.Network/bastionHosts` | `2024-07-01` | Stable |
| `Microsoft.Network/networkInterfaces` | `2024-07-01` | Stable; validation VM has no public IP |
| `Microsoft.Compute/virtualMachines` | `2024-11-01` | Stable typed schema |
| `Microsoft.Authorization/roleAssignments` | `2022-04-01` | Stable |
| `Microsoft.Authorization/roleDefinitions` | `2022-04-01` | Stable existing-resource reference |

### Private endpoint group IDs and DNS

Use these only for the listed service type:

| Target | Group ID | DNS zone |
|---|---|---|
| Foundry account | `account` | `privatelink.services.ai.azure.com`, `privatelink.openai.azure.com`, `privatelink.cognitiveservices.azure.com` |
| Storage | `blob` | `privatelink.blob.core.windows.net` |
| Search | `searchService` | `privatelink.search.windows.net` |
| Cosmos DB for NoSQL | `Sql` | `privatelink.documents.azure.com` |
| Azure Monitor Private Link Scope | `azuremonitor` | Monitor/OMS/ODS/agent-service private zones documented by Azure Monitor |

Query each deployed target's `privateLinkResources` before release; do not generalize group IDs across services.

## Required adaptations to official sample 15

1. Remove the sample location allowlist or add `northcentralus` after the live checks above.
2. Replace one-project orchestration with two fixed project invocations.
3. Deploy separate Storage, Search, and Cosmos DB resources for each project.
4. Create unique project connection names and one capability host per project.
5. Do not use `add-project.bicep` unchanged because it reuses shared data resources.
6. Keep `networkInjections` only on the account; do not add per-project subnet settings.
7. Replace preview Search and Cosmos APIs with the stable versions in this report.
8. Prefer the stable Foundry `2026-05-01` API instead of the sample's `2025-04-01-preview`.
9. Replace timestamp-based names in template 43 with deterministic names.
10. Add the Bastion and private validation-host topology.
11. Remove hosted-agent ACR by default because the confirmed workload is prompt agents. Add it only if hosted agents are later approved.
12. Do not copy the sample's shared App Insights API-key connection and broad project-MI telemetry-reader grants without resolving the monitoring isolation gate.
13. Keep keys, connection strings, passwords, private keys, tokens, and user identifiers out of parameters, outputs, logs, and repository files.

## Planned network contract

| Subnet | Proposed CIDR | Purpose |
|---|---|---|
| `agent-subnet` | `192.168.0.0/24` | Dedicated to the one Foundry account; delegated to `Microsoft.App/environments` |
| `private-endpoint-subnet` | `192.168.1.0/24` | Foundry, data-resource, and monitoring private endpoints |
| `AzureBastionSubnet` | `192.168.2.0/26` | Dedicated Azure Bastion subnet |
| `validation-subnet` | `192.168.3.0/27` | Private validation VM/NIC; no public IP |

No overlap was found against VNet address spaces currently visible in the target subscription. Peered, hub, on-premises, and externally managed networks still require owner confirmation before generation. The validation VM candidate `Standard_B2s` had no regional SKU restrictions in North Central US.

## Generation file map

No files below exist yet; this is the proposed generation map.

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
│  │  ├─ project.bicep
│  │  ├─ project-connections.bicep
│  │  ├─ project-capability-host.bicep
│  │  └─ model-deployment.bicep
│  ├─ data/
│  │  └─ project-data.bicep
│  ├─ network/
│  │  ├─ core-network.bicep
│  │  ├─ private-dns.bicep
│  │  └─ private-endpoints.bicep
│  ├─ monitoring/
│  │  └─ monitoring.bicep
│  ├─ validation/
│  │  └─ bastion-host.bicep
│  └─ access/
│     ├─ project-managed-identity.bicep
│     └─ project-groups.bicep
├─ environments/
│  └─ validation.bicepparam
└─ tests/
   ├─ assert-template.ps1
   ├─ assert-what-if.ps1
   └─ assert-no-secrets.ps1

scripts/
└─ bootstrap-entra-groups.ps1
```

The optional group bootstrap script belongs to the identity-governance boundary. It must not be invoked from Bicep and must return immutable group object IDs without logging membership or personal data.

## Parameter contract

### Bootstrap

- `location = 'northcentralus'`
- `resourceGroupName = 'rg-foundry-permissions-validation'`
- approved non-PII tags

### Foundry and model

- deterministic `foundryAccountName`
- fixed project names:
  - `hoa-project`
  - `one-to-four-residential-contract-project`
- `modelName`
- `modelVersion`
- `modelDeploymentName`
- `modelSkuName`
- `modelCapacity`

### Network

- `vnetAddressPrefix = '192.168.0.0/16'`
- four fixed subnet prefixes from the network contract
- optional existing private DNS zone IDs
- no per-project agent subnet parameter

### Project data

Strongly typed `hoa` and `contract` objects containing only names, SKUs, capacity/retention settings, and feature flags. No keys or connection strings.

### Monitoring

- `monitoringMode`: disabled, shared-admin, or approved per-project mode
- retention and public-query/ingestion settings
- no monitoring credential parameter

### Validation host

- `validationVmSize` default candidate `Standard_B2s`
- generic admin username
- SSH public key only; never store a private key or password
- Bastion SKU and scale settings

### Access

- `hoaGroupObjectId`
- `contractGroupObjectId`
- pinned Foundry User role GUID `53ca6127-db72-4b80-b1b0-d745d6d5456d`
- explicit reviewed project-MI role tuples

## Blockers and conditions

| ID | Gate | Required resolution |
|---|---|---|
| B-01 | Strict sibling non-discoverability remains unproven | Live fresh-token portal, ARM, SDK, and Foundry API tests must pass before release. |
| B-02 | Monitoring/evaluation isolation | Prove that project-scoped App Insights connections with AAD/managed identity work, or approve a shared admin sink that does not grant either project identity sibling-readable telemetry. The official shared API-key pattern is not accepted unchanged. |
| B-03 | Foundry Bicep schema freshness | Compile `2026-05-01` with the pinned Bicep CLI during generation. If typed support fails, use the newest stable typed version; do not fall back to preview solely for convenience. |
| B-04 | Group prerequisites | Governed group creation/verification must supply the two immutable object IDs before access Bicep can be finalized. |
| B-05 | Deployment permissions | The future infrastructure and access identities must prove the planned separation and exact role-assignment permissions. |
| B-06 | Policy and DNS ownership | Review the generated what-if against inherited initiatives and confirm rights to create/link all private DNS zones. |
| B-07 | External network overlap | The subscription-local check passed; confirm the range does not overlap peered, hub, on-premises, or externally managed networks. |
| B-08 | Capacity freshness | Recheck the selected model/version/SKU quota immediately before deployment; catalog availability is not a capacity reservation. |
| B-09 | Capability-host immutability and retry safety | Finalize connection names/data estates before creation and preserve the documented project-capability-host → account purge → subnet-release cleanup order. |
| B-10 | Cosmos throughput | Size each project's Cosmos DB for the current Foundry runtime container requirements; insufficient throughput blocks capability-host provisioning. |

## Final recommendation

Proceed to Bicep generation only after B-02, B-03, B-04, B-06, and B-07 have owners and accepted resolutions. Generate an **adapted, modular composition**, not a copy of one sample:

- AVM for standard Azure resources;
- official sample-derived local modules only for Foundry projects, project connections, and project capability hosts;
- two fixed project/data/capability-host stacks;
- one shared account-level network injection;
- separate access deployment;
- no deployment until static validation and reviewed what-if pass.
