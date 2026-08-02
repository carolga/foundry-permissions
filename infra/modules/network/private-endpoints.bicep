type privateEndpointConfig = {
  name: string
  connectionName: string
  targetResourceId: string
  groupId: string
  dnsZoneIds: string[]
}

@description('Azure region for private endpoints.')
param location string

@description('Resource ID of the private endpoint subnet.')
param privateEndpointSubnetId string

@description('Private endpoint definitions and matching DNS zones.')
param endpoints privateEndpointConfig[]

@description('Approved non-PII tags.')
param tags object

resource privateEndpoints 'Microsoft.Network/privateEndpoints@2024-07-01' = [for endpoint in endpoints: {
  name: endpoint.name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: endpoint.connectionName
        properties: {
          #disable-next-line use-resource-id-functions
          privateLinkServiceId: endpoint.targetResourceId
          groupIds: [
            endpoint.groupId
          ]
        }
      }
    ]
  }
}]

resource dnsZoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = [for (endpoint, i) in endpoints: {
  parent: privateEndpoints[i]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, zoneIndex) in endpoint.dnsZoneIds: {
      name: 'zone-${zoneIndex}'
      properties: {
        #disable-next-line use-resource-id-functions
        privateDnsZoneId: zoneId
      }
    }]
  }
}]

output privateEndpointIds array = [for (endpoint, i) in endpoints: privateEndpoints[i].id]
