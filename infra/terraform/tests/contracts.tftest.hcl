mock_provider "azapi" {}

override_data {
  target = data.azapi_resource_list.locations
  values = {
    output = { display_name = "West US 3" }
  }
}

variables {
  subscription_id           = "00000000-0000-0000-0000-000000000001"
  model                     = null
  validation_ssh_public_key = null
}

run "private_project_contract" {
  command = plan

  assert {
    condition     = azapi_resource.project_host.body.properties.vectorStoreConnections == [azapi_resource.connection["search"].name]
    error_message = "The project host must reference Search CONNECTION NAMES, not resource IDs or endpoints."
  }
  assert {
    condition     = azapi_resource.connection["search"].body.properties.category == "CognitiveSearch" && startswith(azapi_resource.connection["search"].body.properties.target, "https://")
    error_message = "Search must be an AAD project connection with the Search endpoint as target."
  }
  assert {
    condition     = azapi_resource.project_host.body.properties.storageConnections == ["conn-hoa-storage"] && azapi_resource.project_host.body.properties.threadStorageConnections == ["conn-hoa-cosmos"]
    error_message = "Storage and thread storage must be explicitly bound at PROJECT scope."
  }
  assert {
    condition     = alltrue([for resource in [azapi_resource.account, azapi_resource.storage[0], azapi_resource.cosmos[0], azapi_resource.search[0]] : resource.body.properties.publicNetworkAccess == "Disabled"])
    error_message = "All data services must disable public network access."
  }
  assert {
    condition     = length(azapi_resource.private_endpoint) == 4 && length(azapi_resource.validation_vm) == 0 && length(azapi_resource.bastion) == 0 && length(azapi_resource.model) == 0
    error_message = "Default infrastructure must have four private endpoints and no unrequested VM, Bastion or model."
  }
  assert {
    condition     = length(azapi_data_plane_resource.synthetic_prompt_agent) == 0
    error_message = "The synthetic agent must be opt-in."
  }
  assert {
    condition     = length(azapi_resource.application_insights) == 0 && length(azapi_resource.monitor_connection) == 0
    error_message = "Observability must be opt-in."
  }
}

run "private_observability_contract" {
  command = plan
  variables {
    observability_enabled        = true
    trace_reader_principal_ids   = ["00000000-0000-0000-0000-000000000003"]
    observability_retention_days = 60
  }
  assert {
    condition = (
      azapi_resource.application_insights[0].body.properties.DisableLocalAuth &&
      azapi_resource.application_insights[0].body.properties.publicNetworkAccessForIngestion == "Disabled" &&
      azapi_resource.application_insights[0].body.properties.publicNetworkAccessForQuery == "Disabled" &&
      azapi_resource.monitor_workspace[0].body.properties.publicNetworkAccessForIngestion == "Disabled" &&
      azapi_resource.monitor_workspace[0].body.properties.publicNetworkAccessForQuery == "Disabled" &&
      azapi_resource.monitor_workspace[0].body.properties.retentionInDays == 60
    )
    error_message = "Tracing storage must use the requested retention and disable public access and local authentication."
  }
  assert {
    condition = (
      azapi_resource.monitor_scope[0].body.properties.accessModeSettings.ingestionAccessMode == "PrivateOnly" &&
      azapi_resource.monitor_scope[0].body.properties.accessModeSettings.queryAccessMode == "PrivateOnly" &&
      length(azapi_resource.monitor_scope_link) == 2 &&
      length(azapi_resource.private_endpoint) == 5 &&
      azapi_resource.private_endpoint["monitor"].body.properties.privateLinkServiceConnections[0].properties.groupIds == ["azuremonitor"] &&
      length(azapi_resource.dns_zone_group["monitor"].body.properties.privateDnsZoneConfigs) == 5
    )
    error_message = "Monitoring must attach both resources to private-only AMPLS and configure its private endpoint and DNS."
  }
  assert {
    condition = (
      azapi_resource.monitor_connection[0].body.properties.category == "AppInsights" &&
      azapi_resource.monitor_connection[0].body.properties.authType == "ProjectManagedIdentity" &&
      length(azapi_resource.monitor_project_role) == 2 &&
      length(azapi_resource.monitor_reader_role) == 1
    )
    error_message = "The project must use managed-identity telemetry and only grant explicitly requested trace readers."
  }
}

