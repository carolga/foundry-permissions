# Identity, RBAC, and Strict Project-Isolation Plan

**Owner:** Livingston, Identity & RBAC  
**Status:** Planning only; no principals or role assignments are created by this document  
**Region:** `northcentralus`  
**IaC:** Bicep  
**Network posture:** Private networking  
**Last reviewed:** 2026-07-31

## 1. Locked design and acceptance rule

One Microsoft Foundry resource contains exactly these projects:

- `hoa-project`
- `one-to-four-residential-contract-project`

The tenant contains exactly these corresponding Microsoft Entra security groups:

- `hoa-group`
- `One-to-Four-Residential-Contract`

Each developer group receives only **Foundry User** at its own project scope. No developer group receives a role at management-group, subscription, resource-group, Foundry-resource, or sibling-project scope.

Strict isolation means a single-group user:

1. Can create, update, test, and invoke agents in the user's project.
2. Can create, run, read, and manage evaluations in the user's project.
3. Cannot enumerate, discover by name, open, read, invoke, change, or delete the sibling project or its agents, evaluations, files/datasets, connections, or other project assets.

**Hard gate:** A child/project role assignment cannot negate access inherited from a parent. Any broader direct, group-derived, PIM-active, PIM-eligible-and-activatable, custom-role, or legacy assignment that exposes the sibling project fails isolation unless Carol explicitly accepts the exception. A deny assignment is not accepted as compensation for a broader allow.

## 2. Verification status and role catalog

Role GUIDs must be used in Bicep because Microsoft is still rolling out the Foundry role-name changes. Every role is documentation-verified but remains **tenant-unverified** until the deployment team captures the live role definition and permissions in the target subscription.

| Role | Role-definition ID | Planned use | Verification |
|---|---|---|---|
| Foundry User | `53ca6127-db72-4b80-b1b0-d745d6d5456d` | Each developer group at its own project; initial candidate for each project managed identity at its own project | Microsoft Foundry RBAC docs verified; live tenant and feature tests required |
| Foundry Project Manager | `eadc314b-1a2d-4efa-be10-5d325db5065e` | Not assigned to developer groups; exceptional project administration only | Foundry docs verified; tenant-unverified |
| Foundry Account Owner | `e47c6f54-e4a2-4754-9501-8e0985b135e1` | PIM-eligible Foundry account administrators | Foundry docs verified; tenant-unverified |
| Foundry Owner | `c883944f-8b7b-4483-af10-35834be79c4a` | Not planned; emergency-only alternative to Azure Owner | Foundry docs verified; tenant-unverified |
| Foundry Agent Consumer | `eed3b665-ab3a-47b6-8f48-c9382fb1dad6` | Optional future runtime-only callers, not project authors | Foundry docs verified; tenant-unverified |
| Reader | `acdd72a7-3385-48ef-bd42-f606fba81ae7` | Prohibited for developer groups at parent scopes unless live tests prove no sibling discovery | Azure built-in-role docs verified; tenant-unverified |
| Contributor | `b24988ac-6180-42a0-ab88-20f7382dd24c` | Infrastructure deployer/CI identity at the deployment resource group | Azure built-in-role docs verified; tenant-unverified |
| Owner | `8e3af657-a8ff-443c-a75c-2fe8c4bcb635` | Break-glass only; never routine development | Azure built-in-role docs verified; tenant-unverified |
| Role Based Access Control Administrator | `f58310d9-a9f6-439a-9e8d-f62e7b41a168` | PIM/bootstrap access-deployment identity, narrowly scoped | Azure built-in-role docs verified; tenant-unverified |
| User Access Administrator | `18d7d88d-d35e-4fb5-a5c3-7773c20a72d9` | Not preferred; only if an established tenant process requires it | Azure built-in-role docs verified; tenant-unverified |
| Storage Blob Data Contributor | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | Conditional project-MI access to its own project storage | Azure built-in-role docs verified; architecture and tenant validation pending |
| Storage Blob Data Owner | `b7e6dc6d-f1e8-4753-8033-0f276bb0955b` | Conditional standard-agent `agents-blobstore` requirement only | Azure built-in-role docs verified; architecture and tenant validation pending |
| Search Index Data Contributor | `8ebe5a00-799e-43f5-93ac-243d3dce84a7` | Conditional project-MI access to its own search data | Azure built-in-role docs verified; architecture and tenant validation pending |
| Search Service Contributor | `7ca78c08-252a-4471-8644-bb5ff32d4ba0` | Conditional standard-agent search management | Azure built-in-role docs verified; architecture and tenant validation pending |
| Log Analytics Data Reader | `3b03c2da-16b3-4a49-8834-0f8130efdd3b` | Conditional project-MI access for evaluation telemetry | Azure built-in-role docs verified; architecture and tenant validation pending |
| Cosmos DB Built-in Data Contributor | `00000000-0000-0000-0000-000000000002` | Conditional standard-agent Cosmos data access | Cosmos service-native role, not an Azure RBAC role; account-level validation pending |

