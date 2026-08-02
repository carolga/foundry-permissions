@description('Globally unique Microsoft Foundry account name.')
@minLength(2)
@maxLength(64)
param accountName string

@description('Azure region for Microsoft Foundry.')
param location string

@description('Resource ID of the dedicated delegated agent subnet.')
param agentSubnetId string

@description('Approved non-PII tags.')
param tags object

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
        useMicrosoftManagedNetwork: false
      }
    ]
    publicNetworkAccess: 'Disabled'
  }
}

output accountId string = account.id
output accountName string = account.name
output accountEndpoint string = account.properties.endpoint
output accountPrincipalId string = account.identity.principalId

