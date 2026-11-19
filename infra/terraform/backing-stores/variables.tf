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
  description = "New resource group for the independently managed backing services."
}

variable "location" {
  type        = string
  default     = "westus3"
  description = "Region shared with the Foundry deployment."
}

variable "name_prefix" {
  type        = string
  default     = "hoabyo"
  description = "Short lowercase prefix; the subscription and resource group determine the suffix."
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.name_prefix))
    error_message = "Use 3-10 lowercase alphanumeric characters, starting with a letter."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional organization-approved non-sensitive tags."
}