Microsoft documents **Foundry User** as the least-privilege developer role for building and testing agents. The evaluation documentation explicitly requires **Foundry User on the Foundry project** to create and run evaluations. Those statements are design evidence, not proof for the selected agent/evaluation features. Linus must prove authoring with live tenant tests.

## 3. Exact scopes

Foundry resource:

```text
/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.CognitiveServices/accounts/<foundryAccountName>
```

HOA project:

```text
/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.CognitiveServices/accounts/<foundryAccountName>/projects/hoa-project
```

One-to-Four Residential Contract project:

```text
/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.CognitiveServices/accounts/<foundryAccountName>/projects/one-to-four-residential-contract-project
```

A Bicep role assignment is an extension resource at `project.id`. Its resulting resource ID follows:

```text
<projectId>/providers/Microsoft.Authorization/roleAssignments/<deterministicGuid>
```

Use:

```bicep
name: guid(project.id, principalId, roleDefinitionId)
scope: project
principalType: 'Group' // developer groups
```

For managed identities and workload identities, use `principalType: 'ServicePrincipal'`. Basher must use the project resource symbolic reference or exact project resource ID, not the Foundry account, resource group, or subscription as a convenience scope.

## 4. Principal and group lifecycle

### 4.1 Group assumptions

- Both groups are cloud-managed, security-enabled, mail-disabled, assigned-membership groups.
- The display names are exact and case-preserved. Bicep consumes immutable object IDs and never performs display-name lookup.
- Each group has at least two business owners from the corresponding project.
- Nested groups and dynamic membership are prohibited for the initial release. They complicate effective-access proof and can silently create cross-project access.
- No direct user-to-project role assignments are allowed. Access flows through the matching group.
- A user needing both projects must be explicitly approved into both groups. This is a documented dual-access exception, not evidence that isolation works.
- Temporary access uses PIM for Groups or a time-bound governed process where licensed. Permanent membership requires project-owner approval and a business justification.
- Membership is reviewed at least quarterly and on owner/role change. Leavers and transfers are removed within the organization's identity-governance SLA.
- Group owners cannot approve their own membership or their own Azure elevation.
- Recreating a deleted group creates a new object ID. Before reuse, remove orphaned role assignments, update Bicep inputs, redeploy, and repeat all isolation tests.

### 4.2 Ownership and evidence

The identity team owns group creation, object-ID validation, owners, access reviews, and membership evidence. Resource administrators own Azure role assignments. Project leads approve project membership. Linus receives non-PII test aliases and expected memberships; raw directory exports, UPNs, access tokens, and personal details remain in the approved secure evidence store outside the repository.

## 5. Role and scope matrix

