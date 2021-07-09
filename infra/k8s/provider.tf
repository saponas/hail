terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
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
