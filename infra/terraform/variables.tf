variable "subscription_id" {
  type        = string
  description = "Explicit target Azure public-cloud subscription."
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "Supply a subscription UUID."
  }
}

variable "resource_group_name" {
  type        = string
  description = "NEW resource group; never point this sample at the existing Bicep deployment."
  default     = "rg-foundry-terraform-test"
}

variable "location" {
  type        = string
  description = "Foundry, VNet, and backing-store region. Confirm regional availability first."
  default     = "westus3"
}

variable "name_prefix" {
  type        = string
  default     = "hoatf"
  description = "Short lowercase prefix; a deterministic subscription/RG suffix ensures distinct names."
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.name_prefix))
    error_message = "Use 3-10 lowercase alphanumeric characters, starting with a letter."
  }
}

variable "project_name" {
  type    = string
  default = "hoa-project"
}

variable "existing_storage_account_id" {
  type        = string
  description = "Optional same-subscription Storage account ID. The account is read, not managed by this configuration."
  default     = null
  validation {
    condition = var.existing_storage_account_id == null ? true : (
      can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.storage/storageaccounts/[^/]+$", var.existing_storage_account_id)) &&
      startswith(lower(var.existing_storage_account_id), lower("/subscriptions/${var.subscription_id}/"))
    )
    error_message = "Supply a full Storage account resource ID in the target subscription, or null."
  }
}

variable "existing_cosmos_account_id" {
  type        = string
  description = "Optional same-subscription Cosmos DB for NoSQL account ID. The account is read, not managed by this configuration."
  default     = null
  validation {
    condition = var.existing_cosmos_account_id == null ? true : (
      can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.documentdb/databaseaccounts/[^/]+$", var.existing_cosmos_account_id)) &&
      startswith(lower(var.existing_cosmos_account_id), lower("/subscriptions/${var.subscription_id}/"))
    )
    error_message = "Supply a full Cosmos DB account resource ID in the target subscription, or null."
  }
}

variable "existing_search_service_id" {
  type        = string
  description = "Optional same-subscription Azure AI Search service ID. The service is read, not managed by this configuration."
  default     = null
  validation {
    condition = var.existing_search_service_id == null ? true : (
      can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.search/searchservices/[^/]+$", var.existing_search_service_id)) &&
      startswith(lower(var.existing_search_service_id), lower("/subscriptions/${var.subscription_id}/"))
    )
    error_message = "Supply a full Azure AI Search resource ID in the target subscription, or null."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional organization-approved non-sensitive tags."
  default     = {}
}

variable "vnet_address_prefix" {
  type    = string
  default = "10.241.0.0/16"
}

variable "agent_subnet_prefix" {
  type    = string
  default = "10.241.0.0/24"
}

variable "private_endpoint_subnet_prefix" {
  type    = string
  default = "10.241.1.0/24"
}

variable "validation_subnet_prefix" {
  type    = string
  default = "10.241.2.0/27"
}

variable "bastion_subnet_prefix" {
  type        = string
  default     = null
  description = "Optional unused IPv4 CIDR for AzureBastionSubnet; enables billable Bastion for validation VMs."
  validation {
    condition = var.bastion_subnet_prefix == null ? true : try(
      can(cidrnetmask(var.bastion_subnet_prefix)) &&
      tonumber(split("/", var.bastion_subnet_prefix)[1]) <= 26 &&
      cidrhost(var.bastion_subnet_prefix, 0) == split("/", var.bastion_subnet_prefix)[0],
      false
    )
    error_message = "Use an IPv4 network CIDR of /26 or larger for Bastion, or null to disable it."
  }
  validation {
    condition     = var.bastion_subnet_prefix == null || var.validation_ssh_public_key != null || var.windows_desktop_enabled
    error_message = "Bastion requires a Linux validation VM or the Windows desktop."
  }
  validation {
    condition     = !var.windows_desktop_enabled || var.bastion_subnet_prefix != null
    error_message = "The Windows desktop requires Bastion."
  }
}

variable "search_replica_count" {
  type        = number
  default     = 1
  description = "One for a disposable test; use at least three for the Search read/write availability SLA."
  validation {
    condition     = var.search_replica_count >= 1 && var.search_replica_count <= 12 && floor(var.search_replica_count) == var.search_replica_count
    error_message = "Use an integer replica count from 1 to 12."
  }
}

variable "model" {
  type = object({
    deployment_name = string
    name            = string
    version         = string
    sku             = string
    capacity        = number
  })
  description = "Optional model. Confirm version, region and quota; null creates infrastructure without a model."
  default     = null
  validation {
    condition     = var.model == null ? true : var.model.capacity >= 1 && floor(var.model.capacity) == var.model.capacity
    error_message = "Model capacity must be a positive integer."
  }
}

variable "observability_enabled" {
  type        = bool
  default     = false
  description = "Create private Application Insights tracing infrastructure; may incur charges and retain customer content."
}

variable "observability_retention_days" {
  type        = number
  default     = 30
  description = "Retention for the Application Insights component and its Log Analytics workspace."
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.observability_retention_days)
    error_message = "Use an Application Insights retention value: 30, 60, 90, 120, 180, 270, 365, 550, or 730 days."
  }
}