| Principal | Required role and scope | Explicitly excluded |
|---|---|---|
| Bootstrap deployer (human) | Time-bound/PIM **Contributor** on the deployment resource group plus **Role Based Access Control Administrator** only where assignments are deployed | No standing Foundry User; no routine project data access |
| Foundry account administrators | PIM-eligible **Foundry Account Owner** on the Foundry resource | No standing developer-group membership; no routine project data access |
| RBAC administrators | PIM-eligible **Role Based Access Control Administrator** on the Foundry resource and named backing resources; use approval and short activation | No self-approval; no standing project author role |
| `hoa-group` | **Foundry User** only on `.../projects/hoa-project` | Every parent scope and the contract project |
| `One-to-Four-Residential-Contract` | **Foundry User** only on `.../projects/one-to-four-residential-contract-project` | Every parent scope and the HOA project |
| `hoa-project` managed identity | First test: **Foundry User** at `hoa-project`; conditional data roles only on HOA-specific backing resources | Contract project and contract backing resources |
| Contract-project managed identity | First test: **Foundry User** at the contract project; conditional data roles only on contract-specific backing resources | HOA project and HOA backing resources |
| Infrastructure CI/CD workload identity | Federated identity with **Contributor** on the deployment resource group | No secrets, no Foundry data role, no role-assignment permission in steady state |
| Access CI/CD workload identity | Federated identity with **Role Based Access Control Administrator** only on the Foundry resource and exact backing resources needed for assignments | No Contributor and no project data role |
| Break-glass identities | Emergency **Owner** at the subscription or approved parent scope | No routine use, no developer groups, no pipeline use |

If the organization insists on one CI/CD identity, combining Contributor and RBAC Administrator is allowed only for bootstrap, with approval and time limitation. Steady state must split infrastructure deployment from access administration.

### 5.1 Managed-identity isolation gate

Microsoft's starter guidance assigns Foundry User to a project managed identity at the Foundry-resource scope. That parent scope could be inconsistent with strict sibling isolation. Therefore:

1. Attempt project-scoped Foundry User for each project managed identity first.
2. Prove agent creation, file use, evaluation, and runtime access.
3. If the service requires resource-scoped Foundry User, inspect the live role definition and test whether each project identity can access sibling project data or endpoints.
4. If cross-project access is possible, the one-resource/two-project design fails the asset-isolation gate. Do not accept the parent assignment merely because it is documented as a starter configuration.

Backing resources should be separate per project where feasible. If a storage account, search service, Cosmos account, Key Vault, ACR, or Log Analytics workspace is shared, scope data access to a project-specific container, index, database, repository, table, or other supported child boundary and prove it. If the service cannot enforce that boundary, use separate resources.

## 6. Inheritance analysis

For each test user, both groups, administrators, deployers, CI/CD identities, and project managed identities, inspect:

| Scope | Isolation concern | Gate |
|---|---|---|
| Management group | Owner, Contributor, Reader, custom roles, policy-managed identities, Lighthouse delegation | Any developer/test-user access that can reveal or operate the sibling project fails |
| Subscription | Owner, Contributor, Reader, Foundry roles, custom roles, PIM assignments | Same; subscription Reader also fails strict metadata non-discoverability |
| Resource group | Owner, Contributor, Reader, User Access Administrator, RBAC Administrator, custom roles | Any developer/test-user assignment fails unless explicitly accepted |
| Foundry resource | Foundry User/Manager/Owner, Reader, Contributor, custom roles | Any developer-group assignment fails; parent Reader is prohibited pending portal tests |
| Project | Correct group must have only Foundry User; sibling group must have none | Exact-match pass/fail |
| Connected resources | Storage, Search, Cosmos, Key Vault, ACR, Log Analytics, private DNS/network roles | No developer-group data roles; each project MI accesses only its assets |
| Agent scope | Consumer or other endpoint assignments | Must not expose a sibling agent; enumerate separately |

Custom roles require inspection of `Actions`, `NotActions`, `DataActions`, `NotDataActions`, assignable scopes, and conditions. Role name alone is not evidence.

## 7. Effective-access audit procedure

Run this before group assignment, after assignment, after every membership/elevation change, and as part of release evidence.

### 7.1 Inventory

