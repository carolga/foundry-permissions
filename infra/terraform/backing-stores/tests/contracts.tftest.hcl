mock_provider "azapi" {}

override_data {
  target = data.azapi_resource_list.locations
  values = {
    output = { display_name = "West US 3" }
  }
}

run "private_independent_services" {
  command = plan
  variables {
    subscription_id     = "00000000-0000-0000-0000-000000000001"
    resource_group_name = "rg-backing-stores-test"
  }

  assert {
    condition     = alltrue([for resource in [azapi_resource.storage, azapi_resource.cosmos, azapi_resource.search] : resource.body.properties.publicNetworkAccess == "Disabled"])
    error_message = "All backing services must disable public network access."
  }
  assert {
    condition     = !azapi_resource.storage.body.properties.allowSharedKeyAccess && azapi_resource.cosmos.body.properties.disableLocalAuth && azapi_resource.search.body.properties.disableLocalAuth
    error_message = "Backing services must use Microsoft Entra authentication."
  }
}
