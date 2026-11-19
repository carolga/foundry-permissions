resource "azapi_resource" "account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = local.account_name
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    kind = "AIServices"
    sku  = { name = "S0" }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = local.account_name
      disableLocalAuth       = true
      publicNetworkAccess    = "Disabled"
      networkAcls = {
        bypass              = "AzureServices"
        defaultAction       = "Deny"
        ipRules             = []
        virtualNetworkRules = []
      }
      networkInjections = [{
        scenario                   = "agent"
        subnetArmId                = azapi_resource.agent_subnet.id
        useMicrosoftManagedNetwork = false
      }]
    }
  }
  timeouts {
    create = "60m"
    delete = "60m"
  }
}

# Network injection creates the account host. Do not PUT a second host or try to
# populate this platform-owned host with project data connections.
data "azapi_resource_list" "account_hosts" {
  type                   = "Microsoft.CognitiveServices/accounts/capabilityHosts@2025-06-01"
  parent_id              = azapi_resource.account.id
  response_export_values = ["value"]
  lifecycle {
    postcondition {
      condition     = length(self.output.value) == 1 && alltrue([for host in self.output.value : host.properties.provisioningState == "Succeeded"])
      error_message = "Expected one successful auto-created account capability host. Inspect the account operation before proceeding; do not create a second host."
    }
  }
}

resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = var.project_name
  parent_id = azapi_resource.account.id
  location  = var.location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    properties = {
      displayName = "HOA Terraform validation"
      description = "Private Standard Agent Setup with explicit project-owned connections."
    }
  }
  depends_on = [
    data.azapi_resource_list.account_hosts,
    azapi_resource.dns_zone_group,
    azapi_update_resource.blob_service,
  ]
}

locals {
  connections = {
    storage = {
      name        = "conn-hoa-storage"
      category    = "AzureStorageAccount"
      resource_id = local.storage_id
      target      = local.storage_target
    }
    cosmos = {
      name        = "conn-hoa-cosmos"
      category    = "CosmosDb"
      resource_id = local.cosmos_id
      target      = local.cosmos_target
    }
    search = {
      name        = "conn-hoa-search"
      category    = "CognitiveSearch"
      resource_id = local.search_id
      target      = local.search_target
    }
  }
}

resource "azapi_resource" "connection" {
  for_each  = local.connections
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = each.value.name
  parent_id = azapi_resource.project.id
  body = {
    properties = {
      authType                    = "AAD"
      category                    = each.value.category
      target                      = each.value.target
      isSharedToAll               = false
      useWorkspaceManagedIdentity = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = each.value.resource_id
        location   = var.location
      }
    }
  }
}

resource "azapi_resource" "project_host" {
  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-06-01"
  name      = "agents"
  parent_id = azapi_resource.project.id
  # The published 2025-06-01 schema omits capabilityHostKind, but the service
  # requires it. Keep this exception scoped to the capability-host resource.
  schema_validation_enabled = false
  body = {
    properties = {
      capabilityHostKind       = "Agents"
      storageConnections       = [azapi_resource.connection["storage"].name]
      threadStorageConnections = [azapi_resource.connection["cosmos"].name]
      vectorStoreConnections   = [azapi_resource.connection["search"].name]
    }
  }
  replace_triggers_refs = ["body"]
  timeouts {
    create = "60m"
    delete = "60m"
  }
  depends_on = [
    azapi_resource.project_role,
    azapi_resource.cosmos_data_role,
    azapi_resource.dns_zone_group,
    azapi_update_resource.blob_service,
  ]
}

resource "azapi_resource" "model" {
  count     = var.model == null ? 0 : 1
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = var.model.deployment_name
  parent_id = azapi_resource.account.id
  body = {
    sku = { name = var.model.sku, capacity = var.model.capacity }
    properties = {
      model = { format = "OpenAI", name = var.model.name, version = var.model.version }
    }
  }
  depends_on = [azapi_resource.project_host]
}