1. Record immutable IDs for the tenant, subscription, resource group, Foundry resource, both projects, both groups, project managed identities, deployer, and CI/CD identities.
2. Capture the live definitions of every role in section 2. Compare role ID, name, actions, data actions, conditions, and assignable scopes with the approved baseline.
3. At management-group, subscription, resource-group, Foundry-resource, each project, each agent, and each backing-resource scope, list direct and inherited assignments.
4. For each test user, enumerate effective assignments with inherited scopes and group-derived assignments:

   ```text
   az role assignment list --all --assignee <objectId> --include-inherited --include-groups
   ```

5. Enumerate Microsoft Graph `transitiveMemberOf` for test users and `transitiveMembers` for both project groups. Expand every nested group even though nesting is prohibited.
6. Export PIM Azure-resource assignments and activations, including child resources. Separately review PIM for Groups eligible and active membership.
7. Review classic administrators, Azure Lighthouse/delegated management, policy/deployment-stack identities, service-managed assignments, and custom roles.
8. List deny assignments at every scope. Denies can explain an unexpected denial but do not make an unintended parent allow acceptable.

### 7.2 Direct, transitive, PIM, and deny checks

- **Direct:** No test user has a direct assignment except an explicitly documented test setup.
- **Transitive group:** A single-project user resolves to exactly one project group and no privileged or sibling-access group.
- **PIM eligible:** Treat an eligible broader role that the user can activate as an isolation failure unless an explicit exception is approved. Record approval rules and activation history.
- **PIM active:** Deactivate before testing, wait for propagation, and verify the active assignment is gone.
- **Deny:** Record Azure-managed deny assignments and excluded principals. Do not design custom isolation around deny assignments because customers cannot directly create arbitrary deny assignments.

### 7.3 Fresh-token procedure

1. Finish membership and PIM changes and allow at least the documented propagation interval.
2. Sign out from Azure portal and Foundry portal; close all browser sessions and use a new private browser profile.
3. Clear local Azure CLI account/token state, then authenticate as only the intended test identity.
4. Obtain new tokens separately for Azure Resource Manager and the Foundry data endpoint.
5. Never store raw bearer tokens. Record only issuance time, expiry time, tenant/client identifiers where permitted, test alias, and a hash/correlation identifier in the secure evidence store.
6. Repeat portal and direct API tests. Cached success is not accepted as evidence.

## 8. Strict non-discoverability feasibility and decision tree

Microsoft's sample enterprise mapping pairs project-scoped Foundry User with Reader on the Foundry resource. Reader includes `*/read` control-plane access and can expose sibling metadata. Therefore resource-level Reader is **not approved** for either developer group.

Test with no parent Reader:

1. **Own portal experience works; sibling is absent; direct API succeeds only for own project.**  
   Pass. Keep only project-scoped Foundry User.
2. **Portal fails, but own-project API/SDK authoring works and sibling enumeration/direct access is denied.**  
   Strict isolation is technically feasible with an API/SDK-first experience. Carol must decide whether lack of portal authoring is acceptable.
3. **Portal needs only a narrowly identified parent action such as account metadata read.**  
   Trace the exact denied action. Test a custom parent role containing only the minimum account action and excluding project-list/read actions. Approve it only if both portal and API tests show no sibling name, ID, count, URI, or metadata.
4. **Portal requires Reader or parent-level project list/read, and the sibling becomes visible.**  
   Fail strict portal non-discoverability. Do not grant Reader. Options are API/SDK-only authoring or separate Foundry resources; the latter conflicts with the locked topology and requires a design decision.
5. **Any account/project list API reveals the sibling, even though open/data access is denied.**  
   Fail strict non-discoverability.
6. **Sibling access succeeds because of inherited access.**  
   Remove the broader assignment or obtain an explicit exception. Do not attempt to repair it with a project child assignment.

For negative results, `404 Not Found` is preferred. `403 Forbidden` is acceptable only when the response, headers, portal, logs available to the user, and list endpoints do not disclose sibling identity or metadata.

## 9. Authorization scenarios for Linus

Use two clean test users: one member only of `hoa-group`, one member only of `One-to-Four-Residential-Contract`. Add a separate dual-group control user only after single-group tests pass.

