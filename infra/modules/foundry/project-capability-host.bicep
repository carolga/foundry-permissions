@description('Microsoft Foundry account name.')
param accountName string

@description('Exact project child name.')
param projectName string

@description('Project capability host name.')
param capabilityHostName string = 'agents'

@description('Project Storage connection name.')
param storageConnectionName string

@description('Project Search connection name.')
param searchConnectionName string

@description('Project Cosmos DB connection name.')
param cosmosConnectionName string

@description('Approved non-PII tags.')
param tags object

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: account
  name: projectName
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-06-01' = {
  parent: project
  name: capabilityHostName
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    #disable-next-line BCP037
    tags: tags
    storageConnections: [
      storageConnectionName
    ]
    threadStorageConnections: [
      cosmosConnectionName
    ]
    vectorStoreConnections: [
      searchConnectionName
    ]
  }
}

output capabilityHostId string = projectCapabilityHost.id
output deployedCapabilityHostName string = projectCapabilityHost.name
