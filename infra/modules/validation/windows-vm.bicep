@description('Azure region for the private validation VM.')
param location string

@description('Deterministic suffix used in resource names.')
param suffix string

@description('Resource ID of the private validation subnet.')
param validationSubnetId string

@description('Validation VM size.')
@allowed([
  'Standard_B2s'
])
param validationVmSize string

@description('Emergency local administrator username.')
param validationAdminUsername string

@secure()
@description('Emergency local administrator password.')
param validationAdminPassword string

@minLength(36)
@maxLength(36)
@description('Object ID of the operator user receiving VM-scoped administrator login.')
param operatorObjectId string

@minLength(4)
@maxLength(4)
@description('Daily local shutdown time in HHmm format.')
param validationVmShutdownTime string

@description('Windows time zone used by the daily shutdown schedule.')
param validationVmShutdownTimeZone string

@description('Approved non-PII tags.')
param tags object

var validationNicName = 'nic-validation-${suffix}'
var validationVmName = 'vm-validation-${suffix}'
var validationComputerName = 'fpval${suffix}'
var validationOsDiskName = 'osdisk-validation-${suffix}'
var vmAdministratorLoginRoleGuid = '1c0163c0-47e6-4577-8991-ea5c82e286e4'
var vmAdministratorLoginRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  vmAdministratorLoginRoleGuid
)

resource validationNic 'Microsoft.Network/networkInterfaces@2024-07-01' = {
  name: validationNicName
  location: location
  tags: tags
  properties: {
    enableAcceleratedNetworking: false
    enableIPForwarding: false
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          primary: true
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: validationSubnetId
          }
        }
      }
    ]
  }
}

resource validationVm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: validationVmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    hardwareProfile: {
      vmSize: validationVmSize
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: validationNic.id
          properties: {
            deleteOption: 'Delete'
            primary: true
          }
        }
      ]
    }
    osProfile: {
      adminPassword: validationAdminPassword
      adminUsername: validationAdminUsername
      allowExtensionOperations: true
      computerName: validationComputerName
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: {
          assessmentMode: 'ImageDefault'
          patchMode: 'AutomaticByOS'
        }
        provisionVMAgent: true
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      dataDisks: []
      imageReference: {
        offer: 'WindowsServer'
        publisher: 'MicrosoftWindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        caching: 'ReadWrite'
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        name: validationOsDiskName
        osType: 'Windows'
      }
    }
  }
}

resource validationOsDisk 'Microsoft.Compute/disks@2024-03-02' existing = {
  name: validationOsDiskName
}

resource validationOsDiskTags 'Microsoft.Resources/tags@2023-07-01' = {
  name: 'default'
  scope: validationOsDisk
  properties: {
    tags: tags
  }
  dependsOn: [
    validationVm
  ]
}

resource entraLoginExtension 'Microsoft.Compute/virtualMachines/extensions@2024-11-01' = {
  name: 'AADLoginForWindows'
  parent: validationVm
  location: location
  tags: tags
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADLoginForWindows'
    typeHandlerVersion: '2.2'
  }
}

resource operatorVmAdministratorLogin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(validationVm.id, operatorObjectId, vmAdministratorLoginRoleGuid)
  scope: validationVm
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: vmAdministratorLoginRoleId
  }
}

resource validationVmShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${validationVmName}'
  location: location
  tags: tags
  properties: {
    dailyRecurrence: {
      time: validationVmShutdownTime
    }
    notificationSettings: {
      emailRecipient: ''
      status: 'Disabled'
      timeInMinutes: 30
      webhookUrl: ''
    }
    status: 'Enabled'
    targetResourceId: validationVm.id
    taskType: 'ComputeVmShutdownTask'
    timeZoneId: validationVmShutdownTimeZone
  }
}

output validationVmId string = validationVm.id
output validationVmName string = validationVm.name
output validationNicId string = validationNic.id
output validationShutdownScheduleId string = validationVmShutdown.id
