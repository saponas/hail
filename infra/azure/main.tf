# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
}

terraform {
    backend "azurerm" {}
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  # This is necessary unless the account running terraform has appropriate
  # privs to register resource providers. However, terraform will still fail to 
  # apply the plan unless all required resource providers are registered by an account 
  # with appropriate privs.
  #
  # You can verify whether you have sufficient privs to register resource providers by 
  # running the following az cli command:
  #   `az provider register --subscription "YOURSUBSCRIPTION" -n Microsoft.Maps
  #
  # TODO: consider using a service principal with necessary privs 
  skip_provider_registration=true
  features {
  }
}