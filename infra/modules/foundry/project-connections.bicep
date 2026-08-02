@description('Microsoft Foundry account name.')
param accountName string

@description('Exact project child name.')
param projectName string

@description('Short data-boundary token for deterministic connection names.')
@allowed([
  'hoa'
  'contract'
])
param dataBoundary string

@description('Storage account resource ID.')
param storageAccountId string

@description('Storage Blob endpoint.')
param storageBlobEndpoint string

@description('Azure AI Search resource ID.')
param searchServiceId string

@description('Azure AI Search endpoint.')
param searchEndpoint string

@description('Cosmos DB account resource ID.')
param cosmosAccountId string

@description('Cosmos DB endpoint.')
param cosmosEndpoint string

@description('Project-specific Application Insights resource ID.')
param applicationInsightsId string

@description('Azure region metadata for project connections.')
param location string

var storageConnectionName = 'conn-${dataBoundary}-storage'
var searchConnectionName = 'conn-${dataBoundary}-search'
var cosmosConnectionName = 'conn-${dataBoundary}-cosmos'
var monitoringConnectionName = 'conn-${dataBoundary}-monitoring'

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: account
  name: projectName
}

resource storageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: storageConnectionName
  properties: {
    authType: 'AAD'
    category: 'AzureStorageAccount'
    isSharedToAll: false
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageAccountId
      location: location
    }
    peRequirement: 'Required'
    target: storageBlobEndpoint
    useWorkspaceManagedIdentity: true
  }
}

resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: searchConnectionName
  properties: {
    authType: 'AAD'
    category: 'CognitiveSearch'
    isSharedToAll: false
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchServiceId
      location: location
    }
    peRequirement: 'Required'
    target: searchEndpoint
    useWorkspaceManagedIdentity: true
  }
}

resource cosmosConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: cosmosConnectionName
  properties: {
    authType: 'AAD'
    category: 'CosmosDb'
    isSharedToAll: false
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosAccountId
      location: location
    }
    peRequirement: 'Required'
    target: cosmosEndpoint
    useWorkspaceManagedIdentity: true
  }
}

resource monitoringConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: monitoringConnectionName
  properties: {
    authType: 'ProjectManagedIdentity'
    category: 'AppInsights'
    isSharedToAll: false
    metadata: {
      ApiType: 'Azure'
      ResourceId: applicationInsightsId
      location: location
    }
    peRequirement: 'Required'
    target: applicationInsightsId
    useWorkspaceManagedIdentity: true
  }
}

output connectionNames object = {
  storage: storageConnection.name
  search: searchConnection.name
  cosmos: cosmosConnection.name
  monitoring: monitoringConnection.name
}
output connectionIds array = [
  storageConnection.id
  searchConnection.id
  cosmosConnection.id
  monitoringConnection.id
]
