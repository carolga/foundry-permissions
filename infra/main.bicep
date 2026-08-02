targetScope = 'resourceGroup'

@description('Environment identifier.')
@allowed([
  'validation'
])
param environmentName string = 'validation'

@description('Azure region for all regional resources.')
@allowed([
  'northcentralus'
])
param location string = 'northcentralus'

@description('Additional approved non-PII tags. Locked governance tags are applied after this object.')
param tags object = {}

@description('Virtual network address prefix.')
param vnetAddressPrefix string = '192.168.0.0/16'

@description('Dedicated Foundry agent subnet prefix.')
param agentSubnetPrefix string = '192.168.0.0/24'

@description('Private endpoint subnet prefix.')
param privateEndpointSubnetPrefix string = '192.168.1.0/24'

@description('Azure Bastion subnet prefix.')
param bastionSubnetPrefix string = '192.168.2.0/26'

@description('Private validation host subnet prefix.')
param validationSubnetPrefix string = '192.168.3.0/27'

@description('Model name selected from current capacity preflight.')
param modelName string

@description('Exact model version selected from current capacity preflight.')
param modelVersion string

@description('Model provider format.')
@allowed([
  'OpenAI'
])
param modelFormat string = 'OpenAI'

@description('Only the policy-approved model deployment SKU is allowed.')
@allowed([
  'GlobalStandard'
])
param modelSkuName string = 'GlobalStandard'

@description('Capacity units for each account-level validation deployment.')
@minValue(1)
param modelCapacity int

@description('Account-level model deployment name used by the HOA project.')
param hoaModelDeploymentName string

@description('Account-level model deployment name used by the contract project.')
param contractModelDeploymentName string

@description('Storage replication SKU for both project data estates.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
])
param storageSkuName string = 'Standard_LRS'

@description('Azure AI Search replica count per project.')
@minValue(1)
@maxValue(12)
param searchReplicaCount int = 1

@description('Azure AI Search partition count per project.')
@allowed([
  1
  2
  3
  4
  6
  12
])
param searchPartitionCount int = 1

@description('Project monitoring retention in days.')
@minValue(30)
@maxValue(730)
param monitoringRetentionInDays int = 30

@description('Validation VM size.')
param validationVmSize string = 'Standard_B2s'

@description('Validation VM administrator username.')
param validationAdminUsername string = 'azureuser'

@description('Non-secret SSH public key. Leave empty to keep the validation VM disabled.')
param validationSshPublicKey string = ''

var requiredTags = union(tags, {
  environment: environmentName
  workload: 'foundry-permissions'
  managedBy: 'bicep'
  region: location
  SecurityControl: 'Ignore'
  CostControl: 'Ignore'
})
var sharedTags = union(requiredTags, {
  dataBoundary: 'shared-admin'
})
var hoaTags = union(requiredTags, {
  dataBoundary: 'hoa'
})
var contractTags = union(requiredTags, {
  dataBoundary: 'contract'
})
var uniqueSuffix = substring(uniqueString(subscription().id, resourceGroup().id), 0, 6)
var foundryAccountName = 'aifpval${uniqueSuffix}'
var vnetName = 'vnet-foundry-permissions-validation-ncus'
var hoaStorageAccountName = 'stfpvalhoa${uniqueSuffix}'
var contractStorageAccountName = 'stfpvalcontract${uniqueSuffix}'
var hoaSearchServiceName = 'srch-fp-val-hoa-${uniqueSuffix}'
var contractSearchServiceName = 'srch-fp-val-contract-${uniqueSuffix}'
var hoaCosmosAccountName = 'cosmos-fp-val-hoa-${uniqueSuffix}'
var contractCosmosAccountName = 'cosmos-fp-val-contract-${uniqueSuffix}'
var hoaLogAnalyticsName = 'law-fp-val-hoa-${uniqueSuffix}'
var contractLogAnalyticsName = 'law-fp-val-contract-${uniqueSuffix}'
var hoaApplicationInsightsName = 'appi-fp-val-hoa-${uniqueSuffix}'
var contractApplicationInsightsName = 'appi-fp-val-contract-${uniqueSuffix}'
var monitorPrivateLinkScopeName = 'ampls-fp-val-${uniqueSuffix}'

