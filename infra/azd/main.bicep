targetScope = 'subscription'

@description('Environment identifier used for tags and resource-group naming.')
param environmentName string = 'validation'

@description('Azure region for the validation environment.')
@allowed([
  'northcentralus'
])
param location string = 'northcentralus'

@description('Name of the resource group to create and deploy into.')
param resourceGroupName string

@description('Immutable object ID for the pre-created hoa-group security group.')
@minLength(36)
@maxLength(36)
param hoaGroupObjectId string

@description('Immutable object ID for the pre-created One-to-Four-Residential-Contract security group.')
@minLength(36)
@maxLength(36)
param contractGroupObjectId string

@description('Emergency local administrator username. Microsoft Entra sign-in is the normal access path.')
param validationAdminUsername string = 'validationadmin'

@secure()
@description('Emergency local administrator password for the private validation VM. Supply through azd environment variables; never commit it.')
param validationAdminPassword string

@minLength(36)
@maxLength(36)
@description('Object ID of the operator user who can sign in to the validation VM through Bastion.')
param operatorObjectId string

@description('Model name selected from current capacity preflight.')
param modelName string = 'gpt-5.4-mini'

@description('Exact model version selected from current capacity preflight.')
param modelVersion string = '2026-03-17'

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
param modelCapacity int = 10

@description('Account-level model deployment name used by the HOA project.')
param hoaModelDeploymentName string = 'hoa-gpt-5-4-mini'

@description('Account-level model deployment name used by the contract project.')
param contractModelDeploymentName string = 'contract-gpt-5-4-mini'

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

@description('Grant each project group permission to read its own Application Insights traces. Traces may contain sensitive data.')
param grantProjectGroupsTraceRead bool = false

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

@description('Additional approved non-PII tags. Locked governance tags are applied by child entry points.')
param tags object = {}

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: union(tags, {
    environment: environmentName
    workload: 'foundry-permissions'
    managedBy: 'azd-bicep'
    region: location
    dataBoundary: 'shared-admin'
    SecurityControl: 'Ignore'
    CostControl: 'Ignore'
  })
}

var uniqueSuffix = substring(uniqueString(subscription().id, rg.id), 0, 6)
var foundryAccountName = 'aifpval${uniqueSuffix}'
var hoaSearchServiceName = 'srch-fp-val-hoa-${uniqueSuffix}'
var contractSearchServiceName = 'srch-fp-val-contract-${uniqueSuffix}'

module infrastructure '../main.bicep' = {
  name: 'azd-foundry-infrastructure-${uniqueSuffix}'
  scope: rg
  params: {
    agentSubnetPrefix: agentSubnetPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    contractModelDeploymentName: contractModelDeploymentName
    environmentName: environmentName
    hoaModelDeploymentName: hoaModelDeploymentName
    location: location
    modelCapacity: modelCapacity
    modelFormat: modelFormat
    modelName: modelName
    modelSkuName: modelSkuName
    modelVersion: modelVersion
    monitoringRetentionInDays: monitoringRetentionInDays
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    searchPartitionCount: searchPartitionCount
    searchReplicaCount: searchReplicaCount
    storageSkuName: storageSkuName
    tags: tags
    validationSubnetPrefix: validationSubnetPrefix
    vnetAddressPrefix: vnetAddressPrefix
  }
}

module access '../access.bicep' = {
  name: 'azd-foundry-access-${uniqueSuffix}'
  scope: rg
  params: {
    contractGroupObjectId: contractGroupObjectId
    contractSearchServiceName: contractSearchServiceName
    foundryAccountName: foundryAccountName
    grantProjectGroupsTraceRead: grantProjectGroupsTraceRead
    hoaGroupObjectId: hoaGroupObjectId
    hoaSearchServiceName: hoaSearchServiceName
  }
  dependsOn: [
    infrastructure
  ]
}

module validationVm '../validation-vm.bicep' = {
  name: 'azd-validation-vm-${uniqueSuffix}'
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    operatorObjectId: operatorObjectId
    tags: tags
    validationAdminPassword: validationAdminPassword
    validationAdminUsername: validationAdminUsername
  }
  dependsOn: [
    infrastructure
  ]
}

output AZURE_RESOURCE_GROUP string = rg.name
output FOUNDRY_ACCOUNT_NAME string = foundryAccountName
output HOA_PROJECT_ENDPOINT string = infrastructure.outputs.hoaProjectEndpoints.projectEndpoint
output CONTRACT_PROJECT_ENDPOINT string = infrastructure.outputs.contractProjectEndpoints.projectEndpoint
output VALIDATION_VM_NAME string = validationVm.outputs.validationVmName
output BASTION_HOST_ID string = infrastructure.outputs.bastionHostId
