locals {
  subscription_scope = "/subscriptions/${var.subscription_id}"
  suffix             = substr(sha256(lower("${var.subscription_id}/${var.resource_group_name}")), 0, 8)
  account_name       = "${var.name_prefix}-${local.suffix}"
  tags = merge(var.tags, {
    workload  = "foundry-terraform-validation"
    managedBy = "terraform"
  })
  role_ids = {
    foundry_user       = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
    storage_management = "17d1049b-9a84-46fb-8f53-869881c3d3ab"
    storage_data       = "b7e6dc6d-f1e8-4753-8033-0f276bb0955b"
    search_management  = "7ca78c08-252a-4471-8644-bb5ff32d4ba0"
    search_data        = "8ebe5a00-799e-43f5-93ac-243d3dce84a7"
    cosmos_management  = "230815da-be43-4aae-9cb4-875f7bd000aa"
  }
}

resource "azapi_resource" "resource_group" {
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  name      = var.resource_group_name
  parent_id = local.subscription_scope
  location  = var.location
  tags      = local.tags
}
