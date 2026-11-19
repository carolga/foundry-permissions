resource "azapi_resource" "vnet" {
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name      = "vnet-${local.account_name}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      addressSpace = { addressPrefixes = [var.vnet_address_prefix] }
    }
  }
}

resource "azapi_resource" "agent_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "agents"
  parent_id = azapi_resource.vnet.id
  body = {
    properties = {
      addressPrefix = var.agent_subnet_prefix
      delegations = [{
        name       = "agent-service"
        properties = { serviceName = "Microsoft.App/environments" }
      }]
    }
  }
}

resource "azapi_resource" "private_endpoint_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "private-endpoints"
  parent_id = azapi_resource.vnet.id
  locks     = [azapi_resource.vnet.id]
  body = {
    properties = {
      addressPrefix                     = var.private_endpoint_subnet_prefix
      privateEndpointNetworkPolicies    = "Disabled"
      privateLinkServiceNetworkPolicies = "Enabled"
    }
  }
  depends_on = [azapi_resource.agent_subnet]
}

locals {
  dns_zones = setunion(toset([
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.services.ai.azure.com",
    "privatelink.blob.core.windows.net",
    "privatelink.search.windows.net",
    "privatelink.documents.azure.com",
    ]), var.observability_enabled ? toset([
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
  ]) : toset([]))
  private_endpoints = merge({
    foundry = {
      resource_id = azapi_resource.account.id
      group_id    = "account"
      zones       = ["privatelink.cognitiveservices.azure.com", "privatelink.openai.azure.com", "privatelink.services.ai.azure.com"]
    }
    storage = {
      resource_id = local.storage_id
      group_id    = "blob"
      zones       = ["privatelink.blob.core.windows.net"]
    }
    search = {
      resource_id = local.search_id
      group_id    = "searchService"
      zones       = ["privatelink.search.windows.net"]
    }
    cosmos = {
      resource_id = local.cosmos_id
      group_id    = "Sql"
      zones       = ["privatelink.documents.azure.com"]
    }
    }, var.observability_enabled ? {
    monitor = {
      resource_id = azapi_resource.monitor_scope[0].id
      group_id    = "azuremonitor"
      zones = [
        "privatelink.monitor.azure.com",
        "privatelink.oms.opinsights.azure.com",
        "privatelink.ods.opinsights.azure.com",
        "privatelink.agentsvc.azure-automation.net",
        "privatelink.blob.core.windows.net",
      ]
    }
  } : {})
}

resource "azapi_resource" "dns_zone" {
  for_each  = local.dns_zones
  type      = "Microsoft.Network/privateDnsZones@2024-06-01"
  name      = each.value
  parent_id = azapi_resource.resource_group.id
  location  = "global"
  tags      = local.tags
}

resource "azapi_resource" "dns_link" {
  for_each  = local.dns_zones
  type      = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01"
  name      = "foundry-vnet"
  parent_id = azapi_resource.dns_zone[each.value].id
  location  = "global"
  tags      = local.tags
  body = {
    properties = {
      registrationEnabled = false
      virtualNetwork      = { id = azapi_resource.vnet.id }
    }
  }
}

resource "azapi_resource" "private_endpoint" {
  for_each  = local.private_endpoints
  type      = "Microsoft.Network/privateEndpoints@2024-05-01"
  name      = "pe-${each.key}-${local.suffix}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      subnet = { id = azapi_resource.private_endpoint_subnet.id }
      privateLinkServiceConnections = [{
        name = each.key
        properties = {
          privateLinkServiceId = each.value.resource_id
          groupIds             = [each.value.group_id]
        }
      }]
    }
  }
  depends_on = [azapi_resource.monitor_scope_link]
}

resource "azapi_resource" "dns_zone_group" {
  for_each  = local.private_endpoints
  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01"
  name      = "default"
  parent_id = azapi_resource.private_endpoint[each.key].id
  body = {
    properties = {
      privateDnsZoneConfigs = [for zone in each.value.zones : {
        name       = replace(zone, ".", "-")
        properties = { privateDnsZoneId = azapi_resource.dns_zone[zone].id }
      }]
    }
  }
  depends_on = [azapi_resource.dns_link]
}