variable "trace_reader_principal_ids" {
  type        = set(string)
  default     = []
  description = "Explicitly approved Entra object IDs granted Log Analytics Reader on this project's Application Insights."
  validation {
    condition = alltrue([for id in var.trace_reader_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ]) && (var.observability_enabled || length(var.trace_reader_principal_ids) == 0)
    error_message = "Use Entra object IDs and enable observability before granting trace access."
  }
}

variable "synthetic_prompt_agent_name" {
  type        = string
  default     = null
  description = "Optional new, Terraform-owned synthetic prompt agent name. Requires a model and private project access."
  validation {
    condition = var.synthetic_prompt_agent_name == null ? true : (
      can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$", var.synthetic_prompt_agent_name))
    )
    error_message = "The agent name must be 1-63 letters, digits or hyphens, beginning and ending with a letter or digit."
  }
  validation {
    condition     = var.synthetic_prompt_agent_name == null || var.model != null
    error_message = "A synthetic prompt agent requires a model deployment."
  }
}

variable "developer_principal_ids" {
  type        = set(string)
  default     = []
  description = "Existing user/group/service-principal object IDs granted Foundry User on this project only."
}

variable "validation_ssh_public_key" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional SSH PUBLIC key. Enables a private Linux validation VM with managed identity and no public IP. Never supply a private key."
  validation {
    condition     = var.validation_ssh_public_key == null ? true : can(regex("^ssh-(rsa|ed25519) ", var.validation_ssh_public_key))
    error_message = "Supply an OpenSSH public key, or null to omit the validation VM."
  }
}

variable "windows_desktop_enabled" {
  type        = bool
  default     = false
  description = "Create a private Windows desktop reachable only through Bastion."
}

variable "windows_admin_password" {
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
  description = "Ephemeral Windows administrator password; never store it in a variable file."
  validation {
    condition = var.windows_admin_password == null ? !var.windows_desktop_enabled : (
      length(var.windows_admin_password) >= 12 && length(var.windows_admin_password) <= 123
    )
    error_message = "The Windows desktop requires an administrator password between 12 and 123 characters."
  }
}

variable "windows_entra_login_principal_id" {
  type        = string
  default     = null
  description = "Entra user object ID granted administrator login on the Windows desktop."
  validation {
    condition = var.windows_entra_login_principal_id == null ? !var.windows_desktop_enabled : (
      var.windows_desktop_enabled && can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.windows_entra_login_principal_id))
    )
    error_message = "Supply an Entra user object ID when the Windows desktop is enabled; otherwise use null."
  }
}
