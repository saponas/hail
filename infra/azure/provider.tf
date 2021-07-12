terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.67.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "1.13.3"
    }
  }
}

# Use Azure blob store to manage tfstate
terraform {
  backend "azurerm" {}
}

# Configure the Azure provider
provider "azurerm" {
  features {}
  # Provider registrations (Microsoft.DataProtection, Microsoft.AVS) require 
  # subscription-level permissions, so they must be registered ahead of time
  skip_provider_registration = true
}

# Master resource group for deployment (unmanaged)
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}