module network './modules/network/core-network.bicep' = {
  name: 'network-${uniqueSuffix}'
  params: {
    agentSubnetPrefix: agentSubnetPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    location: location
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    tags: sharedTags
    validationSubnetPrefix: validationSubnetPrefix
    vnetAddressPrefix: vnetAddressPrefix
    vnetName: vnetName
  }
}

module privateDns './modules/network/private-dns.bicep' = {
  name: 'private-dns-${uniqueSuffix}'
  params: {
    tags: sharedTags
    virtualNetworkId: network.outputs.virtualNetworkId
  }
}

module hoaData './modules/data/project-data.bicep' = {
  name: 'hoa-data-${uniqueSuffix}'
  params: {
    cosmosAccountName: hoaCosmosAccountName
    dataBoundary: 'hoa'
    location: location
    searchPartitionCount: searchPartitionCount
    searchReplicaCount: searchReplicaCount
    searchServiceName: hoaSearchServiceName
    storageAccountName: hoaStorageAccountName
    storageSkuName: storageSkuName
    tags: requiredTags
  }
}

module contractData './modules/data/project-data.bicep' = {
  name: 'contract-data-${uniqueSuffix}'
  params: {
    cosmosAccountName: contractCosmosAccountName
    dataBoundary: 'contract'
    location: location
    searchPartitionCount: searchPartitionCount
    searchReplicaCount: searchReplicaCount
    searchServiceName: contractSearchServiceName
    storageAccountName: contractStorageAccountName
    storageSkuName: storageSkuName
    tags: requiredTags
  }
}

module monitoring './modules/monitoring/monitoring.bicep' = {
  name: 'monitoring-${uniqueSuffix}'
  params: {
    contractApplicationInsightsName: contractApplicationInsightsName
    contractLogAnalyticsName: contractLogAnalyticsName
    contractProjectName: 'one-to-four-residential-contract-project'
    foundryAccountName: foundryAccountName
    hoaApplicationInsightsName: hoaApplicationInsightsName
    hoaLogAnalyticsName: hoaLogAnalyticsName
    hoaProjectName: 'hoa-project'
    location: location
    monitorDnsZoneIds: privateDns.outputs.monitorDnsZoneIds
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    privateLinkScopeName: monitorPrivateLinkScopeName
    retentionInDays: monitoringRetentionInDays
    tags: requiredTags
  }
  dependsOn: [
    hoaProject
    contractProject
  ]
}

module foundryAccount './modules/foundry/account.bicep' = {
  name: 'foundry-account-${uniqueSuffix}'
  params: {
    accountName: foundryAccountName
    agentSubnetId: network.outputs.agentSubnetId
    location: location
    tags: sharedTags
  }
}

module modelDeployments './modules/foundry/model-deployments.bicep' = {
  name: 'model-deployments-${uniqueSuffix}'
  params: {
    accountName: foundryAccount.outputs.accountName
    modelDeployments: [
      {
        capacity: modelCapacity
        deploymentName: hoaModelDeploymentName
        modelFormat: modelFormat
        modelName: modelName
        modelVersion: modelVersion
        skuName: modelSkuName
      }
      {
        capacity: modelCapacity
        deploymentName: contractModelDeploymentName
        modelFormat: modelFormat
        modelName: modelName
        modelVersion: modelVersion
        skuName: modelSkuName
      }
    ]
    tags: sharedTags
  }
}

