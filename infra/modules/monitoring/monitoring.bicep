@description('Azure region for project monitoring resources and private endpoint.')
param location string

@description('HOA Log Analytics workspace name.')
param hoaLogAnalyticsName string

@description('Contract Log Analytics workspace name.')
param contractLogAnalyticsName string

@description('HOA Application Insights component name.')
param hoaApplicationInsightsName string

@description('Contract Application Insights component name.')
param contractApplicationInsightsName string

@description('Azure Monitor Private Link Scope name.')
param privateLinkScopeName string

@description('Microsoft Foundry account name for explicit diagnostic settings.')
param foundryAccountName string

@description('HOA project name for explicit diagnostic settings.')
param hoaProjectName string

@description('Contract project name for explicit diagnostic settings.')
param contractProjectName string

@description('Resource ID of the private endpoint subnet.')
param privateEndpointSubnetId string

@description('All five Azure Monitor private DNS zone IDs, including the existing Blob zone.')
@minLength(5)
@maxLength(5)
param monitorDnsZoneIds array

@description('Log retention in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Approved non-PII tags.')
param tags object

resource hoaLogAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: hoaLogAnalyticsName
  location: location
  tags: union(tags, {
    dataBoundary: 'hoa'
  })
  properties: {
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
    retentionInDays: retentionInDays
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource contractLogAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: contractLogAnalyticsName
  location: location
  tags: union(tags, {
    dataBoundary: 'contract'
  })
  properties: {
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
    retentionInDays: retentionInDays
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource hoaApplicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: hoaApplicationInsightsName
  location: location
  tags: union(tags, {
    dataBoundary: 'hoa'
  })
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableLocalAuth: true
    RetentionInDays: retentionInDays
    SamplingPercentage: 100
    WorkspaceResourceId: hoaLogAnalytics.id
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource contractApplicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: contractApplicationInsightsName
  location: location
  tags: union(tags, {
    dataBoundary: 'contract'
  })
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableLocalAuth: true
    RetentionInDays: retentionInDays
    SamplingPercentage: 100
    WorkspaceResourceId: contractLogAnalytics.id
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource hoaProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: hoaProjectName
}

resource contractProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: contractProjectName
}

// Diagnostic settings currently expose only a preview ARM API. Required Ignore tags suppress
// inherited governance deployment, so Bicep explicitly emits all account and project telemetry.
// The shared account is sent symmetrically to both isolated project workspaces.
resource accountHoaDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: foundryAccount
  name: 'account-to-hoa-workspace'
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: hoaLogAnalytics.id
  }
}

resource accountContractDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: foundryAccount
  name: 'account-to-contract-workspace'
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: contractLogAnalytics.id
  }
}

resource hoaProjectDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: hoaProject
  name: 'hoa-project-to-hoa-workspace'
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: hoaLogAnalytics.id
  }
}

resource contractProjectDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: contractProject
  name: 'contract-project-to-contract-workspace'
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: contractLogAnalytics.id
  }
}

resource privateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-09-01' = {
  name: privateLinkScopeName
  location: 'global'
  tags: union(tags, {
    dataBoundary: 'shared-admin'
  })
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

resource hoaAppInsightsScope 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' = {
  parent: privateLinkScope
  name: 'hoa-application-insights'
  properties: {
    linkedResourceId: hoaApplicationInsights.id
  }
}

resource contractAppInsightsScope 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' = {
  parent: privateLinkScope
  name: 'contract-application-insights'
  properties: {
    linkedResourceId: contractApplicationInsights.id
  }
}

resource hoaWorkspaceScope 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' = {
  parent: privateLinkScope
  name: 'hoa-log-analytics'
  properties: {
    linkedResourceId: hoaLogAnalytics.id
  }
}

resource contractWorkspaceScope 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' = {
  parent: privateLinkScope
  name: 'contract-log-analytics'
  properties: {
    linkedResourceId: contractLogAnalytics.id
  }
}

resource monitorPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'pe-${privateLinkScopeName}'
  location: location
  tags: union(tags, {
    dataBoundary: 'shared-admin'
  })
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'azure-monitor'
        properties: {
          privateLinkServiceId: privateLinkScope.id
          groupIds: [
            'azuremonitor'
          ]
        }
      }
    ]
  }
  dependsOn: [
    hoaAppInsightsScope
    contractAppInsightsScope
    hoaWorkspaceScope
    contractWorkspaceScope
  ]
}

resource monitorDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: monitorPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, zoneIndex) in monitorDnsZoneIds: {
      name: 'monitor-zone-${zoneIndex}'
      properties: {
        privateDnsZoneId: zoneId
      }
    }]
  }
}

output hoaApplicationInsightsId string = hoaApplicationInsights.id
output contractApplicationInsightsId string = contractApplicationInsights.id
output hoaLogAnalyticsId string = hoaLogAnalytics.id
output contractLogAnalyticsId string = contractLogAnalytics.id
output privateLinkScopeId string = privateLinkScope.id
output monitorPrivateEndpointId string = monitorPrivateEndpoint.id
