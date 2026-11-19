resource "azapi_resource" "validation_nsg" {
  count     = var.validation_ssh_public_key == null && !var.windows_desktop_enabled ? 0 : 1
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = "nsg-validation-${local.suffix}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      securityRules = concat(var.bastion_subnet_prefix == null || var.validation_ssh_public_key == null ? [] : [{
        name = "AllowSshFromBastion"
        properties = {
          priority                 = 100
          direction                = "Inbound"
          access                   = "Allow"
          protocol                 = "Tcp"
          sourcePortRange          = "*"
          destinationPortRange     = "22"
          sourceAddressPrefix      = var.bastion_subnet_prefix
          destinationAddressPrefix = var.validation_subnet_prefix
        }
        }], var.windows_desktop_enabled ? [{
        name = "AllowRdpFromBastion"
        properties = {
          priority                 = 110
          direction                = "Inbound"
          access                   = "Allow"
          protocol                 = "Tcp"
          sourcePortRange          = "*"
          destinationPortRange     = "3389"
          sourceAddressPrefix      = var.bastion_subnet_prefix
          destinationAddressPrefix = "${cidrhost(var.validation_subnet_prefix, 5)}/32"
        }
        }] : [], [{
        name = "DenyAllInbound"
        properties = {
          priority                 = var.bastion_subnet_prefix == null ? 100 : var.windows_desktop_enabled ? 120 : 110
          direction                = "Inbound"
          access                   = "Deny"
          protocol                 = "*"
          sourcePortRange          = "*"
          destinationPortRange     = "*"
          sourceAddressPrefix      = "*"
          destinationAddressPrefix = "*"
        }
      }])
    }
  }
}

resource "azapi_resource" "validation_subnet" {
  count     = var.validation_ssh_public_key == null && !var.windows_desktop_enabled ? 0 : 1
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "validation"
  parent_id = azapi_resource.vnet.id
  locks     = [azapi_resource.vnet.id]
  body = {
    properties = {
      addressPrefix        = var.validation_subnet_prefix
      networkSecurityGroup = { id = azapi_resource.validation_nsg[0].id }
    }
  }
  depends_on = [azapi_resource.private_endpoint_subnet]
}

resource "azapi_resource" "validation_nic" {
  count     = var.validation_ssh_public_key == null ? 0 : 1
  type      = "Microsoft.Network/networkInterfaces@2024-05-01"
  name      = "nic-validation-${local.suffix}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      ipConfigurations = [{
        name = "private"
        properties = {
          privateIPAllocationMethod = "Dynamic"
          subnet                    = { id = azapi_resource.validation_subnet[0].id }
        }
      }]
    }
  }
}

resource "azapi_resource" "validation_vm" {
  count     = var.validation_ssh_public_key == null ? 0 : 1
  type      = "Microsoft.Compute/virtualMachines@2024-07-01"
  name      = "vm-validation-${local.suffix}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    properties = {
      hardwareProfile = { vmSize = "Standard_B2s" }
      storageProfile = {
        imageReference = {
          publisher = "Canonical"
          offer     = "ubuntu-24_04-lts"
          sku       = "server"
          version   = "latest"
        }
        osDisk = {
          createOption = "FromImage"
          deleteOption = "Delete"
          managedDisk  = { storageAccountType = "Standard_LRS" }
        }
      }
      osProfile = {
        computerName  = "foundry-check"
        adminUsername = "azureuser"
        linuxConfiguration = {
          disablePasswordAuthentication = true
          ssh = {
            publicKeys = [{
              path    = "/home/azureuser/.ssh/authorized_keys"
              keyData = var.validation_ssh_public_key
            }]
          }
        }
      }
      networkProfile = {
        networkInterfaces = [{ id = azapi_resource.validation_nic[0].id, properties = { primary = true } }]
      }
    }
  }
}

resource "azapi_resource" "validation_role" {
  count     = var.validation_ssh_public_key == null ? 0 : 1
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("url", "${azapi_resource.project.id}/${azapi_resource.validation_vm[0].identity[0].principal_id}/foundry-user")
  parent_id = azapi_resource.project.id
  body = {
    properties = {
      principalId      = azapi_resource.validation_vm[0].identity[0].principal_id
      principalType    = "ServicePrincipal"
      roleDefinitionId = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.foundry_user}"
    }
  }
}
