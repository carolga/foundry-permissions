@description('Microsoft Foundry account name.')
param accountName string

@description('Exact project child name.')
param projectName string

@description('Project display name.')
param displayName string

@description('Project description.')
param projectDescription string

@description('Azure region for the project.')
param location string

@description('Approved non-PII tags.')
param tags object

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: projectDescription
    displayName: displayName
  }
}

output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId
output projectEndpoints object = project.properties.endpoints
