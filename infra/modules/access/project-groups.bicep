@description('Microsoft Foundry account name.')
param accountName string

@description('Immutable HOA Entra security-group object ID.')
param hoaGroupObjectId string

@description('Immutable contract Entra security-group object ID.')
param contractGroupObjectId string

@description('Pinned built-in Foundry User role definition GUID.')
param foundryUserRoleDefinitionId string

var foundryUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryUserRoleDefinitionId)

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

resource hoaProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: account
  name: 'hoa-project'
}

resource contractProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: account
  name: 'one-to-four-residential-contract-project'
}

resource hoaFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: hoaProject
  name: guid(hoaProject.id, hoaGroupObjectId, foundryUserRoleDefinitionId)
  properties: {
    principalId: hoaGroupObjectId
    principalType: 'Group'
    roleDefinitionId: foundryUserRoleId
  }
}

resource contractFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: contractProject
  name: guid(contractProject.id, contractGroupObjectId, foundryUserRoleDefinitionId)
  properties: {
    principalId: contractGroupObjectId
    principalType: 'Group'
    roleDefinitionId: foundryUserRoleId
  }
}

output hoaFoundryUserRoleAssignmentId string = hoaFoundryUser.id
output contractFoundryUserRoleAssignmentId string = contractFoundryUser.id