module servicePrivateEndpoints './modules/network/private-endpoints.bicep' = {
  name: 'service-private-endpoints-${uniqueSuffix}'
  params: {
    endpoints: [
      {
        connectionName: 'foundry-account'
        dnsZoneIds: privateDns.outputs.foundryDnsZoneIds
        groupId: 'account'
        name: 'pe-foundry-${uniqueSuffix}'
        targetResourceId: foundryAccount.outputs.accountId
      }
      {
        connectionName: 'hoa-storage-blob'
        dnsZoneIds: [
          privateDns.outputs.storageBlobDnsZoneId
        ]
        groupId: 'blob'
        name: 'pe-storage-hoa-${uniqueSuffix}'
        targetResourceId: hoaData.outputs.storageAccountId
      }
      {
        connectionName: 'contract-storage-blob'
        dnsZoneIds: [
          privateDns.outputs.storageBlobDnsZoneId
        ]
        groupId: 'blob'
        name: 'pe-storage-contract-${uniqueSuffix}'
        targetResourceId: contractData.outputs.storageAccountId
      }
      {
        connectionName: 'hoa-search'
        dnsZoneIds: [
          privateDns.outputs.searchDnsZoneId
        ]
        groupId: 'searchService'
        name: 'pe-search-hoa-${uniqueSuffix}'
        targetResourceId: hoaData.outputs.searchServiceId
      }
      {
        connectionName: 'contract-search'
        dnsZoneIds: [
          privateDns.outputs.searchDnsZoneId
        ]
        groupId: 'searchService'
        name: 'pe-search-contract-${uniqueSuffix}'
        targetResourceId: contractData.outputs.searchServiceId
      }
      {
        connectionName: 'hoa-cosmos-sql'
        dnsZoneIds: [
          privateDns.outputs.cosmosDnsZoneId
        ]
        groupId: 'Sql'
        name: 'pe-cosmos-hoa-${uniqueSuffix}'
        targetResourceId: hoaData.outputs.cosmosAccountId
      }
      {
        connectionName: 'contract-cosmos-sql'
        dnsZoneIds: [
          privateDns.outputs.cosmosDnsZoneId
        ]
        groupId: 'Sql'
        name: 'pe-cosmos-contract-${uniqueSuffix}'
        targetResourceId: contractData.outputs.cosmosAccountId
      }
    ]
    location: location
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    tags: sharedTags
  }
}

module hoaProject './modules/foundry/project.bicep' = {
  name: 'hoa-project-${uniqueSuffix}'
  params: {
    accountName: foundryAccount.outputs.accountName
    projectDescription: 'HOA document extraction and quality-control validation project.'
    displayName: 'HOA Project'
    location: location
    projectName: 'hoa-project'
    tags: hoaTags
  }
}

module contractProject './modules/foundry/project.bicep' = {
  name: 'contract-project-${uniqueSuffix}'
  params: {
    accountName: foundryAccount.outputs.accountName
    projectDescription: 'One-to-four residential contract extraction and quality-control validation project.'
    displayName: 'One-to-Four Residential Contract Project'
    location: location
    projectName: 'one-to-four-residential-contract-project'
    tags: contractTags
  }
}

module hoaConnections './modules/foundry/project-connections.bicep' = {
  name: 'hoa-connections-${uniqueSuffix}'
  params: {
    accountName: foundryAccount.outputs.accountName
    applicationInsightsId: monitoring.outputs.hoaApplicationInsightsId
    cosmosAccountId: hoaData.outputs.cosmosAccountId
    cosmosEndpoint: hoaData.outputs.cosmosEndpoint
    dataBoundary: 'hoa'
    location: location
    projectName: hoaProject.outputs.projectName
    searchEndpoint: hoaData.outputs.searchEndpoint
    searchServiceId: hoaData.outputs.searchServiceId
    storageAccountId: hoaData.outputs.storageAccountId
    storageBlobEndpoint: hoaData.outputs.storageBlobEndpoint
  }
}

module contractConnections './modules/foundry/project-connections.bicep' = {
  name: 'contract-connections-${uniqueSuffix}'
  params: {
    accountName: foundryAccount.outputs.accountName
    applicationInsightsId: monitoring.outputs.contractApplicationInsightsId
    cosmosAccountId: contractData.outputs.cosmosAccountId
    cosmosEndpoint: contractData.outputs.cosmosEndpoint
    dataBoundary: 'contract'
    location: location
    projectName: contractProject.outputs.projectName
    searchEndpoint: contractData.outputs.searchEndpoint
    searchServiceId: contractData.outputs.searchServiceId
    storageAccountId: contractData.outputs.storageAccountId
    storageBlobEndpoint: contractData.outputs.storageBlobEndpoint
  }
}

module hoaManagedIdentityAccess './modules/access/project-managed-identity.bicep' = {
  name: 'hoa-managed-identity-access-${uniqueSuffix}'
  params: {
    applicationInsightsName: hoaApplicationInsightsName
    cosmosAccountName: hoaData.outputs.cosmosAccountName
    projectPrincipalId: hoaProject.outputs.projectPrincipalId
    searchServiceName: hoaData.outputs.searchServiceName
    storageAccountName: hoaData.outputs.storageAccountName
  }
}

module contractManagedIdentityAccess './modules/access/project-managed-identity.bicep' = {
  name: 'contract-managed-identity-access-${uniqueSuffix}'
  params: {
    applicationInsightsName: contractApplicationInsightsName
    cosmosAccountName: contractData.outputs.cosmosAccountName
    projectPrincipalId: contractProject.outputs.projectPrincipalId
    searchServiceName: contractData.outputs.searchServiceName
    storageAccountName: contractData.outputs.storageAccountName
  }
}

