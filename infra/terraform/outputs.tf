output "resource_group_name" { value = azapi_resource.resource_group.name }
output "account_id" { value = azapi_resource.account.id }
output "account_name" { value = azapi_resource.account.name }
output "project_id" { value = azapi_resource.project.id }
output "project_endpoint" { value = "https://${local.account_name}.services.ai.azure.com/api/projects/${var.project_name}" }
output "project_principal_id" { value = azapi_resource.project.identity[0].principal_id }
output "project_host_id" { value = azapi_resource.project_host.id }
output "connection_names" { value = { for key, connection in azapi_resource.connection : key => connection.name } }
output "account_capability_hosts" { value = data.azapi_resource_list.account_hosts.output.value }
output "backing_resources" {
  value = {
    storage = local.storage_id
    search  = local.search_id
    cosmos  = local.cosmos_id
  }
}
output "private_endpoint_ids" { value = { for key, endpoint in azapi_resource.private_endpoint : key => endpoint.id } }
output "model_deployment_name" { value = var.model == null ? null : var.model.deployment_name }
output "synthetic_prompt_agent_name" { value = var.synthetic_prompt_agent_name == null ? null : azapi_data_plane_resource.synthetic_prompt_agent[0].name }
output "validation_vm_name" { value = var.validation_ssh_public_key == null ? null : azapi_resource.validation_vm[0].name }
output "bastion_name" { value = var.bastion_subnet_prefix == null ? null : azapi_resource.bastion[0].name }
output "windows_desktop_name" { value = var.windows_desktop_enabled ? azapi_resource.windows_vm[0].name : null }