run "reject_trace_reader_without_monitoring" {
  command = plan
  variables {
    trace_reader_principal_ids = ["00000000-0000-0000-0000-000000000003"]
  }
  expect_failures = [var.trace_reader_principal_ids]
}

run "reject_unsupported_monitor_retention" {
  command = plan
  variables {
    observability_retention_days = 31
  }
  expect_failures = [var.observability_retention_days]
}

run "synthetic_prompt_agent_contract" {
  command = plan
  variables {
    synthetic_prompt_agent_name = "hoa-intake-test"
    model = {
      deployment_name = "hoa-chat"
      name            = "gpt-5.4-mini"
      version         = "2026-03-17"
      sku             = "GlobalStandard"
      capacity        = 10
    }
  }
  assert {
    condition = (
      azapi_data_plane_resource.synthetic_prompt_agent[0].name == "hoa-intake-test" &&
      azapi_data_plane_resource.synthetic_prompt_agent[0].type == "Microsoft.Foundry/agents@v1" &&
      azapi_data_plane_resource.synthetic_prompt_agent[0].parent_id == "${local.account_name}.services.ai.azure.com/api/projects/${var.project_name}" &&
      azapi_data_plane_resource.synthetic_prompt_agent[0].body.name == "hoa-intake-test" &&
      azapi_data_plane_resource.synthetic_prompt_agent[0].body.definition.kind == "prompt" &&
      azapi_data_plane_resource.synthetic_prompt_agent[0].body.definition.model == "hoa-chat"
    )
    error_message = "The opt-in agent must use the configured model and the Foundry prompt data-plane API."
  }
}

run "reject_agent_without_model" {
  command = plan
  variables {
    synthetic_prompt_agent_name = "hoa-intake-test"
  }
  expect_failures = [var.synthetic_prompt_agent_name]
}

run "reject_invalid_agent_name" {
  command = plan
  variables {
    synthetic_prompt_agent_name = "-invalid"
    model = {
      deployment_name = "hoa-chat"
      name            = "gpt-5.4-mini"
      version         = "2026-03-17"
      sku             = "GlobalStandard"
      capacity        = 10
    }
  }
  expect_failures = [var.synthetic_prompt_agent_name]
}

run "private_validation_with_bastion" {
  command = plan
  variables {
    validation_ssh_public_key = "ssh-ed25519 AAAA validation-test"
    bastion_subnet_prefix     = "10.241.3.0/26"
  }

  assert {
    condition     = azapi_resource.bastion[0].body.sku.name == "Basic" && azapi_resource.bastion_subnet[0].name == "AzureBastionSubnet"
    error_message = "The optional Linux jumpbox must use Bastion Basic and its dedicated subnet."
  }
  assert {
    condition = (
      azapi_resource.validation_nsg[0].body.properties.securityRules[0].properties.sourceAddressPrefix == var.bastion_subnet_prefix &&
      azapi_resource.validation_nsg[0].body.properties.securityRules[0].properties.destinationPortRange == "22" &&
      azapi_resource.validation_nsg[0].body.properties.securityRules[0].properties.priority == 100 &&
      azapi_resource.validation_nsg[0].body.properties.securityRules[1].properties.access == "Deny" &&
      azapi_resource.validation_nsg[0].body.properties.securityRules[1].properties.priority == 110
    )
    error_message = "Allow only Bastion-originated SSH before the validation subnet's deny-all rule."
  }
  assert {
    condition     = !contains(keys(azapi_resource.validation_nic[0].body.properties.ipConfigurations[0].properties), "publicIPAddress")
    error_message = "The validation VM must not have a public IP."
  }
  assert {
    condition     = length(azapi_resource.bastion_nsg[0].body.properties.securityRules) == 8
    error_message = "The Bastion subnet NSG must retain all documented control-plane, health-probe and session rules."
  }
}

