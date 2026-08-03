targetScope = 'resourceGroup'

@description('Environment identifier.')
@allowed([
  'validation'
])
param environmentName string = 'validation'

@description('Azure region for the private validation VM.')
@allowed([
  'northcentralus'
])
param location string = 'northcentralus'

@description('Additional approved non-PII tags. Locked governance tags are applied after this object.')
param tags object = {}

@description('Validation VM size.')
@allowed([
  'Standard_B2s'
])
param validationVmSize string = 'Standard_B2s'

@description('Emergency local administrator username. Microsoft Entra sign-in is the normal access path.')
param validationAdminUsername string = 'validationadmin'

@secure()
@description('Emergency local administrator password. Supply ephemerally at deployment time; never persist or output it.')
param validationAdminPassword string

@minLength(36)
@maxLength(36)
@description('Object ID of the current operator user. Supply ephemerally for VM-scoped login authorization; never persist it.')
param operatorObjectId string

@minLength(4)
@maxLength(4)
@description('Daily local shutdown time in HHmm format.')
param validationVmShutdownTime string = '1900'

@description('Windows time zone used by the daily shutdown schedule.')
@allowed([
  'Central Standard Time'
])
param validationVmShutdownTimeZone string = 'Central Standard Time'

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
var uniqueSuffix = substring(uniqueString(subscription().id, resourceGroup().id), 0, 6)
var vnetName = 'vnet-foundry-permissions-validation-ncus'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetName
}

resource validationSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: 'validation-subnet'
  parent: virtualNetwork
}

module windowsValidationVm './modules/validation/windows-vm.bicep' = {
  name: 'windows-validation-vm-${uniqueSuffix}'
  params: {
    location: location
    operatorObjectId: operatorObjectId
    suffix: uniqueSuffix
    tags: sharedTags
    validationAdminPassword: validationAdminPassword
    validationAdminUsername: validationAdminUsername
    validationSubnetId: validationSubnet.id
    validationVmShutdownTime: validationVmShutdownTime
    validationVmShutdownTimeZone: validationVmShutdownTimeZone
    validationVmSize: validationVmSize
  }
}

output validationVmId string = windowsValidationVm.outputs.validationVmId
output validationVmName string = windowsValidationVm.outputs.validationVmName
output validationNicId string = windowsValidationVm.outputs.validationNicId
output validationShutdownScheduleId string = windowsValidationVm.outputs.validationShutdownScheduleId