module hoaCapabilityHost './modules/foundry/project-capability-host.bicep' = {
  name: 'hoa-capability-host-${uniqueSuffix}'
  params: {
    accountName: foundryAccount.outputs.accountName
    capabilityHostName: 'agents'
    cosmosConnectionName: hoaConnections.outputs.connectionNames.cosmos
    projectName: hoaProject.outputs.projectName
    searchConnectionName: hoaConnections.outputs.connectionNames.search
    storageConnectionName: hoaConnections.outputs.connectionNames.storage
    tags: hoaTags
  }
  dependsOn: [
    hoaManagedIdentityAccess
    servicePrivateEndpoints
  ]
}

module contractCapabilityHost './modules/foundry/project-capability-host.bicep' = {
  name: 'contract-capability-host-${uniqueSuffix}'
  params: {
    accountName: foundryAccount.outputs.accountName
    capabilityHostName: 'agents'
    cosmosConnectionName: contractConnections.outputs.connectionNames.cosmos
    projectName: contractProject.outputs.projectName
    searchConnectionName: contractConnections.outputs.connectionNames.search
    storageConnectionName: contractConnections.outputs.connectionNames.storage
    tags: contractTags
  }
  dependsOn: [
    contractManagedIdentityAccess
    servicePrivateEndpoints
  ]
}

module validationAccess './modules/validation/bastion-host.bicep' = {
  name: 'validation-access-${uniqueSuffix}'
  params: {
    bastionSubnetId: network.outputs.bastionSubnetId
    location: location
    suffix: uniqueSuffix
    tags: sharedTags
    validationAdminUsername: validationAdminUsername
    validationSshPublicKey: validationSshPublicKey
    validationSubnetId: network.outputs.validationSubnetId
    validationVmSize: validationVmSize
  }
}

output foundryAccountId string = foundryAccount.outputs.accountId
output foundryAccountName string = foundryAccount.outputs.accountName
output foundryAccountPrincipalId string = foundryAccount.outputs.accountPrincipalId
output modelDeploymentIds array = modelDeployments.outputs.modelDeploymentIds
output hoaProjectId string = hoaProject.outputs.projectId
output contractProjectId string = contractProject.outputs.projectId
output hoaProjectPrincipalId string = hoaProject.outputs.projectPrincipalId
output contractProjectPrincipalId string = contractProject.outputs.projectPrincipalId
output hoaProjectEndpoints object = hoaProject.outputs.projectEndpoints
output contractProjectEndpoints object = contractProject.outputs.projectEndpoints
output hoaDataResourceIds object = {
  storage: hoaData.outputs.storageAccountId
  search: hoaData.outputs.searchServiceId
  cosmos: hoaData.outputs.cosmosAccountId
  applicationInsights: monitoring.outputs.hoaApplicationInsightsId
  logAnalytics: monitoring.outputs.hoaLogAnalyticsId
}
output contractDataResourceIds object = {
  storage: contractData.outputs.storageAccountId
  search: contractData.outputs.searchServiceId
  cosmos: contractData.outputs.cosmosAccountId
  applicationInsights: monitoring.outputs.contractApplicationInsightsId
  logAnalytics: monitoring.outputs.contractLogAnalyticsId
}
output hoaConnectionIds array = hoaConnections.outputs.connectionIds
output contractConnectionIds array = contractConnections.outputs.connectionIds
output hoaCapabilityHostId string = hoaCapabilityHost.outputs.capabilityHostId
output contractCapabilityHostId string = contractCapabilityHost.outputs.capabilityHostId
output servicePrivateEndpointIds array = servicePrivateEndpoints.outputs.privateEndpointIds
output monitorPrivateEndpointId string = monitoring.outputs.monitorPrivateEndpointId
output privateDnsZoneIds array = privateDns.outputs.allPrivateDnsZoneIds
output virtualNetworkId string = network.outputs.virtualNetworkId
output agentSubnetId string = network.outputs.agentSubnetId
output bastionHostId string = validationAccess.outputs.bastionHostId
output validationVmId string = validationAccess.outputs.validationVmId
output validationVmDeployed bool = validationAccess.outputs.validationVmDeployed
