# Entra Group Identity Bootstrap

## Purpose and boundary

This runbook validates or creates only these assigned Microsoft Entra security
groups:

- `hoa-group`
- `One-to-Four-Residential-Contract`

The script does not create users, memberships, Azure role assignments, or Azure
resources. Bicep receives immutable group object IDs and never discovers a
principal by display name.

## Required authority

Use PowerShell 7+, Azure CLI, and an Azure CLI sign-in scoped to the intended
tenant. No client secret is requested or persisted.

This runbook supports one tested authorization model: a delegated work/school
operator.

- Microsoft Graph delegated `Group.ReadWrite.All` is required.
- Tenant policy and directory role governance must permit security-group
  creation with owners. Use a time-bound supported role such as Groups
  Administrator when tenant policy requires it.
- Global Reader is read-only and is not sufficient for owner management.

Use the tenant's normal consent and governance process for delegated
`Group.ReadWrite.All`. The script rejects application-only tokens and delegated
tokens without that scope. Application permissions are not claimed or
supported by this workflow.

Azure subscription Owner, Contributor, or User Access Administrator does not
grant Microsoft Graph authority. A time-bound Azure Owner exception may support
later Azure bootstrap work, but this script independently proves the Graph token
tenant and delegated permission claims, binds all approved owners in the initial
create request, and verifies the owner IDs after creation.

The script intentionally does not pre-read
`/directoryObjects/{ownerId}`. Each approved owner ID is supplied through
`owners@odata.bind` in the initial `POST /groups` request. Microsoft Graph
therefore validates and binds the complete owner set as part of the atomic
creation operation; an invalid or unreadable binding fails creation rather than
creating an ownerless group. This preserves fail-closed behavior without the
broader delegated `Directory.Read.All` scope.

The supplied owner arrays are the complete approved owner sets. An existing
group with missing or additional owners fails closed; the script does not repair
it. Owner read-back requests select only `id`. Microsoft Graph limited-
information responses are acceptable because no other owner properties are
needed.

## Preflight

1. Obtain the approved owner object IDs through the governed identity process.
2. Activate any required time-bound Entra role.
3. Sign in with Azure CLI to the intended tenant.
4. Confirm no group membership or Azure RBAC change is bundled with this step.
5. Keep tenant-specific IDs in the secure deployment system, not in source
   control.

## Safe preview

`-WhatIf` validates local owner and tenant parameter formats, then exits without
calling Azure CLI or Microsoft Graph. It cannot report whether a group already
exists.

```powershell
& .\scripts\bootstrap-entra-groups.ps1 `
  -HoaOwnerObjectId @('<approved-owner-guid-1>', '<approved-owner-guid-2>') `
  -ContractOwnerObjectId @('<approved-owner-guid-3>', '<approved-owner-guid-4>') `
  -TenantId '<tenant-guid>' `
  -WhatIf
```

## Governed execution

Run from an approved administrative workstation or pipeline:

```powershell
$groups = & .\scripts\bootstrap-entra-groups.ps1 `
  -HoaOwnerObjectId @('<approved-owner-guid-1>', '<approved-owner-guid-2>') `
  -ContractOwnerObjectId @('<approved-owner-guid-3>', '<approved-owner-guid-4>') `
  -TenantId '<tenant-guid>'

$groups | Format-Table GroupLabel, ObjectId, Status
```

The only success records are the exact group label, immutable object ID, and
`Created` or `Existing` status. The script fails nonzero for wrong tenant,
authorization failure, ambiguous names, property drift, owner drift, rejected
owner bindings, or unsafe post-create verification.

Creation includes approved owners in the initial Graph payload, so there is no
ownerless interval. If same-invocation post-create verification fails, the
script first verifies the returned object ID and exact label, then deletes only
that newly created object. It never deletes a preexisting group.

Rollback is fail-closed, not best-effort. It is attempted only for an object ID
returned by a creation request made in the current invocation. If the script
cannot verify the rollback target, deletion is declined, or Microsoft Graph
does not confirm the delete request, execution ends with the created group ID
and manual-remediation guidance and explicitly states that the system is not
known to be clean. Do not rerun until the governed identity operator resolves
that object. No unverifiable group is reported as success, and no preexisting
group is modified or deleted.

## Pass immutable IDs to Bicep

Keep the returned objects in memory and pass their IDs to validation, what-if,
and deployment commands. Do not place tenant-specific IDs in committed Bicep
parameter files.

```powershell
$hoaGroupObjectId = (
  $groups | Where-Object GroupLabel -CEQ 'hoa-group'
).ObjectId

$contractGroupObjectId = (
  $groups |
    Where-Object GroupLabel -CEQ 'One-to-Four-Residential-Contract'
).ObjectId

az deployment group what-if `
  --resource-group '<deployment-resource-group>' `
  --template-file '.\infra\main.bicep' `
  --parameters `
    hoaGroupObjectId=$hoaGroupObjectId `
    contractGroupObjectId=$contractGroupObjectId
```

Use the same ephemeral variables for deployment after reviewing what-if. In CI,
store IDs as governed environment-specific configuration or protected pipeline
variables. Object IDs are not credentials, but they are tenant-specific and
must not become portable defaults.

## Later membership and isolation testing

Do not add members during group bootstrap. After Azure deployment and the
inherited-access audit, identity governance must manually provision clean test
users and approve membership:

- one test user only in `hoa-group`;
- one test user only in `One-to-Four-Residential-Contract`.

The users must have no parent Azure RBAC, privileged or nested group path,
active or eligible PIM role, Lighthouse delegation, direct assignment, or
cached test session. Membership creation and user lifecycle remain separate,
manual/governed steps. After propagation, obtain fresh tokens and run the
positive own-project and negative sibling non-discoverability matrix.

## Cleanup and evidence

Record only the exact labels, object IDs, statuses, execution time, and approval
reference in the approved evidence store. Never record access tokens, Graph
response bodies, user principal names, member lists, or personal owner details.
Deactivate time-bound Entra and Azure bootstrap elevation when the governed
work is complete.

## Microsoft Graph references

- [Create group: delegated work/school least privilege is `Group.ReadWrite.All`](https://learn.microsoft.com/graph/api/group-post-groups?view=graph-rest-1.0)
- [List group owners: `Group.ReadWrite.All` and limited-information responses](https://learn.microsoft.com/graph/api/group-list-owners?view=graph-rest-1.0)
- [Delete group](https://learn.microsoft.com/graph/api/group-delete?view=graph-rest-1.0)
