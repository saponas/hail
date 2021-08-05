terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.67.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.2.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "2.1.0"
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

# Configure the Kubernetes provider
provider "kubernetes" {
  host = "https://${azurerm_kubernetes_cluster.vdc.fqdn}"

  cluster_ca_certificate = base64decode(
    azurerm_kubernetes_cluster.vdc.kube_config[0].cluster_ca_certificate
  )
  client_certificate = base64decode(
    azurerm_kubernetes_cluster.vdc.kube_config[0].client_certificate
  )
  client_key = base64decode(
    azurerm_kubernetes_cluster.vdc.kube_config[0].client_key
  )
}

# Master resource group for deployment (unmanaged)
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}
