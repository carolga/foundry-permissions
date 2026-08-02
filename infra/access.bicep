targetScope = 'resourceGroup'

@description('Microsoft Foundry account name returned by the infrastructure deployment.')
param foundryAccountName string

@description('Immutable object ID for the pre-created hoa-group security group.')
@minLength(36)
@maxLength(36)
param hoaGroupObjectId string

@description('Immutable object ID for the pre-created One-to-Four-Residential-Contract security group.')
@minLength(36)
@maxLength(36)
param contractGroupObjectId string

@description('Pinned built-in Foundry User role definition GUID.')
@minLength(36)
@maxLength(36)
param foundryUserRoleDefinitionId string = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

module projectGroups './modules/access/project-groups.bicep' = {
  name: 'project-group-access'
  params: {
    accountName: foundryAccountName
    contractGroupObjectId: contractGroupObjectId
    foundryUserRoleDefinitionId: foundryUserRoleDefinitionId
    hoaGroupObjectId: hoaGroupObjectId
  }
}

output hoaFoundryUserRoleAssignmentId string = projectGroups.outputs.hoaFoundryUserRoleAssignmentId
output contractFoundryUserRoleAssignmentId string = projectGroups.outputs.contractFoundryUserRoleAssignmentId

