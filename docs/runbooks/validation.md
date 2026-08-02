# Infrastructure validation runbook

This runbook separates checks that are executable without Azure access from checks that require an approved validation deployment. Use PowerShell 7. Never place credentials, tokens, personal identifiers, live documents, or private keys in commands or evidence.

## Executable now: local static validation

### Prerequisites

- PowerShell 7
- Either Azure CLI with `az bicep`, or the standalone Bicep CLI
- Repository checkout containing:
  - `infra\bootstrap\main.bicep`
  - `infra\main.bicep`
  - `infra\access.bicep`

Run from the repository root:

```powershell
pwsh -NoProfile -File .\infra\tests\Invoke-LocalValidation.ps1
```

The orchestrator:

1. detects an available Bicep compiler;
2. compiles all three entry points into a uniquely named repository-local
   `.validation-work` directory;
3. runs structural, required-tag, secret-safety, identity-bootstrap, and
   policy-compatibility assertions, including the Defender for Storage
   per-account malware-scanning opt-out;
4. deletes only the temporary directory it created; and
5. exits nonzero on any build or assertion failure.

The static checks enforce the approved topology: one Foundry account, two exact projects, disjoint project data/connection/capability-host/monitoring resources, four unconditional Foundry diagnostic settings, one network injection, four fixed subnets, private endpoints and DNS, the complete eight-rule Standard Bastion NSG contract, a validation-subnet allow-before-deny contract that permits only Bastion-originated SSH inbound, all five AMPLS private DNS associations, private/local-auth controls, exact project-scoped Foundry User assignments, parameterized models, and no committed secret-bearing values.

Because the required Ignore tags suppress applicable inherited diagnostic
deployment, Bicep must emit diagnostics directly. Each project sends
`allLogs` and `AllMetrics` only to its matching Log Analytics workspace. The
shared Foundry account uses two uniquely named settings, one to each project
workspace, avoiding an invented central destination and arbitrary coupling to
only one project. Resource-context workspace access remains enabled.

Required-tag checks enforce `SecurityControl=Ignore` and `CostControl=Ignore`
on every taggable declaration, including conditional resources, private DNS
virtual network links, the resource-group bootstrap, and capability-host
property tags. The explicit non-taggable allowlist is limited to role
assignments, Cosmos DB SQL role assignments, Foundry project connections,
diagnostic settings, AMPLS scoped resources, private endpoint DNS zone groups,
Storage blob services, Defender for Storage settings, and generated nested
deployment resources.

The Defender assertion requires exactly two
`Microsoft.Security/defenderForStorageSettings/current` resources, one through
each project-data module instance. Each must override subscription-level
settings, explicitly disable on-upload malware scanning, omit any scan-result
Event Grid topic, retain the narrower Defender plan and sensitive-data threat
detection, and declare no invalid extension-resource tags.

Azure evaluates NSG rules from lower priority numbers to higher numbers and
stops at the first match. The validation NSG therefore allows TCP 22 from the
exact `AzureBastionSubnet` prefix at priority 100, then denies every other
inbound flow at priority 110. The deny is evaluated before Azure's default
priority-65000 `AllowVNetInBound`, overriding broad VNet-originated access
without changing outbound rules or stateful response traffic. See
[Azure network security groups overview](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview).

Run an individual assertion only against compiled ARM JSON:

```powershell
pwsh -NoProfile -File .\infra\tests\Assert-Template.ps1 -TemplatePath <compiled-template-json>
pwsh -NoProfile -File .\infra\tests\Assert-RequiredTags.ps1 -SourcePath .\infra -TemplatePath <compiled-template-json>
pwsh -NoProfile -File .\infra\tests\Assert-NoSecrets.ps1 -SourcePath .\infra -TemplatePath <compiled-template-json>
pwsh -NoProfile -File .\infra\tests\Assert-IdentityBootstrap.ps1 -SourcePath .
pwsh -NoProfile -File .\infra\tests\Assert-PolicyCompatibility.ps1 -SourcePath .\infra -TemplatePath <compiled-template-json>
```

## Future: validation and what-if

These steps require approved read/deployment access and are not performed by the local scripts.

When the planned resource group is absent, validate the bootstrap and infrastructure
at subscription scope. The repository-owned validation wrapper declares the resource
group and invokes `infra\main.bicep` at resource-group scope; validation and what-if
do not create the resource group or deploy resources.

```powershell
$validateHelper = Join-Path $HOME '.agents\skills\azure-validate\references\recipes\scripts\validate-deployment.ps1'

pwsh -NoProfile -File $validateHelper `
  -Scope sub `
  -Location northcentralus `
  -Template .\infra\bootstrap\main.bicep `
  -Parameters .\infra\bootstrap\no-parameters.json `
  -Subscription <subscription-id>

