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
}

