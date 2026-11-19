targetScope = 'resourceGroup'

@description('Microsoft Foundry account name returned by the infrastructure deployment.')
param foundryAccountName string

@description('Immutable object ID for the pre-created hoa-group security group.')
@minLength(36)
@maxLength(36)
param hoaGroupObjectId string

@description('Immutable object ID for the pre-created One-to-Four-Residential-Contract security group.')
@minLength(36)
@maxLength(36)
param contractGroupObjectId string

@description('Project-specific HOA Azure AI Search service name.')
param hoaSearchServiceName string

@description('Project-specific contract Azure AI Search service name.')
param contractSearchServiceName string

@description('Grant each project group Log Analytics Reader on its own Application Insights component. Trace data may contain sensitive content.')
param grantProjectGroupsTraceRead bool = false

var uniqueSuffix = substring(uniqueString(subscription().id, resourceGroup().id), 0, 6)

@description('Pinned built-in Foundry User role definition GUID.')
@minLength(36)
@maxLength(36)
param foundryUserRoleDefinitionId string = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

@description('Pinned built-in Reader role definition GUID used only for Foundry portal account navigation compatibility.')
@minLength(36)
@maxLength(36)
param readerRoleDefinitionId string = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

@description('Pinned built-in Search Index Data Contributor role definition GUID.')
@minLength(36)
@maxLength(36)
param searchIndexDataContributorRoleDefinitionId string = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'

@description('Pinned built-in Search Service Contributor role definition GUID.')
@minLength(36)
@maxLength(36)
param searchServiceContributorRoleDefinitionId string = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'

module projectGroups './modules/access/project-groups.bicep' = {
  name: 'project-group-access'
  params: {
    accountName: foundryAccountName
    contractGroupObjectId: contractGroupObjectId
    contractSearchServiceName: contractSearchServiceName
    foundryUserRoleDefinitionId: foundryUserRoleDefinitionId
    grantProjectGroupsTraceRead: grantProjectGroupsTraceRead
    hoaApplicationInsightsName: 'appi-fp-val-hoa-${uniqueSuffix}'
    contractApplicationInsightsName: 'appi-fp-val-contract-${uniqueSuffix}'
    hoaGroupObjectId: hoaGroupObjectId
    hoaSearchServiceName: hoaSearchServiceName
    readerRoleDefinitionId: readerRoleDefinitionId
    searchIndexDataContributorRoleDefinitionId: searchIndexDataContributorRoleDefinitionId
    searchServiceContributorRoleDefinitionId: searchServiceContributorRoleDefinitionId
  }
}

output hoaFoundryUserRoleAssignmentId string = projectGroups.outputs.hoaFoundryUserRoleAssignmentId
output contractFoundryUserRoleAssignmentId string = projectGroups.outputs.contractFoundryUserRoleAssignmentId
output hoaAccountReaderRoleAssignmentId string = projectGroups.outputs.hoaAccountReaderRoleAssignmentId
output contractAccountReaderRoleAssignmentId string = projectGroups.outputs.contractAccountReaderRoleAssignmentId
output hoaSearchIndexDataContributorRoleAssignmentId string = projectGroups.outputs.hoaSearchIndexDataContributorRoleAssignmentId
output hoaSearchServiceContributorRoleAssignmentId string = projectGroups.outputs.hoaSearchServiceContributorRoleAssignmentId
output contractSearchIndexDataContributorRoleAssignmentId string = projectGroups.outputs.contractSearchIndexDataContributorRoleAssignmentId
output contractSearchServiceContributorRoleAssignmentId string = projectGroups.outputs.contractSearchServiceContributorRoleAssignmentId