pwsh -NoProfile -File $validateHelper `
  -Scope sub `
  -Location northcentralus `
  -Template .\infra\tests\subscription-validation-wrapper.bicep `
  -Parameters .\infra\tests\no-parameters.json `
  -Subscription <subscription-id>
```

The deliberately absent parameter paths make the shared helper use safe Bicep
defaults; do not invent `main.parameters.json`. For authoritative change counts,
also run `az deployment sub what-if` with `--result-format ResourceIdOnly`,
`--no-pretty-print`, and JSON output. Record `Unsupported` separately from
Create/Modify/Delete. Runtime-derived managed-identity role assignments can be
reported as unsupported even when subscription validation succeeds; verify those
assignments statically before deployment and live after deployment.

Command templates:

```powershell
az deployment sub validate --location northcentralus --template-file .\infra\bootstrap\main.bicep --parameters @<secure-bootstrap-parameters>
az deployment sub what-if --location northcentralus --template-file .\infra\bootstrap\main.bicep --parameters @<secure-bootstrap-parameters>

az deployment group validate --resource-group <validation-resource-group> --template-file .\infra\main.bicep --parameters @<secure-infrastructure-parameters>
az deployment group what-if --resource-group <validation-resource-group> --template-file .\infra\main.bicep --parameters @<secure-infrastructure-parameters>

az deployment group validate --resource-group <validation-resource-group> --template-file .\infra\access.bicep --parameters @<secure-access-parameters>
az deployment group what-if --resource-group <validation-resource-group> --template-file .\infra\access.bicep --parameters @<secure-access-parameters>
```

1. Re-run local validation and retain the commit ID, Bicep version, template hashes, and test result.
2. Validate each deployment at its intended scope.
3. Run resource-group what-if for infrastructure and access separately.
4. Reject unexpected deletes, broad role assignments, shared customer-data connections, public access, key authentication, missing or changed `SecurityControl=Ignore` / `CostControl=Ignore` tags, unapproved additional bypass tags, or resources outside the approved region.
5. Confirm exactly one account and the two named projects.
6. Confirm exactly four unconditional diagnostic settings: two shared-account
   settings targeting the two distinct project workspaces, plus one setting
   from each project to its matching workspace. Every setting must enable
   `allLogs` and `AllMetrics`.
7. Confirm group role assignments use Foundry User GUID `53ca6127-db72-4b80-b1b0-d745d6d5456d` at the exact project resource IDs only.
8. After deployment, run a second what-if. Only documented platform/policy drift is acceptable.

Use placeholder parameter files supplied through the approved secure workflow. Do not commit group object IDs, tenant-specific identifiers, SSH key material, or deployment credentials.

## Defender for Storage remediation validation

The subscription-level Defender for Storage V2 plan can remain enabled while
the two project Storage accounts override only on-upload malware scanning. The
resource is the non-taggable extension type
`Microsoft.Security/defenderForStorageSettings@2025-06-01`, named `current` at
the Storage-account scope.

Before any approved remediation deployment, verify the proposed template has
exactly these properties for both accounts:

```bicep
properties: {
  isEnabled: true
  malwareScanning: {
    onUpload: {
      isEnabled: false
    }
  }
  overrideSubscriptionLevelSettings: true
  sensitiveDataDiscovery: {
    isEnabled: true
  }
}
```

Use `ResourceIdOnly` for authoritative Create/Modify/Delete counts and compare
its Deploy set to the validated baseline. Use `FullResourcePayloads` only to
confirm the two additional entries are the Defender settings; provider
normalization can report pre-existing resources as Modify. Existing unmanaged
Event Grid system topics can appear as ignored runtime resources, but the
template must not delete them. Reject any application-resource delete or any
full-payload differential beyond the two Defender settings.

Only after a separately approved deployment:

1. read both live Defender settings and confirm the override is active and
   on-upload scanning is disabled;
2. wait for auto-provisioning to stabilize;
3. delete only the two Defender-generated system topics identified from their
   Storage-account source and `StorageAntimalwareSubscription` child;
4. confirm no topic is recreated; and
5. rerun the complete inventory and policy review.

Disabling on-upload malware scanning removes blob-upload malware inspection and
its associated Event Grid trigger. Defender threat detection and
sensitive-data discovery remain enabled.

## Postdeployment: private network and DNS

Run from the Bastion-reached private validation VM:

```powershell
Resolve-DnsName <service-fqdn> -Type A
Test-NetConnection <service-fqdn> -Port 443 -InformationLevel Detailed
```

