@description('Azure region for project data resources.')
param location string

@description('Project data-boundary identifier.')
@allowed([
  'hoa'
  'contract'
])
param dataBoundary string

@description('Globally unique Storage account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Storage replication SKU.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
])
param storageSkuName string = 'Standard_LRS'

@description('Globally unique Azure AI Search service name.')
@minLength(2)
@maxLength(60)
param searchServiceName string

@description('Azure AI Search SKU.')
@allowed([
  'standard'
])
param searchSkuName string = 'standard'

@description('Azure AI Search replica count.')
@minValue(1)
@maxValue(12)
param searchReplicaCount int = 1

@description('Azure AI Search partition count.')
@allowed([
  1
  2
  3
  4
  6
  12
])
param searchPartitionCount int = 1

@description('Globally unique Cosmos DB account name.')
@minLength(3)
@maxLength(44)
param cosmosAccountName string

@description('Approved non-PII tags.')
param tags object

var projectTags = union(tags, {
  dataBoundary: dataBoundary
})

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: projectTags
  kind: 'StorageV2'
  sku: {
    name: storageSkuName
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    isHnsEnabled: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: true
      retentionInDays: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    isVersioningEnabled: true
  }
}

resource defenderForStorageOptOut 'Microsoft.Security/defenderForStorageSettings@2025-06-01' = {
  name: 'current'
  scope: storageAccount
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
}

resource searchService 'Microsoft.Search/searchServices@2025-05-01' = {
  name: searchServiceName
  location: location
  tags: projectTags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: searchSkuName
  }
  properties: {
    disableLocalAuth: true
    hostingMode: 'Default'
    networkRuleSet: {
      bypass: 'None'
      ipRules: []
    }
    partitionCount: searchPartitionCount
    publicNetworkAccess: 'disabled'
    replicaCount: searchReplicaCount
    semanticSearch: 'disabled'
  }
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2025-04-15' = {
  name: cosmosAccountName
  location: location
  tags: projectTags
  kind: 'GlobalDocumentDB'
  properties: {
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    databaseAccountOfferType: 'Standard'
    disableLocalAuth: true
    enableAutomaticFailover: false
    enableFreeTier: false
    enableMultipleWriteLocations: false
    ipRules: []
    locations: [
      {
        failoverPriority: 0
        isZoneRedundant: false
        locationName: location
      }
    ]
    minimalTlsVersion: 'Tls12'
    networkAclBypass: 'None'
    networkAclBypassResourceIds: []
    publicNetworkAccess: 'Disabled'
    virtualNetworkRules: []
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output storageBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output searchServiceId string = searchService.id
output searchServiceName string = searchService.name
output searchEndpoint string = searchService.properties.endpoint
output cosmosAccountId string = cosmosAccount.id
output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
