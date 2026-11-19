@description('Microsoft Foundry account name.')
param accountName string

@description('Immutable HOA Entra security-group object ID.')
param hoaGroupObjectId string

@description('Immutable contract Entra security-group object ID.')
param contractGroupObjectId string

@description('Project-specific HOA Azure AI Search service name.')
param hoaSearchServiceName string

@description('Project-specific contract Azure AI Search service name.')
param contractSearchServiceName string

@description('Allow each group to read traces only from its own Application Insights.')
param grantProjectGroupsTraceRead bool = false

param hoaApplicationInsightsName string
param contractApplicationInsightsName string

@description('Pinned built-in Foundry User role definition GUID.')
param foundryUserRoleDefinitionId string

@description('Pinned built-in Reader role definition GUID used only for Foundry portal account navigation compatibility.')
param readerRoleDefinitionId string

@description('Pinned built-in Search Index Data Contributor role definition GUID.')
param searchIndexDataContributorRoleDefinitionId string

@description('Pinned built-in Search Service Contributor role definition GUID.')
param searchServiceContributorRoleDefinitionId string

var foundryUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryUserRoleDefinitionId)
var readerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleDefinitionId)
var searchIndexDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleDefinitionId)
var searchServiceContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleDefinitionId)
var logAnalyticsReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

resource hoaProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: account
  name: 'hoa-project'
}

resource contractProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: account
  name: 'one-to-four-residential-contract-project'
}

resource hoaSearchService 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: hoaSearchServiceName
}

resource contractSearchService 'Microsoft.Search/searchServices@2025-05-01' existing = {
  name: contractSearchServiceName
}

resource hoaApplicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: hoaApplicationInsightsName
}

resource contractApplicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: contractApplicationInsightsName
}

resource hoaTraceReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantProjectGroupsTraceRead) {
  scope: hoaApplicationInsights
  name: guid(hoaApplicationInsights.id, hoaGroupObjectId, logAnalyticsReaderRoleId)
  properties: {
    principalId: hoaGroupObjectId
    principalType: 'Group'
    roleDefinitionId: logAnalyticsReaderRoleId
  }
}

resource contractTraceReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantProjectGroupsTraceRead) {
  scope: contractApplicationInsights
  name: guid(contractApplicationInsights.id, contractGroupObjectId, logAnalyticsReaderRoleId)
  properties: {
    principalId: contractGroupObjectId
    principalType: 'Group'
    roleDefinitionId: logAnalyticsReaderRoleId
  }
}

resource hoaFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: hoaProject
  name: guid(hoaProject.id, hoaGroupObjectId, foundryUserRoleDefinitionId)
  properties: {
    principalId: hoaGroupObjectId
    principalType: 'Group'
    roleDefinitionId: foundryUserRoleId
  }
}

resource contractFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: contractProject
  name: guid(contractProject.id, contractGroupObjectId, foundryUserRoleDefinitionId)
  properties: {
    principalId: contractGroupObjectId
    principalType: 'Group'
    roleDefinitionId: foundryUserRoleId
  }
}

resource hoaAccountReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: account
  name: guid(account.id, hoaGroupObjectId, readerRoleDefinitionId)
  properties: {
    principalId: hoaGroupObjectId
    principalType: 'Group'
    roleDefinitionId: readerRoleId
  }
}

resource contractAccountReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: account
  name: guid(account.id, contractGroupObjectId, readerRoleDefinitionId)
  properties: {
    principalId: contractGroupObjectId
    principalType: 'Group'
    roleDefinitionId: readerRoleId
  }
}

resource hoaSearchIndexDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: hoaSearchService
  name: guid(hoaSearchService.id, hoaGroupObjectId, searchIndexDataContributorRoleDefinitionId)
  properties: {
    principalId: hoaGroupObjectId
    principalType: 'Group'
    roleDefinitionId: searchIndexDataContributorRoleId
  }
}

resource hoaSearchServiceContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: hoaSearchService
  name: guid(hoaSearchService.id, hoaGroupObjectId, searchServiceContributorRoleDefinitionId)
  properties: {
    principalId: hoaGroupObjectId
    principalType: 'Group'
    roleDefinitionId: searchServiceContributorRoleId
  }
}

resource contractSearchIndexDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: contractSearchService
  name: guid(contractSearchService.id, contractGroupObjectId, searchIndexDataContributorRoleDefinitionId)
  properties: {
    principalId: contractGroupObjectId
    principalType: 'Group'
    roleDefinitionId: searchIndexDataContributorRoleId
  }
}

resource contractSearchServiceContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: contractSearchService
  name: guid(contractSearchService.id, contractGroupObjectId, searchServiceContributorRoleDefinitionId)
  properties: {
    principalId: contractGroupObjectId
    principalType: 'Group'
    roleDefinitionId: searchServiceContributorRoleId
  }
}

output hoaFoundryUserRoleAssignmentId string = hoaFoundryUser.id
output contractFoundryUserRoleAssignmentId string = contractFoundryUser.id
output hoaAccountReaderRoleAssignmentId string = hoaAccountReader.id
output contractAccountReaderRoleAssignmentId string = contractAccountReader.id
output hoaSearchIndexDataContributorRoleAssignmentId string = hoaSearchIndexDataContributor.id
output hoaSearchServiceContributorRoleAssignmentId string = hoaSearchServiceContributor.id
output contractSearchIndexDataContributorRoleAssignmentId string = contractSearchIndexDataContributor.id
output contractSearchServiceContributorRoleAssignmentId string = contractSearchServiceContributor.id
