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

resource "azapi_resource" "storage" {
  count     = var.existing_storage_account_id == null ? 1 : 0
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
  count     = var.existing_storage_account_id == null ? 1 : 0
  type      = "Microsoft.Storage/storageAccounts/blobServices@2025-01-01"
  name      = "default"
  parent_id = azapi_resource.storage[0].id
  body = {
    properties = {
      isVersioningEnabled            = true
      deleteRetentionPolicy          = { enabled = true, days = 7 }
      containerDeleteRetentionPolicy = { enabled = true, days = 7 }
    }
  }
}

resource "azapi_resource" "search" {
  count     = var.existing_search_service_id == null ? 1 : 0
  type      = "Microsoft.Search/searchServices@2025-05-01"
  name      = "srch-${local.account_name}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    sku = { name = "standard" }
    properties = {
      replicaCount        = var.search_replica_count
      partitionCount      = 1
      hostingMode         = "Default"
      disableLocalAuth    = true
      publicNetworkAccess = "Disabled"
      networkRuleSet      = { bypass = "None", ipRules = [] }
    }
  }
}

resource "azapi_resource" "cosmos" {
  count     = var.existing_cosmos_account_id == null ? 1 : 0
  type      = "Microsoft.DocumentDB/databaseAccounts@2025-04-15"
  name      = "cosmos-${local.account_name}"
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

data "azapi_resource" "existing_storage" {
  count                  = var.existing_storage_account_id == null ? 0 : 1
  type                   = "Microsoft.Storage/storageAccounts@2025-01-01"
  resource_id            = var.existing_storage_account_id
  response_export_values = ["properties.publicNetworkAccess", "properties.primaryEndpoints.blob"]
  lifecycle {
    postcondition {
      condition     = contains([lower(var.location), lower(data.azapi_resource_list.locations.output.display_name)], try(lower(self.location), "")) && try(lower(self.output.properties.publicNetworkAccess), "") == "disabled"
      error_message = "Existing Storage must be in the Foundry region with public network access disabled."
    }
    postcondition {
      condition     = can(regex("^https://[a-z0-9]+\\.blob\\.core\\.windows\\.net/?$", try(self.output.properties.primaryEndpoints.blob, "")))
      error_message = "Existing Storage must expose a standard Azure public-cloud blob endpoint."
    }
  }
}

data "azapi_resource" "existing_cosmos" {
  count                  = var.existing_cosmos_account_id == null ? 0 : 1
  type                   = "Microsoft.DocumentDB/databaseAccounts@2025-04-15"
  resource_id            = var.existing_cosmos_account_id
  response_export_values = ["kind", "properties.publicNetworkAccess", "properties.documentEndpoint", "properties.capabilities", "properties.capacity.totalThroughputLimit"]
  lifecycle {
    postcondition {
      condition     = contains([lower(var.location), lower(data.azapi_resource_list.locations.output.display_name)], try(lower(self.location), "")) && try(lower(self.output.properties.publicNetworkAccess), "") == "disabled"
      error_message = "Existing Cosmos DB must be in the Foundry region with public network access disabled."
    }
    postcondition {
      condition = (
        try(self.output.kind, "") == "GlobalDocumentDB" &&
        length(setintersection(toset(try([for capability in self.output.properties.capabilities : capability.name], [])), toset(["EnableGremlin", "EnableTable", "EnableMongo", "EnableCassandra"]))) == 0 &&
        can(regex("(?i)^https://[a-z0-9-]+\\.documents\\.azure\\.com(:443)?/?$", try(self.output.properties.documentEndpoint, "")))
      )
      error_message = "Existing Cosmos DB must be a NoSQL account with a standard Azure public-cloud endpoint."
    }
    postcondition {
      condition = try(self.output.properties.capacity.totalThroughputLimit, null) == null ? true : (
        self.output.properties.capacity.totalThroughputLimit == -1 ||
        self.output.properties.capacity.totalThroughputLimit >= 3000
      )
      error_message = "An existing Cosmos DB throughput limit must be unlimited or at least 3000 RU/s."
    }
  }
}

data "azapi_resource" "existing_search" {
  count                  = var.existing_search_service_id == null ? 0 : 1
  type                   = "Microsoft.Search/searchServices@2025-05-01"
  resource_id            = var.existing_search_service_id
  response_export_values = ["sku.name", "properties.publicNetworkAccess", "properties.disableLocalAuth", "properties.authOptions"]
  lifecycle {
    postcondition {
      condition     = contains([lower(var.location), lower(data.azapi_resource_list.locations.output.display_name)], try(lower(self.location), "")) && try(lower(self.output.properties.publicNetworkAccess), "") == "disabled"
      error_message = "Existing Search must be in the Foundry region with public network access disabled."
    }
    postcondition {
      condition = (
        try(lower(self.output.sku.name), "") != "" && try(lower(self.output.sku.name), "") != "free" &&
        (try(self.output.properties.disableLocalAuth, false) == true || try(self.output.properties.authOptions.aadOrApiKey, null) != null)
      )
      error_message = "Existing Search must support private endpoints and Microsoft Entra data-plane authentication."
    }
  }
}

locals {
  storage_id = var.existing_storage_account_id == null ? azapi_resource.storage[0].id : data.azapi_resource.existing_storage[0].id
  cosmos_id  = var.existing_cosmos_account_id == null ? azapi_resource.cosmos[0].id : data.azapi_resource.existing_cosmos[0].id
  search_id  = var.existing_search_service_id == null ? azapi_resource.search[0].id : data.azapi_resource.existing_search[0].id

  storage_target = var.existing_storage_account_id == null ? "https://${azapi_resource.storage[0].name}.blob.core.windows.net/" : data.azapi_resource.existing_storage[0].output.properties.primaryEndpoints.blob
  cosmos_target  = var.existing_cosmos_account_id == null ? "https://${azapi_resource.cosmos[0].name}.documents.azure.com:443/" : data.azapi_resource.existing_cosmos[0].output.properties.documentEndpoint
  search_target  = var.existing_search_service_id == null ? "https://${azapi_resource.search[0].name}.search.windows.net" : "https://${element(reverse(split("/", var.existing_search_service_id)), 0)}.search.windows.net"
}

moved {
  from = azapi_resource.storage
  to   = azapi_resource.storage[0]
}

moved {
  from = azapi_update_resource.blob_service
  to   = azapi_update_resource.blob_service[0]
}

moved {
  from = azapi_resource.cosmos
  to   = azapi_resource.cosmos[0]
}

moved {
  from = azapi_resource.search
  to   = azapi_resource.search[0]
}
