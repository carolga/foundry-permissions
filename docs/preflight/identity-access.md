# Identity, RBAC, Entra, and Policy Preflight

**Run:** 2026-07-31  
**Mode:** Read-only; no groups, memberships, resources, policies, or role assignments were changed  
**Overall outcome:** **BLOCKED**

The Azure context and live Foundry role GUID are correct, and the deploying identity has sufficient Azure authority. Deployment remains blocked because both required Entra groups are absent, their immutable object IDs and approved owners are unresolved, the current identity violates the planned separation-of-duties model, and strict sibling non-discoverability cannot be proven before the projects and clean test users exist.

## 1. Prerequisite verdicts

| Prerequisite | Verdict | Safe evidence / reason |
|---|---|---|
| Active Azure context | **PASS** | Subscription `<subscription-name>` (`<subscription-id>`), tenant `<tenant-id>`, state `Enabled`. No UPN was retrieved or recorded. |
| Planned resource group | **CONDITIONAL** | `rg-foundry-permissions-validation` does not exist. Only inherited management-group and subscription controls can be evaluated now. |
| Live Foundry role IDs | **PASS** | The planned Foundry User GUID resolves to the live built-in **Foundry User** role. No GUID/name drift was found. |
| Foundry User suitability | **CONDITIONAL** | The live role is broad and must still pass feature-specific own-project and sibling-denial tests at child scope. |
| Exact Entra groups | **BLOCKED** | `hoa-group`: **not found**. `One-to-Four-Residential-Contract`: **not found**. No members or owners were enumerated. |
| Azure deployment authority | **PASS (capability)** | The current principal has active Owner at the subscription and management-group scopes and inherited User Access Administrator at management-group scope. This covers resource creation and role-assignment operations. |
| Deployment identity governance | **BLOCKED** | The current principal is overprivileged for steady-state deployment and also has Foundry User at subscription scope. It must not be used as an isolation-test identity. Use separate bootstrap, infrastructure, and access identities. |
| Graph group bootstrap | **BLOCKED pending inputs** | The active delegated token includes `Group.ReadWrite.All`, and the tenant default permits users to create security groups. Approved owner object IDs and an operator able to establish owners are unresolved; the current directory role is read-only. |
| Azure Policy compatibility | **CONDITIONAL** | No reviewed policy denies the planned resource types, private endpoints, or `northcentralus`. Policies will modify local/public access and deploy centralized diagnostics. Provisioned Azure OpenAI capacity is explicitly denied. |
| Inherited-access proof | **BLOCKED until postdeployment** | The projects and clean test users do not exist. Strict sibling non-discoverability remains a hard release gate. |

## 2. Safe identity and role evidence

### Deploying identity

- Principal type: user
- Object ID: redacted (tenant-specific deploying-user principal ID)
- Relevant effective Azure assignments:
  - Owner at `/subscriptions/<subscription-id>`
  - Owner at the tenant management-group scope
  - User Access Administrator inherited from the tenant management-group scope
  - Foundry User at subscription scope
- Subscription deny assignments: none found

The identity can create the resource group, deploy resources, and create role assignments. Its standing breadth conflicts with the approved least-privilege design. The subscription-scoped Foundry User assignment also makes this identity unsuitable for either positive or negative project-isolation testing.

### Live Foundry role catalog

| Live role | Live GUID | Drift |
|---|---|---|
| Foundry User | `53ca6127-db72-4b80-b1b0-d745d6d5456d` | None |
| Foundry Project Manager | `eadc314b-1a2d-4efa-be10-5d325db5065e` | None |
| Foundry Account Owner | `e47c6f54-e4a2-4754-9501-8e0985b135e1` | None |
| Foundry Owner | `c883944f-8b7b-4483-af10-35834be79c4a` | None |
| Foundry Agent Consumer | `eed3b665-ab3a-47b6-8f48-c9382fb1dad6` | None |

The live Foundry User definition includes:

- control-plane reads across `Microsoft.CognitiveServices`;
- `Microsoft.CognitiveServices/accounts/listkeys/action`;
- ARM deployment actions;
- `Microsoft.CognitiveServices/*` data actions;
- exclusions for user-identity impersonation and specified fine-tuning deployment writes.

This is not proof of isolation. At project scope, verify that parent-only actions cannot be exercised, no sibling metadata is returned, local/key authentication remains disabled, and the required agent/evaluation operations work.

## 3. Entra group and Graph preflight

| Exact display name | Result | Object ID |
|---|---|---|
| `hoa-group` | Not found | Unresolved |
| `One-to-Four-Residential-Contract` | Not found | Unresolved |

### Required bootstrap object shape

Use a separate identity-owned script, not Bicep or an ARM deployment script:

