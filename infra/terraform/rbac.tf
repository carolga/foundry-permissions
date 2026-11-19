locals {
  project_roles = {
    foundry_user       = azapi_resource.project.id
    storage_management = local.storage_id
    storage_data       = local.storage_id
    search_management  = local.search_id
    search_data        = local.search_id
    cosmos_management  = local.cosmos_id
  }
}

resource "azapi_resource" "project_role" {
  for_each  = local.project_roles
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("url", "${each.value}/${azapi_resource.project.identity[0].principal_id}/${local.role_ids[each.key]}")
  parent_id = each.value
  body = {
    properties = {
      principalId      = azapi_resource.project.identity[0].principal_id
      principalType    = "ServicePrincipal"
      roleDefinitionId = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids[each.key]}"
    }
  }
}

resource "azapi_resource" "cosmos_data_role" {
  type      = "Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-04-15"
  name      = uuidv5("url", "${local.cosmos_id}/${azapi_resource.project.identity[0].principal_id}/data-contributor")
  parent_id = local.cosmos_id
  body = {
    properties = {
      principalId      = azapi_resource.project.identity[0].principal_id
      roleDefinitionId = "${local.cosmos_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
      scope            = local.cosmos_id
    }
  }
}

resource "azapi_resource" "developer_role" {
  for_each  = var.developer_principal_ids
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("url", "${azapi_resource.project.id}/${each.value}/foundry-user")
  parent_id = azapi_resource.project.id
  body = {
    properties = {
      principalId      = each.value
      roleDefinitionId = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/${local.role_ids.foundry_user}"
    }
  }
}
