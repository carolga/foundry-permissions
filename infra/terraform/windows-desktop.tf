resource "azapi_resource" "windows_nic" {
  count     = var.windows_desktop_enabled ? 1 : 0
  type      = "Microsoft.Network/networkInterfaces@2024-05-01"
  name      = "nic-windows-${local.suffix}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      ipConfigurations = [{
        name = "private"
        properties = {
          privateIPAllocationMethod = "Static"
          privateIPAddress          = cidrhost(var.validation_subnet_prefix, 5)
          subnet                    = { id = azapi_resource.validation_subnet[0].id }
        }
      }]
    }
  }
  depends_on = [azapi_resource.validation_nic]
}

resource "azapi_resource" "windows_vm" {
  count     = var.windows_desktop_enabled ? 1 : 0
  type      = "Microsoft.Compute/virtualMachines@2024-07-01"
  name      = "vm-windows-${local.suffix}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    properties = {
      hardwareProfile = { vmSize = "Standard_B2ms" }
      securityProfile = {
        securityType = "TrustedLaunch"
        uefiSettings = { secureBootEnabled = true, vTpmEnabled = true }
      }
      storageProfile = {
        imageReference = {
          publisher = "MicrosoftWindowsServer"
          offer     = "WindowsServer"
          sku       = "2025-datacenter-azure-edition"
          version   = "latest"
        }
        osDisk = {
          createOption = "FromImage"
          deleteOption = "Delete"
          managedDisk  = { storageAccountType = "StandardSSD_LRS" }
        }
      }
      osProfile = {
        computerName  = "foundry-desktop"
        adminUsername = "foundryadmin"
        windowsConfiguration = {
          provisionVMAgent       = true
          enableAutomaticUpdates = true
          patchSettings          = { patchMode = "AutomaticByPlatform", assessmentMode = "AutomaticByPlatform" }
        }
      }
      networkProfile = {
        networkInterfaces = [{ id = azapi_resource.windows_nic[0].id, properties = { primary = true } }]
      }
      diagnosticsProfile = { bootDiagnostics = { enabled = true } }
    }
  }
  sensitive_body = {
    properties = { osProfile = { adminPassword = var.windows_admin_password } }
  }
  sensitive_body_version = { "properties.osProfile.adminPassword" = "1" }
}

resource "azapi_resource" "windows_foundry_role" {
  count     = var.windows_desktop_enabled ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("url", "${azapi_resource.project.id}/${azapi_resource.windows_vm[0].identity[0].principal_id}/foundry-user")
  parent_id = azapi_resource.project.id
  body = {
    properties = {
      principalId      = azapi_resource.windows_vm[0].identity[0].principal_id
      principalType    = "ServicePrincipal"
      roleDefinitionId = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.foundry_user}"
    }
  }
}

resource "azapi_resource" "windows_entra_extension" {
  count     = var.windows_entra_login_principal_id == null ? 0 : 1
  type      = "Microsoft.Compute/virtualMachines/extensions@2024-07-01"
  name      = "AADLoginForWindows"
  parent_id = azapi_resource.windows_vm[0].id
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      publisher               = "Microsoft.Azure.ActiveDirectory"
      type                    = "AADLoginForWindows"
      typeHandlerVersion      = "2.2"
      autoUpgradeMinorVersion = true
    }
  }
}

resource "azapi_resource" "windows_entra_role" {
  count     = var.windows_entra_login_principal_id == null ? 0 : 1
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("url", "${azapi_resource.windows_vm[0].id}/${var.windows_entra_login_principal_id}/administrator-login")
  parent_id = azapi_resource.windows_vm[0].id
  body = {
    properties = {
      principalId      = var.windows_entra_login_principal_id
      principalType    = "User"
      roleDefinitionId = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/1c0163c0-47e6-4577-8991-ea5c82e286e4"
    }
  }
}