1. Resolve every Foundry, Storage Blob, Search, Cosmos SQL, and Azure Monitor FQDN.
   The AMPLS private endpoint must associate all five documented zones:
   `privatelink.monitor.azure.com`,
   `privatelink.oms.opinsights.azure.com`,
   `privatelink.ods.opinsights.azure.com`,
   `privatelink.agentsvc.azure-automation.net`, and
   `privatelink.blob.core.windows.net`.
2. Record the resolver, CNAME chain, private address, expected private endpoint alias, UTC time, and sanitized output hash.
3. Test TCP 443 and the smallest authenticated own-project operation.
4. Verify the VM NIC has no public IP and uses `validation-subnet`.
5. Verify Bastion uses `AzureBastionSubnet`.
6. Verify each private endpoint is associated with the expected group ID and DNS zone.
7. Verify the Bastion subnet NSG retains all four inbound and all four outbound
   documented rules. On the validation subnet, verify priority 100 allows only
   TCP 22 from the exact `AzureBastionSubnet` prefix and priority 110 denies all
   other inbound traffic, ahead of default `AllowVNetInBound` at priority
   65000.

From an approved external client with no private route or private DNS, prove that public operations fail. A public-path success is a release-blocking defect.

## Clean-user RBAC matrix

Use non-personal test aliases only:

| Alias | Own project | Sibling project |
|---|---|---|
| `T-HOA-ONLY` | HOA: allow required authoring | Contract: absent and denied |
| `T-CONTRACT-ONLY` | Contract: allow required authoring | HOA: absent and denied |
| `T-NO-ACCESS` | None | Both absent and denied |
| `T-DUAL-CONTROL` | Both intentionally allowed | Control only; run after single-project gates |

Before testing, audit direct assignments, inherited scopes, transitive and dynamic groups, PIM active/eligible roles, Lighthouse, classic administrators, custom roles, deny assignments, and service-managed assignments. Test identities must have no parent Reader, account-level Foundry role, privileged group path, or sibling membership.

## Fresh-token protocol

After every role, membership, PIM, or deny-assignment change:

1. Record the sanitized change alias and UTC time `T0`.
2. End portal sessions and use a new private browser profile.
3. clear approved CLI/SDK token caches without printing tokens;
4. acquire fresh ARM and Foundry tokens;
5. record issue/expiry times only;
6. run a minimal probe, then the applicable matrix; and
7. retry with newly issued tokens at approved propagation checkpoints.

Never preserve bearer tokens, cookies, authentication headers, or cache files. Any fresh-token sibling disclosure is a defect even if later retries converge.

## Strict non-discoverability

For each single-project identity, test portal, ARM, Foundry API/SDK/CLI, Resource Graph/search, selectors, recent items, copied deep links, connections, traces, files, datasets, evaluations, and backing resources.

Pass requires:

- the sibling is absent from lists, counts, search, pickers, and recent items;
- known sibling identifiers do not reveal name, ID, URI, tags, endpoint, assets, or counts;
- `404` is preferred;
- `403` is acceptable only when response bodies, headers, logs, and UI reveal no sibling metadata; and
- no parent Reader is added to make the portal work.

A visible but non-editable sibling is a failure.

## Prompt-agent and evaluation CRUD

Run symmetrically for both single-project identities.

Own project:

1. create, read, update, invoke, list, and delete a synthetic extraction/QC prompt agent;
2. upload/use only approved synthetic project artifacts;
3. create, run, read, cancel where supported, list, and delete an evaluation; and
4. use the approved model through the project.

Sibling project:

- repeat list/get/create/update/invoke/delete attempts using known sanitized aliases;
- verify no asset, connection, trace, result, file, dataset, or metadata is returned; and
- verify each project managed identity is denied the sibling Storage, Search, and Cosmos estate.

Do not test with live documents or prompts containing personal data.

## Evidence schema

Store sensitive artifacts outside the repository. Repository-safe manifests may contain:

| Field | Content |
|---|---|
| `test_run_id`, `test_case_id` | Stable non-sensitive aliases |
| `environment` | Validation environment alias |
| `principal`, `group` | Non-personal aliases only |
| `role`, `scope` | Role name/GUID and sanitized scope alias |
| `project`, `interface`, `operation` | Exact test target and action |
| `expected`, `actual`, `result` | Allow/deny/absent and pass/fail/blocked |
| `token_time` | Issue/expiry timestamps only |
| `timestamp` | UTC start/end |
| `status_code`, `correlation_id` | Sanitized platform metadata |
| `propagation_context` | Change time and retry number |
| `artifact_hash`, `artifact_location` | SHA-256 and secure-store reference |
| `tool_versions` | PowerShell, Bicep, CLI/SDK, model/evaluator |
| `defect_id` | Tracking alias when failed |

Never record raw tokens, secrets, keys, connection strings, user names, email addresses, unrelated tenant inventory, or live document content.
