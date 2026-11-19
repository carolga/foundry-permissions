mock_provider "azapi" {}

override_data {
  target = data.azapi_resource_list.locations
  values = {
    output = { display_name = "West US 3" }
  }
}

override_data {
  target          = data.azapi_resource.existing_storage[0]
  override_during = plan
  values = {
    id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared/providers/Microsoft.Storage/storageAccounts/existingstorage"
    location = "West US 3"
    output = {
      properties = {
        publicNetworkAccess = "Disabled"
        primaryEndpoints    = { blob = "https://existingstorage.blob.core.windows.net/" }
      }
    }
  }
}

override_data {
  target          = data.azapi_resource.existing_cosmos[0]
  override_during = plan
  values = {
    id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared/providers/Microsoft.DocumentDB/databaseAccounts/existing-cosmos"
    location = "West US 3"
    output = {
      kind = "GlobalDocumentDB"
      properties = {
        publicNetworkAccess = "Disabled"
        documentEndpoint    = "https://existing-cosmos.documents.azure.com:443/"
        capabilities        = []
      }
    }
  }
}

override_data {
  target          = data.azapi_resource.existing_search[0]
  override_during = plan
  values = {
    id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared/providers/Microsoft.Search/searchServices/existing-search"
    location = "westus3"
    output = {
      sku = { name = "standard" }
      properties = {
        publicNetworkAccess = "Disabled"
        disableLocalAuth    = true
      }
    }
  }
}

variables {
  subscription_id             = "00000000-0000-0000-0000-000000000001"
  existing_storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared/providers/Microsoft.Storage/storageAccounts/existingstorage"
  existing_cosmos_account_id  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared/providers/Microsoft.DocumentDB/databaseAccounts/existing-cosmos"
  existing_search_service_id  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared/providers/Microsoft.Search/searchServices/existing-search"
  model                       = null
  validation_ssh_public_key   = null
}

run "existing_stores_with_capability_host" {
  command = plan

  assert {
    condition     = length(azapi_resource.storage) == 0 && length(azapi_resource.cosmos) == 0 && length(azapi_resource.search) == 0 && length(azapi_update_resource.blob_service) == 0
    error_message = "Existing stores and their blob-service settings must not be managed."
  }
  assert {
    condition     = azapi_resource.connection["storage"].body.properties.metadata.ResourceId == var.existing_storage_account_id && azapi_resource.connection["cosmos"].body.properties.metadata.ResourceId == var.existing_cosmos_account_id && azapi_resource.connection["search"].body.properties.metadata.ResourceId == var.existing_search_service_id
    error_message = "Project connections must point to all three existing resources."
  }
  assert {
    condition = (
      azapi_resource.private_endpoint["storage"].body.properties.privateLinkServiceConnections[0].properties.privateLinkServiceId == var.existing_storage_account_id &&
      azapi_resource.private_endpoint["cosmos"].body.properties.privateLinkServiceConnections[0].properties.privateLinkServiceId == var.existing_cosmos_account_id &&
      azapi_resource.private_endpoint["search"].body.properties.privateLinkServiceConnections[0].properties.privateLinkServiceId == var.existing_search_service_id &&
      azapi_resource.project_role["storage_management"].parent_id == var.existing_storage_account_id &&
      azapi_resource.project_role["cosmos_management"].parent_id == var.existing_cosmos_account_id &&
      azapi_resource.project_role["search_management"].parent_id == var.existing_search_service_id &&
      azapi_resource.cosmos_data_role.parent_id == var.existing_cosmos_account_id
    )
    error_message = "Private endpoints and project roles must target the three existing services."
  }
}

run "reject_wrong_subscription" {
  command = plan
  variables {
    existing_search_service_id = "/subscriptions/00000000-0000-0000-0000-000000000099/resourceGroups/shared/providers/Microsoft.Search/searchServices/existing-search"
  }
  expect_failures = [var.existing_search_service_id]
}

run "reject_cosmos_throughput_limit_below_minimum" {
  command = plan
  override_data {
    target          = data.azapi_resource.existing_cosmos[0]
    override_during = plan
    values = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared/providers/Microsoft.DocumentDB/databaseAccounts/existing-cosmos"
      location = "West US 3"
      output = {
        kind = "GlobalDocumentDB"
        properties = {
          publicNetworkAccess = "Disabled"
          documentEndpoint    = "https://existing-cosmos.documents.azure.com:443/"
          capabilities        = []
          capacity            = { totalThroughputLimit = 2999 }
        }
      }
    }
  }
  expect_failures = [data.azapi_resource.existing_cosmos[0]]
}

run "accept_cosmos_minimum_throughput_limit" {
  command = plan
  override_data {
    target          = data.azapi_resource.existing_cosmos[0]
    override_during = plan
    values = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared/providers/Microsoft.DocumentDB/databaseAccounts/existing-cosmos"
      location = "West US 3"
      output = {
        kind = "GlobalDocumentDB"
        properties = {
          publicNetworkAccess = "Disabled"
          documentEndpoint    = "https://existing-cosmos.documents.azure.com:443/"
          capabilities        = []
          capacity            = { totalThroughputLimit = 3000 }
        }
      }
    }
  }
}

run "accept_unlimited_cosmos_throughput" {
  command = plan
  override_data {
    target          = data.azapi_resource.existing_cosmos[0]
    override_during = plan
    values = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared/providers/Microsoft.DocumentDB/databaseAccounts/existing-cosmos"
      location = "West US 3"
      output = {
        kind = "GlobalDocumentDB"
        properties = {
          publicNetworkAccess = "Disabled"
          documentEndpoint    = "https://existing-cosmos.documents.azure.com:443/"
          capabilities        = []
          capacity            = { totalThroughputLimit = -1 }
        }
      }
    }
  }
}

run "reject_search_without_entra_auth" {
  command = plan
  override_data {
    target          = data.azapi_resource.existing_search[0]
    override_during = plan
    values = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared/providers/Microsoft.Search/searchServices/existing-search"
      location = "westus3"
      output = {
        sku = { name = "standard" }
        properties = {
          publicNetworkAccess = "Disabled"
          disableLocalAuth    = false
        }
      }
    }
  }
  expect_failures = [data.azapi_resource.existing_search[0]]
}
