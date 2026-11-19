locals {
  subscription_scope = "/subscriptions/${var.subscription_id}"
  suffix             = substr(sha256(lower("${var.subscription_id}/${var.resource_group_name}")), 0, 8)
  name               = "${var.name_prefix}-${local.suffix}"
  tags = merge(var.tags, {
    workload  = "foundry-backing-stores"
    managedBy = "terraform"
  })
}

data "azapi_resource_list" "locations" {
  type      = "Microsoft.Resources/subscriptions/locations@2022-12-01"
  parent_id = local.subscription_scope
  response_export_values = {
    display_name = "value[?name == '${var.location}'].displayName | [0]"
  }
  lifecycle {
    postcondition {
      condition     = self.output.display_name != null
      error_message = "The selected Azure region was not found in this subscription."
    }
  }
}

resource "azapi_resource" "resource_group" {
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  name      = var.resource_group_name
  parent_id = local.subscription_scope
  location  = var.location
  tags      = local.tags
}

resource "azapi_resource" "storage" {
  type      = "Microsoft.Storage/storageAccounts@2025-01-01"
  name      = "st${var.name_prefix}${local.suffix}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_LRS" }
    properties = {
      accessTier                   = "Hot"
      allowBlobPublicAccess        = false
      allowSharedKeyAccess         = false
      allowCrossTenantReplication  = false
      defaultToOAuthAuthentication = true
      minimumTlsVersion            = "TLS1_2"
      publicNetworkAccess          = "Disabled"
      supportsHttpsTrafficOnly     = true
      networkAcls = {
        bypass              = "AzureServices"
        defaultAction       = "Deny"
        ipRules             = []
        virtualNetworkRules = []
      }
    }
  }
}

resource "azapi_update_resource" "blob_service" {
  type      = "Microsoft.Storage/storageAccounts/blobServices@2025-01-01"
  name      = "default"
  parent_id = azapi_resource.storage.id
  body = {
    properties = {
      isVersioningEnabled            = true
      deleteRetentionPolicy          = { enabled = true, days = 7 }
      containerDeleteRetentionPolicy = { enabled = true, days = 7 }
    }
  }
}

resource "azapi_resource" "cosmos" {
  type      = "Microsoft.DocumentDB/databaseAccounts@2025-04-15"
  name      = "cosmos-${local.name}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    kind = "GlobalDocumentDB"
    properties = {
      databaseAccountOfferType     = "Standard"
      capabilities                 = [{ name = "EnableServerless" }]
      consistencyPolicy            = { defaultConsistencyLevel = "Session" }
      locations                    = [{ locationName = data.azapi_resource_list.locations.output.display_name, failoverPriority = 0, isZoneRedundant = false }]
      disableLocalAuth             = true
      publicNetworkAccess          = "Disabled"
      minimalTlsVersion            = "Tls12"
      enableAutomaticFailover      = false
      enableMultipleWriteLocations = false
      networkAclBypass             = "None"
    }
  }
}

resource "azapi_resource" "search" {
  type      = "Microsoft.Search/searchServices@2025-05-01"
  name      = "srch-${local.name}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    sku = { name = "standard" }
    properties = {
      replicaCount        = 1
      partitionCount      = 1
      hostingMode         = "Default"
      disableLocalAuth    = true
      publicNetworkAccess = "Disabled"
      networkRuleSet      = { bypass = "None", ipRules = [] }
    }
  }
}

output "backing_resources" {
  value = {
    storage = azapi_resource.storage.id
    cosmos  = azapi_resource.cosmos.id
    search  = azapi_resource.search.id
  }
}

output "resource_group_name" {
  value = azapi_resource.resource_group.name
}