| Property | HOA group | Contract group |
|---|---|---|
| `displayName` | `hoa-group` | `One-to-Four-Residential-Contract` |
| `mailNickname` | `hoa-group` | `One-to-Four-Residential-Contract` |
| `securityEnabled` | `true` | `true` |
| `mailEnabled` | `false` | `false` |
| `groupTypes` | `[]` | `[]` |
| membership | Assigned; no dynamic rule | Assigned; no dynamic rule |
| owners | Approved owner object IDs required | Approved owner object IDs required |

### Graph permissions

- Exact-name lookup/verification: use `Group.Read.All` or `Group.ReadWrite.All`.
- Delegated creation: `Group.ReadWrite.All`.
- App-only creation: least-privileged `Group.Create`; add `Group.Read.All` for idempotent lookup.
- App-only creation with user owners: also requires `User.Read.All`; use `Directory.Read.All` if owners can include users or service principals.
- Adding owners after creation requires `Group.ReadWrite.All` and, for delegated operation, a supported Entra role such as Groups Administrator or a custom role granting the owner-update action.

The current token contains `Group.ReadWrite.All`, and tenant policy reports that default users may create security groups. However, the current principal's directory role is Global Reader, so owner-update authority is not established. Do not create ownerless groups.

### Fail-safe bootstrap behavior

1. Query only each exact display name and select only non-PII group properties.
2. Zero matches: create only when the operator has the approved Graph permission and owner inputs.
3. One match: validate exact name, security enabled, mail disabled, assigned membership, and approved ownership; do not silently repair drift.
4. More than one match: fail as ambiguous and emit no object ID.
5. Treat any authorization failure, missing owner, property mismatch, or post-create read-back mismatch as fatal.
6. Never enumerate members, owners beyond the supplied owner IDs, or unrelated groups.
7. Output only the two group object IDs and a sanitized status.

## 4. Azure RBAC deployment requirements

### Capability required

- Creating the currently absent resource group: Contributor or Owner at subscription scope.
- Deploying resources inside it: Contributor at the resource-group scope.
- Creating project and backing-resource role assignments: Role Based Access Control Administrator, User Access Administrator, or Owner at the exact assignment scopes.

### Approved operating model

- Bootstrap operator: time-bound/PIM subscription authority only for resource-group bootstrap.
- Infrastructure identity: federated Contributor on `rg-foundry-permissions-validation`; no Graph, Foundry data, or role-assignment permission.
- Access identity: federated deployment permission plus Role Based Access Control Administrator only at the two projects and approved backing-resource scopes.
- Isolation testers: clean non-admin identities with no parent RBAC, privileged group, Lighthouse, PIM, or direct assignment path.

Before deployment, replace the current broad identity with the approved split or record an explicit, time-bound bootstrap exception. Remove bootstrap elevation after deployment.

## 5. Policy evidence

Eight effective assignments were returned: five inherited from the tenant management group and three subscription Security Center initiatives. Enforcement mode is `Default`; no subscription policy exemptions were found.

### Relevant inherited assignments

| Assignment | Effect on this design | Verdict |
|---|---|---|
| `MCAPSGovDenyPolicies` | Denies Azure OpenAI `ProvisionedManaged` deployments; blocks selected VM SKUs and legacy/disallowed types. None of the 57 disallowed types matches the planned Foundry, project, Storage, Search, Cosmos, Key Vault, VNet, private endpoint, or private DNS types. | **CONDITIONAL** |
| `MCAPSGovDeployPolicies` | Modifies Cognitive Services to disable local auth; disables public network access on Storage, Key Vault, and Cosmos; deploys diagnostics for Cognitive Services and Foundry projects; creates central governance diagnostics resources. | **CONDITIONAL** |
| `MCAPSGovAuditPolicies` | Audits security and diagnostics posture; no reviewed item imposes a location or planned-resource-type deny. | **PASS with compliance follow-up** |
| `Azure_Security_Baseline` | Broad inherited security baseline. No assignment-level override or exemption was found. | **CONDITIONAL** |
| `Block Azure RM Resource Creation` | Despite its name, its rule denies only classic resource types when its `ringValue` condition matches. It does not block ARM/Bicep resources in this plan. | **PASS** |

### Specific policy implications