### 9.1 Positive scenarios, repeated for each project

- Sign in with fresh portal, ARM, and Foundry tokens.
- Discover/open only the assigned project.
- Read project metadata needed for authoring.
- Create, read, update, and delete a prompt agent.
- Add an approved agent to the assigned project and invoke it.
- Upload/use an approved synthetic file or dataset in the assigned project.
- Create, run, cancel where supported, read, and delete an evaluation.
- Read the evaluation's own project traces/results when the selected evaluation type requires them.
- Confirm no Owner, Contributor, Project Manager, Account Owner, or role-assignment capability.
- Confirm no ability to create projects, deploy account-level models, change networking, obtain keys, or assign roles.

### 9.2 Negative sibling scenarios

- List projects from portal, ARM, Foundry API, SDK, and CLI; sibling must not be returned.
- Open a copied deep link to the sibling project.
- GET the sibling project by exact resource ID and exact known name.
- List/read/create/update/delete sibling agents.
- Invoke a sibling agent endpoint.
- List/read/upload/delete sibling files and datasets.
- List/read/create/run/delete sibling evaluations and read their results/traces.
- List/read/use sibling project connections and backing-resource assets.
- Create any object while supplying the sibling project endpoint or project ID.
- Search browser history, portal recent items, resource selectors, telemetry pickers, and error messages for sibling disclosure.
- Verify own-project deletion or role-management operations remain denied.

Each result records test alias, direct/transitive membership state, PIM state, scope, role ID, operation, expected result, actual HTTP/result code, timestamp, correlation ID, and sanitized evidence location.

## 10. Bicep contract for Basher

### 10.1 Inputs

- `location` constrained to `northcentralus`
- Resource-group and Foundry-account names
- Exact project names, preferably constants:
  - `hoa-project`
  - `one-to-four-residential-contract-project`
- Entra group object IDs:
  - `hoaGroupObjectId`
  - `contractGroupObjectId`
- Administrator group object ID
- Bootstrap deployer and federated CI/CD principal IDs
- Built-in role GUID constants from section 2
- Per-project backing-resource IDs and the approved per-resource role map
- Private-network resource IDs, subnet IDs, private DNS zone IDs, and approved tags

Object IDs are identifiers, not secrets, but must still be validated as the expected principal type. Do not accept UPNs, display-name lookup, client secrets, keys, or connection strings as Bicep parameters.

### 10.2 Non-secret outputs

- Foundry resource ID and name
- `hoa-project` resource ID and endpoint
- Contract-project resource ID and endpoint
- Both project managed-identity principal IDs
- Developer group object IDs used
- Role-assignment resource IDs
- Per-project backing-resource IDs
- Private endpoint and private DNS resource IDs

Do not output keys, connection strings, tokens, credentials, or raw sensitive deployment data.

### 10.3 Deployment ordering

1. Identity team creates/governs groups and supplies verified object IDs outside ARM Bicep. No group creation occurs in this task.
2. Bootstrap approver activates time-bound Contributor and RBAC Administrator access.
3. Deploy resource group, private network, private DNS, private endpoints, and project-specific backing resources.
4. Deploy the single Foundry resource with public access disabled as supported.
5. Deploy both projects and obtain each project resource ID and managed-identity principal ID.
6. Assign each project managed identity only the approved roles on its own backing resources; validate the Foundry User scope using the gate in section 5.1.
7. Deploy deterministic project-scoped role assignments:
   - `hoa-group` → Foundry User → `hoa-project`
   - `One-to-Four-Residential-Contract` → Foundry User → contract project
8. Deploy administrator and CI/CD assignments through the access module.
9. Run Bicep what-if and reject parent-scope developer assignments, display-name principal resolution, or unexpected role changes.
10. Complete the inherited-access audit before adding test users to groups.
11. Add test memberships through the governed identity process, wait for propagation, obtain fresh tokens, and run Linus's matrix.
12. Remove bootstrap elevation and retain only approved steady-state assignments.