run "windows_desktop_contract" {
  command = plan
  variables {
    validation_ssh_public_key        = "ssh-ed25519 AAAA validation-test"
    bastion_subnet_prefix            = "10.241.3.0/26"
    windows_desktop_enabled          = true
    windows_admin_password           = "Synthetic-Password-1!"
    windows_entra_login_principal_id = "00000000-0000-0000-0000-000000000002"
  }
  assert {
    condition = (
      azapi_resource.validation_nsg[0].body.properties.securityRules[1].properties.sourceAddressPrefix == var.bastion_subnet_prefix &&
      azapi_resource.validation_nsg[0].body.properties.securityRules[1].properties.destinationAddressPrefix == "10.241.2.5/32" &&
      azapi_resource.validation_nsg[0].body.properties.securityRules[1].properties.destinationPortRange == "3389" &&
      azapi_resource.validation_nsg[0].body.properties.securityRules[2].properties.access == "Deny"
    )
    error_message = "Windows RDP must be limited to Bastion and the Windows VM before deny-all."
  }
  assert {
    condition = (
      azapi_resource.bastion[0].body.sku.name == "Standard" &&
      azapi_resource.bastion[0].body.properties.enableTunneling &&
      azapi_resource.windows_vm[0].body.properties.securityProfile.securityType == "TrustedLaunch" &&
      !contains(keys(azapi_resource.windows_nic[0].body.properties.ipConfigurations[0].properties), "publicIPAddress")
    )
    error_message = "The Windows VM must use Trusted Launch without a public IP."
  }
  assert {
    condition = (
      azapi_resource.windows_entra_extension[0].body.properties.type == "AADLoginForWindows" &&
      azapi_resource.windows_entra_role[0].body.properties.principalId == var.windows_entra_login_principal_id &&
      endswith(azapi_resource.windows_entra_role[0].body.properties.roleDefinitionId, "/1c0163c0-47e6-4577-8991-ea5c82e286e4")
    )
    error_message = "Entra login must grant only the supplied user the VM administrator login role."
  }
}

run "windows_without_linux" {
  command = plan
  variables {
    bastion_subnet_prefix            = "10.241.3.0/26"
    windows_desktop_enabled          = true
    windows_admin_password           = "Synthetic-Password-1!"
    windows_entra_login_principal_id = "00000000-0000-0000-0000-000000000002"
  }
  assert {
    condition = (
      length(azapi_resource.validation_vm) == 0 &&
      length(azapi_resource.windows_vm) == 1 &&
      azapi_resource.validation_nsg[0].body.properties.securityRules[0].name == "AllowRdpFromBastion" &&
      azapi_resource.validation_nsg[0].body.properties.securityRules[1].properties.access == "Deny"
    )
    error_message = "Windows and Bastion must work without creating the Linux VM or allowing SSH."
  }
}

run "reject_windows_without_password" {
  command = plan
  variables {
    validation_ssh_public_key        = "ssh-ed25519 AAAA validation-test"
    bastion_subnet_prefix            = "10.241.3.0/26"
    windows_desktop_enabled          = true
    windows_entra_login_principal_id = "00000000-0000-0000-0000-000000000002"
  }
  expect_failures = [var.windows_admin_password]
}

run "reject_windows_without_entra_operator" {
  command = plan
  variables {
    bastion_subnet_prefix   = "10.241.3.0/26"
    windows_desktop_enabled = true
    windows_admin_password  = "Synthetic-Password-1!"
  }
  expect_failures = [var.windows_entra_login_principal_id]
}

run "reject_bastion_without_validation_vm" {
  command = plan
  variables {
    bastion_subnet_prefix = "10.241.3.0/26"
  }
  expect_failures = [var.bastion_subnet_prefix]
}

run "reject_small_bastion_subnet" {
  command = plan
  variables {
    validation_ssh_public_key = "ssh-ed25519 AAAA validation-test"
    bastion_subnet_prefix     = "10.241.3.0/27"
  }
  expect_failures = [var.bastion_subnet_prefix]
}

run "reject_private_key" {
  command = plan
  variables {
    validation_ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----"
  }
  expect_failures = [var.validation_ssh_public_key]
}

run "reject_zero_model_capacity" {
  command = plan
  variables {
    model = {
      deployment_name = "test"
      name            = "gpt-5.4-mini"
      version         = "2026-03-17"
      sku             = "GlobalStandard"
      capacity        = 0
    }
  }
  expect_failures = [var.model]
}
