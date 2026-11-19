resource "azapi_resource" "bastion_nsg" {
  count     = var.bastion_subnet_prefix == null ? 0 : 1
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = "nsg-bastion-${local.suffix}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      securityRules = [
        {
          name = "AllowHttpsInbound"
          properties = {
            priority                 = 120
            direction                = "Inbound"
            access                   = "Allow"
            protocol                 = "Tcp"
            sourcePortRange          = "*"
            destinationPortRange     = "443"
            sourceAddressPrefix      = "Internet"
            destinationAddressPrefix = "*"
          }
        },
        {
          name = "AllowGatewayManagerInbound"
          properties = {
            priority                 = 130
            direction                = "Inbound"
            access                   = "Allow"
            protocol                 = "Tcp"
            sourcePortRange          = "*"
            destinationPortRange     = "443"
            sourceAddressPrefix      = "GatewayManager"
            destinationAddressPrefix = "*"
          }
        },
        {
          name = "AllowAzureLoadBalancerInbound"
          properties = {
            priority                 = 140
            direction                = "Inbound"
            access                   = "Allow"
            protocol                 = "Tcp"
            sourcePortRange          = "*"
            destinationPortRange     = "443"
            sourceAddressPrefix      = "AzureLoadBalancer"
            destinationAddressPrefix = "*"
          }
        },
        {
          name = "AllowBastionHostCommunication"
          properties = {
            priority                 = 150
            direction                = "Inbound"
            access                   = "Allow"
            protocol                 = "*"
            sourcePortRange          = "*"
            destinationPortRanges    = ["8080", "5701"]
            sourceAddressPrefix      = "VirtualNetwork"
            destinationAddressPrefix = "VirtualNetwork"
          }
        },
        {
          name = "AllowSshRdpOutbound"
          properties = {
            priority                 = 100
            direction                = "Outbound"
            access                   = "Allow"
            protocol                 = "*"
            sourcePortRange          = "*"
            destinationPortRanges    = ["22", "3389"]
            sourceAddressPrefix      = "*"
            destinationAddressPrefix = "VirtualNetwork"
          }
        },
        {
          name = "AllowAzureCloudOutbound"
          properties = {
            priority                 = 110
            direction                = "Outbound"
            access                   = "Allow"
            protocol                 = "Tcp"
            sourcePortRange          = "*"
            destinationPortRange     = "443"
            sourceAddressPrefix      = "*"
            destinationAddressPrefix = "AzureCloud"
          }
        },
        {
          name = "AllowBastionCommunication"
          properties = {
            priority                 = 120
            direction                = "Outbound"
            access                   = "Allow"
            protocol                 = "*"
            sourcePortRange          = "*"
            destinationPortRanges    = ["8080", "5701"]
            sourceAddressPrefix      = "VirtualNetwork"
            destinationAddressPrefix = "VirtualNetwork"
          }
        },
        {
          name = "AllowHttpOutbound"
          properties = {
            priority                 = 130
            direction                = "Outbound"
            access                   = "Allow"
            protocol                 = "*"
            sourcePortRange          = "*"
            destinationPortRange     = "80"
            sourceAddressPrefix      = "*"
            destinationAddressPrefix = "Internet"
          }
        }
      ]
    }
  }
}

resource "azapi_resource" "bastion_subnet" {
  count     = var.bastion_subnet_prefix == null ? 0 : 1
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "AzureBastionSubnet"
  parent_id = azapi_resource.vnet.id
  locks     = [azapi_resource.vnet.id]
  body = {
    properties = {
      addressPrefix        = var.bastion_subnet_prefix
      networkSecurityGroup = { id = azapi_resource.bastion_nsg[0].id }
    }
  }
  depends_on = [azapi_resource.validation_subnet]
}

resource "azapi_resource" "bastion_public_ip" {
  count     = var.bastion_subnet_prefix == null ? 0 : 1
  type      = "Microsoft.Network/publicIPAddresses@2024-05-01"
  name      = "pip-bastion-${local.suffix}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    sku = { name = "Standard" }
    properties = {
      publicIPAllocationMethod = "Static"
      publicIPAddressVersion   = "IPv4"
    }
  }
}

resource "azapi_resource" "bastion" {
  count     = var.bastion_subnet_prefix == null ? 0 : 1
  type      = "Microsoft.Network/bastionHosts@2024-05-01"
  name      = "bas-validation-${local.suffix}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    sku = { name = var.windows_desktop_enabled ? "Standard" : "Basic" }
    properties = merge(var.windows_desktop_enabled ? { enableTunneling = true } : {}, {
      ipConfigurations = [{
        name = "bastion-ip-configuration"
        properties = {
          privateIPAllocationMethod = "Dynamic"
          subnet                    = { id = azapi_resource.bastion_subnet[0].id }
          publicIPAddress           = { id = azapi_resource.bastion_public_ip[0].id }
        }
      }]
    })
  }
}
