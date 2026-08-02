@description('Azure region for Bastion and the optional validation VM.')
param location string

@description('Deterministic suffix used in resource names.')
param suffix string

@description('Resource ID of AzureBastionSubnet.')
param bastionSubnetId string

@description('Resource ID of the private validation subnet.')
param validationSubnetId string

@description('Validation VM size.')
param validationVmSize string = 'Standard_B2s'

@description('Validation VM administrator username.')
param validationAdminUsername string = 'azureuser'

@description('Non-secret SSH public key. Leave empty to omit the validation VM and NIC.')
param validationSshPublicKey string = ''

@description('Approved non-PII tags.')
param tags object

var deployValidationVm = !empty(validationSshPublicKey)
var bastionPublicIpName = 'pip-bastion-${suffix}'
var bastionName = 'bas-validation-${suffix}'
var validationNicName = 'nic-validation-${suffix}'
var validationVmName = 'vm-validation-${suffix}'

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: bastionPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2024-07-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    enableFileCopy: false
    enableIpConnect: true
    enableShareableLink: false
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'bastion-ip-configuration'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: bastionPublicIp.id
          }
          subnet: {
            id: bastionSubnetId
          }
        }
      }
    ]
    scaleUnits: 2
  }
}

resource validationNic 'Microsoft.Network/networkInterfaces@2024-07-01' = if (deployValidationVm) {
  name: validationNicName
  location: location
  tags: tags
  properties: {
    enableAcceleratedNetworking: false
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: validationSubnetId
          }
        }
      }
    ]
  }
}

resource validationVm 'Microsoft.Compute/virtualMachines@2024-11-01' = if (deployValidationVm) {
  name: validationVmName
  location: location
  tags: tags
  zones: []
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
      adminUsername: validationAdminUsername
      computerName: validationVmName
      linuxConfiguration: {
        disablePasswordAuthentication: true
        patchSettings: {
          assessmentMode: 'ImageDefault'
          patchMode: 'ImageDefault'
        }
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              keyData: validationSshPublicKey
              path: '/home/${validationAdminUsername}/.ssh/authorized_keys'
            }
          ]
        }
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
      imageReference: {
        offer: '0001-com-ubuntu-server-jammy'
        publisher: 'Canonical'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        caching: 'ReadWrite'
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
  }
}

output bastionHostId string = bastionHost.id
output bastionPublicIpId string = bastionPublicIp.id
output validationVmId string = deployValidationVm ? validationVm.id : ''
output validationVmDeployed bool = deployValidationVm

