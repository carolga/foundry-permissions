targetScope = 'subscription'

@description('Azure region for the validation resource group.')
@allowed([
  'northcentralus'
])
param location string = 'northcentralus'

@description('Name of the validation resource group.')
@minLength(1)
@maxLength(90)
param resourceGroupName string = 'rg-foundry-permissions-validation'

@description('Environment identifier.')
@allowed([
  'validation'
])
param environmentName string = 'validation'

@description('Additional approved non-PII tags. Locked governance tags are applied after this object.')
param tags object = {}

var requiredTags = union(tags, {
  environment: environmentName
  workload: 'foundry-permissions'
  managedBy: 'bicep'
  region: location
  dataBoundary: 'shared-admin'
  SecurityControl: 'Ignore'
  CostControl: 'Ignore'
})

resource resourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: requiredTags
}

output resourceGroupId string = resourceGroup.id
output deployedResourceGroupName string = resourceGroup.name