- **Model SKU:** `ProvisionedManaged` is blocked. Choose a permitted deployment SKU or obtain an approved policy exception before model deployment.
- **Location:** no effective allowed-location policy was found in the reviewed assignments; `northcentralus` is not policy-blocked. Regional capability and quota remain separate gates.
- **Private endpoints:** no policy blocking private endpoints or private DNS was found.
- **Public access:** Storage, Key Vault, and Cosmos public access is modified to `Disabled`, which aligns with the plan. The reviewed Foundry-hub public-network policy targets legacy `Microsoft.MachineLearningServices/workspaces` hubs, not the planned Cognitive Services account.
- **Local authentication:** Cognitive Services local authentication is modified off. Bicep must explicitly match this setting and must not depend on account keys.
- **Diagnostics:** policy deploys `allLogs` and `AllMetrics` diagnostic settings for Cognitive Services accounts and `Microsoft.CognitiveServices/accounts/projects`, targeting the central `McapsGovernance` storage account. Confirm that developer groups have no access to this destination and that shared telemetry cannot reveal sibling metadata.
- **Managed identities:** reviewed identity-modification policies target virtual machines, not the planned Foundry project identities.
- **Tags (original preflight finding):** no required-tag deny was found for planned resources. The initial review treated `SecurityControl=Ignore` as requiring a separately approved exception.
- **Superseding implementation direction (attested 2026-08-01T00:56:55.852-05:00):** Carol explicitly required `SecurityControl=Ignore` and `CostControl=Ignore` on every taggable deployed resource regardless of the policy assessment. Validation and what-if must confirm both exact locked values without erasing this original finding.
- **Policy-generated resources:** policy can create the `McapsGovernance` resource group and diagnostics storage resources in `WestUS2`. Treat them as tenant controls, not project-owned infrastructure.

## 6. Exact deployment inputs

### Known

```text
tenantId = <tenant-id>
subscriptionId = <subscription-id>
resourceGroupName = rg-foundry-permissions-validation
location = northcentralus
hoaProjectName = hoa-project
contractProjectName = one-to-four-residential-contract-project
foundryUserRoleDefinitionId = 53ca6127-db72-4b80-b1b0-d745d6d5456d
```

Role assignments must use:

```text
hoaGroupObjectId -> Foundry User -> <foundryAccountId>/projects/hoa-project
contractGroupObjectId -> Foundry User -> <foundryAccountId>/projects/one-to-four-residential-contract-project
principalType = Group
assignmentName = guid(projectId, groupObjectId, foundryUserRoleDefinitionId)
```

### Unresolved before access-module generation/deployment

- `hoaGroupObjectId`
- `contractGroupObjectId`
- approved owner object IDs for both groups
- `foundryAccountName`
- administrator group object ID
- bootstrap, infrastructure, and access principal IDs
- exact VNet, subnet, private DNS, and diagnostic-destination resource IDs
- approved backing-resource role map
- permitted model deployment SKU
- decision on policy-enforced centralized diagnostics and isolation evidence

Do not pass display names, UPNs, credentials, keys, tokens, or connection strings to Bicep.

## 7. Inherited-access audit gates

### Checks possible now

- Active tenant/subscription confirmed.
- Deploying identity's relevant effective roles confirmed.
- Planned resource group confirmed absent.
- Live Foundry role definitions captured.
- Exact group names checked without member/owner enumeration.
- Effective management-group/subscription policy assignments reviewed.
- Subscription deny assignments and policy exemptions checked; none found.

### Required after groups exist, before membership

1. Validate each group object ID and immutable properties.
2. Audit direct Azure assignments for each group from management group through each project and backing resource.
3. Verify no group nesting, dynamic membership, privileged-group path, Lighthouse delegation, custom role, deny-assignment exception, or parent Foundry/Reader assignment.
4. Capture live role-definition drift again immediately before what-if/deployment.

### Required after deployment with clean test users

1. Use one test user only in `hoa-group` and one only in `One-to-Four-Residential-Contract`.
2. Audit direct assignments, transitive memberships, PIM active/eligible roles, classic administration, Lighthouse, custom roles, and inherited assignments.
3. Obtain fresh ARM and Foundry tokens after propagation.
4. Prove required agent, file/dataset, inference, and evaluation operations in the assigned project.
5. Prove the sibling is absent from portal, ARM/API/SDK/CLI lists, Resource Graph/search, selectors, recent items, telemetry pickers, errors, and copied deep links.
6. Prove exact sibling project, agent, file, dataset, connection, evaluation, trace, and backing-resource operations fail without disclosing metadata.
7. Prove each project managed identity cannot access the sibling project or data estate.
8. Verify policy-created central diagnostics are not readable by either developer group.

Any sibling name, ID, count, URI, asset, telemetry, or data disclosure is a deployment failure. A `403` that reveals sibling metadata is not sufficient; `404` or complete omission is preferred.

## 8. Required remediation sequence

1. Approve owner object IDs and a time-bound Graph bootstrap operator.
2. Generate and review the idempotent group bootstrap script with fail-closed behavior.
3. Execute the script outside Bicep, then supply the two verified group object IDs.
4. Establish separate bootstrap, infrastructure, and access identities; do not use the current identity for isolation evidence.
5. Select a model SKU other than `ProvisionedManaged`, unless a policy exception is approved.
6. Reconcile Bicep with policy-enforced local-auth, public-network, and diagnostics settings.
7. Approve the central diagnostics isolation approach.
8. Run Bicep validation and what-if; reject parent-scope developer assignments and unexpected policy changes.
9. Deploy without adding test members, run the group/inherited-access audit, then add clean test users.
10. Complete the fresh-token positive/negative isolation matrix before release.
