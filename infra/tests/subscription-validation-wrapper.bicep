targetScope = 'subscription'

@description('Azure region for the validation resource group and regional resources.')
@allowed([
  'northcentralus'
])
param location string = 'northcentralus'

@description('Name of the absent validation resource group evaluated by validate and what-if.')
param resourceGroupName string = 'rg-foundry-permissions-validation'

@description('Additional approved non-PII tags. Locked governance tags are applied after this object.')
param tags object = {
  criticality: 'validation'
}

var requiredTags = union(tags, {
  environment: 'validation'
  workload: 'foundry-permissions'
  managedBy: 'bicep'
  region: location
  dataBoundary: 'shared-admin'
  SecurityControl: 'Ignore'
  CostControl: 'Ignore'
})

resource validationResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: requiredTags
}

module infrastructure '../main.bicep' = {
  name: 'validate-foundry-permissions-infrastructure'
  scope: validationResourceGroup
  params: {
    contractModelDeploymentName: 'contract-gpt-5-4-mini'
    environmentName: 'validation'
    hoaModelDeploymentName: 'hoa-gpt-5-4-mini'
    location: location
    modelCapacity: 10
    modelFormat: 'OpenAI'
    modelName: 'gpt-5.4-mini'
    modelSkuName: 'GlobalStandard'
    modelVersion: '2026-03-17'
    tags: requiredTags
  }
}