Separate Bicep modules should cover infrastructure, project identities/backing-resource access, and human/group RBAC. This supports separation of duties and allows the access module to be reviewed and deployed independently.

## 11. Least-privilege risks and controls

| Risk | Control |
|---|---|
| Parent Reader exposes sibling names | Prohibit it until live portal/API evidence proves strict filtering |
| Parent Foundry User grants both projects | Developer groups receive Foundry User only at their project |
| Broad subscription/RG Contributor or Owner | Treat as failed isolation; use clean test identities and PIM-scoped administration |
| Foundry User role changes over time | Pin GUID, capture live definition, diff actions/data actions before deployment |
| Keys bypass Entra RBAC | Do not distribute keys; use Entra authentication and disable local/key auth where supported |
| Project MI gets account-wide data access | Test project scope first; isolate backing resources; fail if sibling access is possible |
| Shared storage/search/Cosmos/telemetry leaks data | Use per-project resources or enforce and test supported child scopes |
| Nested/dynamic group membership creates hidden access | Assigned membership, no nesting, transitive audit |
| CI/CD credential theft | Workload identity federation; no client secrets; short, scoped permissions |
| One pipeline can deploy resources and grant itself access | Split infrastructure and access identities; approvals and protected environments |
| Orphaned assignments after principal deletion | Remove assignments before principal replacement; deterministic assignment names include principal ID |
| Portal/API cached authorization | Fresh private session and new ARM/Foundry tokens for every evidence run |

## 12. Break-glass and separation of duties

- Maintain at least two monitored emergency identities under the tenant's break-glass standard.
- Break-glass identities are excluded from project groups and routine administration, use phishing-resistant authentication where supported, and are tested periodically.
- Their broad Owner access is an explicit emergency exception to project isolation, not a normal user pattern. Every use triggers incident review.
- Group owners approve membership; RBAC administrators deploy assignments; project leads validate business need; Linus independently validates effective access.
- Infrastructure CI/CD cannot grant access. Access CI/CD cannot modify application/network resources.
- PIM activation requires justification, approval, short duration, and alerts. Administrators cannot approve their own membership or elevation.

## 13. Release gates

The RBAC portion is ready only when:

1. Live role definitions match the approved role IDs and intended permissions.
2. Both group object IDs and owners are verified.
3. No unintended direct, inherited, transitive-group, PIM, Lighthouse, custom-role, or deny-assignment condition remains unexplained.
4. Foundry User proves agent authoring and evaluation create/run for both projects.
5. Portal and API evidence proves sibling non-discoverability, not merely denial of writes.
6. Project managed identities cannot access sibling project assets.
7. All backing-resource permissions are project-specific and tested.
8. Bootstrap elevation is removed and steady-state separation of duties is active.
9. Danny approves the sanitized evidence pack.

## 14. Official Microsoft references

- [Microsoft Foundry architecture and security-driven separation](https://learn.microsoft.com/azure/foundry/concepts/architecture#security-driven-separation-of-concerns)
- [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry)
- [Elevated-role tasks in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/concepts/administrator-guide)
- [Run evaluations from the Microsoft Foundry portal](https://learn.microsoft.com/azure/foundry/how-to/evaluate-generative-ai-app)
- [Azure built-in roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles)
- [Azure privileged built-in roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/privileged)
- [Check access to an Azure resource](https://learn.microsoft.com/azure/role-based-access-control/check-access)
- [List Azure role assignments with inherited and group access](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-list-cli)
- [Azure deny assignments](https://learn.microsoft.com/azure/role-based-access-control/deny-assignments)
- [PIM audit for Azure resource roles](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/azure-pim-resource-rbac)
- [PIM for Groups](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/concept-pim-for-groups)
- [Access reviews for groups](https://learn.microsoft.com/entra/id-governance/create-access-review)
- [Use Bicep for Azure RBAC](https://learn.microsoft.com/azure/azure-resource-manager/bicep/scenarios-rbac)
- [Child resources in Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/child-resource-name-type)
- [Managed identities for Azure resources](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview)
