type modelDeploymentConfig = {
  deploymentName: string
  modelName: string
  modelFormat: string
  modelVersion: string
  skuName: string
  capacity: int
}

@description('Microsoft Foundry account name.')
param accountName string

@description('Account-level model deployments.')
param modelDeployments modelDeploymentConfig[]

@description('Approved non-PII tags.')
param tags object

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

@batchSize(1)
resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = [for deployment in modelDeployments: {
  parent: account
  name: deployment.deploymentName
  tags: tags
  sku: {
    name: deployment.skuName
    capacity: deployment.capacity
  }
  properties: {
    model: {
      format: deployment.modelFormat
      name: deployment.modelName
      version: deployment.modelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}]

output modelDeploymentIds array = [for (deployment, i) in modelDeployments: deployments[i].id]
