terraform {
  required_version = ">= 1.11, < 2.0"
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.10"
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
  # ARM preflight substitutes an invalid placeholder for the new subnet's
  # unknown ID. Keep local schema validation; Azure validates the real ID on PUT.
  enable_preflight = false
}
