@description('Azure region for Bastion.')
param location string

@description('Deterministic suffix used in resource names.')
param suffix string

@description('Resource ID of AzureBastionSubnet.')
param bastionSubnetId string

@description('Approved non-PII tags.')
param tags object

var bastionPublicIpName = 'pip-bastion-${suffix}'
var bastionName = 'bas-validation-${suffix}'

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

output bastionHostId string = bastionHost.id
output bastionPublicIpId string = bastionPublicIp.id
