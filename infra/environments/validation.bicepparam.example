using '../main.bicep'

param environmentName = 'validation'
param location = 'northcentralus'

// Current capacity-driven validation candidate. Recheck catalog and quota before deployment.
param modelName = 'gpt-5.4-mini'
param modelVersion = '2026-03-17'
param modelFormat = 'OpenAI'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 10
param hoaModelDeploymentName = 'hoa-gpt-5-4-mini'
param contractModelDeploymentName = 'contract-gpt-5-4-mini'

param vnetAddressPrefix = '192.168.0.0/16'
param agentSubnetPrefix = '192.168.0.0/24'
param privateEndpointSubnetPrefix = '192.168.1.0/24'
param bastionSubnetPrefix = '192.168.2.0/26'
param validationSubnetPrefix = '192.168.3.0/27'

param storageSkuName = 'Standard_LRS'
param searchReplicaCount = 1
param searchPartitionCount = 1
param monitoringRetentionInDays = 30

param tags = {
  // These locked values are also enforced by the entry point and cannot be overridden.
  SecurityControl: 'Ignore'
  CostControl: 'Ignore'
  criticality: 'validation'
}
