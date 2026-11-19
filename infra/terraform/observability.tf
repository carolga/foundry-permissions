resource "azapi_resource" "monitor_workspace" {
  count     = var.observability_enabled ? 1 : 0
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  name      = "law-${local.account_name}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      features                        = { enableLogAccessUsingOnlyResourcePermissions = true }
      publicNetworkAccessForIngestion = "Disabled"
      publicNetworkAccessForQuery     = "Disabled"
      retentionInDays                 = var.observability_retention_days
      sku                             = { name = "PerGB2018" }
    }
  }
}

resource "azapi_resource" "application_insights" {
  count     = var.observability_enabled ? 1 : 0
  type      = "Microsoft.Insights/components@2020-02-02"
  name      = "appi-${local.account_name}"
  parent_id = azapi_resource.resource_group.id
  location  = var.location
  tags      = local.tags
  body = {
    kind = "web"
    properties = {
      Application_Type                = "web"
      DisableLocalAuth                = true
      RetentionInDays                 = var.observability_retention_days
      SamplingPercentage              = 100
      WorkspaceResourceId             = azapi_resource.monitor_workspace[0].id
      publicNetworkAccessForIngestion = "Disabled"
      publicNetworkAccessForQuery     = "Disabled"
    }
  }
}

resource "azapi_resource" "monitor_scope" {
  count     = var.observability_enabled ? 1 : 0
  type      = "Microsoft.Insights/privateLinkScopes@2021-09-01"
  name      = "ampls-${local.account_name}"
  parent_id = azapi_resource.resource_group.id
  location  = "global"
  tags      = local.tags
  body = {
    properties = {
      accessModeSettings = {
        ingestionAccessMode = "PrivateOnly"
        queryAccessMode     = "PrivateOnly"
      }
    }
  }
}

resource "azapi_resource" "monitor_scope_link" {
  for_each = var.observability_enabled ? {
    insights  = azapi_resource.application_insights[0].id
    workspace = azapi_resource.monitor_workspace[0].id
  } : {}
  type      = "Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01"
  name      = each.key
  parent_id = azapi_resource.monitor_scope[0].id
  body      = { properties = { linkedResourceId = each.value } }
}

resource "azapi_resource" "monitor_project_role" {
  for_each = var.observability_enabled ? toset([
    "3913510d-42f4-4e42-8a64-420c390055eb",
    "43d0d8ad-25c7-4714-9337-8ba259a9fe05",
  ]) : toset([])
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  parent_id = azapi_resource.application_insights[0].id
  name      = uuidv5("url", "${azapi_resource.application_insights[0].id}/${azapi_resource.project.identity[0].principal_id}/${each.value}")
  body = {
    properties = {
      principalId      = azapi_resource.project.identity[0].principal_id
      principalType    = "ServicePrincipal"
      roleDefinitionId = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
    }
  }
}

resource "azapi_resource" "monitor_reader_role" {
  for_each  = var.observability_enabled ? var.trace_reader_principal_ids : toset([])
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  parent_id = azapi_resource.application_insights[0].id
  name      = uuidv5("url", "${azapi_resource.application_insights[0].id}/${each.value}/73c42c96-874c-492b-b04d-ab87d138a893")
  body = {
    properties = {
      principalId      = each.value
      roleDefinitionId = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/73c42c96-874c-492b-b04d-ab87d138a893"
    }
  }
}

resource "azapi_resource" "monitor_connection" {
  count     = var.observability_enabled ? 1 : 0
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "conn-hoa-monitoring"
  parent_id = azapi_resource.project.id
  # The published schema omits ProjectManagedIdentity, which the service supports.
  schema_validation_enabled = false
  body = {
    properties = {
      authType                    = "ProjectManagedIdentity"
      category                    = "AppInsights"
      isSharedToAll               = false
      target                      = azapi_resource.application_insights[0].id
      useWorkspaceManagedIdentity = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = azapi_resource.application_insights[0].id
        location   = var.location
      }
    }
  }
  depends_on = [azapi_resource.monitor_project_role, azapi_resource.dns_zone_group]
}
