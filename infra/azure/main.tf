# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "1.13.3"
    }
  }
}

terraform {
    backend "azurerm" {}
}

# Configure the Microsoft Azure Provider
# This block is only necessary if the account running terraform does not have appropriate
# privs to register resource providers. In that case, Terraform will fail to 
# apply the plan unless all required resource providers are registered by an account 
# with appropriate privs.
#
# You can verify whether you have sufficient privs to register resource providers by 
# running the following az cli command:
#   `az provider register --subscription "YOURSUBSCRIPTION" -n Microsoft.Maps
provider "azurerm" {
#   skip_provider_registration=true
 
  features {
  }
}

### Variables

variable "deployment_name" {}
variable "location" {}

### Shared resources

resource "azurerm_resource_group" "rg" {
  name = "${var.deployment_name}-rg"
  location = var.location
}

### Networking-related resources

resource "azurerm_virtual_network" "vnet" {
  name = "hail_vnet"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space = ["10.0.0.0/16"]
  dns_servers = ["10.0.0.4", "10.0.0.5"]
}

resource "azurerm_public_ip" "gateway" {
  name = "gateway"
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
  allocation_method = "Static"
}

resource "azurerm_public_ip" "internal_gateway" {
  # TODO, make the equivalent of address_type=INTERNAL, probably using NSG
  name = "internal-gateway"
  resource_group_name = azurerm_resource_group.rg.name
  location = azurerm_resource_group.rg.location
  allocation_method = "Static"
}

### Kubernetes-related resources

resource "azurerm_container_registry" "acr" {
    name                = "${var.deployment_name}acr"
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location
    sku                 = "Premium"
}

resource "azurerm_kubernetes_cluster" "vdc" {
    name                = "${var.deployment_name}vdc"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    dns_prefix          = "${var.deployment_name}vdc"

#    linux_profile {
#        admin_username = "ubuntu"
#
#        ssh_key {
#            key_data = file(var.ssh_public_key)
#        }
#    }

    default_node_pool {
        name            = "agentpool"
        node_count      = 2
        vm_size         = "Standard_D2_v2"
    }

    identity {
        type                      = "SystemAssigned"
    }

#    addon_profile {
#        oms_agent {
#        enabled                    = true
#        log_analytics_workspace_id = azurerm_log_analytics_workspace.laworkspace.id
#        }
#    }

    network_profile {
        load_balancer_sku = "Standard"
        network_plugin = "kubenet"
    }
}

resource "azurerm_kubernetes_cluster_node_pool" "vdc_preemptible_pool" {
  # TODO, name change from GCP configuration. Look for impact throughout codebase
  name = "preempt"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.vdc.id
  vm_size = "Standard_D2_v2"
  enable_auto_scaling = true
  node_count = 1
  max_count = 200
  min_count = 0

  priority = "Spot"
  node_labels = {
    "preemptible" = "true"
  }
  node_taints = [ "preemptible=true:NoSchedule"]

  # TODO, this resource always requires delete/re-add on subsequent terraform apply calls. I think a change in the config here can fix that.
  # TODO, may need metadata and oath_scopes equivalent from GCP configuration. 
}

resource "azurerm_kubernetes_cluster_node_pool" "vdc_nonpreemptible_pool" {
  # TODO, name change from GCP configuration. Look for impact throughout codebase.
  name = "nonpreempt"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.vdc.id
  vm_size = "Standard_D2_v2"
  enable_auto_scaling = true
  node_count = 1
  max_count = 200
  min_count = 0

  node_labels = {
    "preemptible" = "false"
  }

  # TODO, may need metadata and oath_scopes equivalent from GCP configuration
}

resource "azurerm_role_assignment" "acr_pull" {
  scope = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id = azurerm_kubernetes_cluster.vdc.kubelet_identity[0].object_id
}

resource "azurerm_role_assignment" "acr_push" {
  scope = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id = azurerm_kubernetes_cluster.vdc.kubelet_identity[0].object_id
}

provider "kubernetes" {
  load_config_file = false

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

resource "kubernetes_secret" "global_config" {
  metadata{
    name = "global-config"
  }

  data = {
    batch_gcp_regions = "TODO"
    batch_logs_bucket = "TODO"
    hail_query_gcs_path = "TODO"
    default_namespace = "default"
    docker_root_image = "${azurerm_container_registry.acr.login_server}/ubuntu:18.04"
    domain = "TODO"
    gcp_project = "TODO"
    gcp_region = "TODO"
    gcp_zone = "TODO"
    docker_prefix = azurerm_container_registry.acr.login_server
    gsuite_organization = "TODO"
    internal_ip = azurerm_public_ip.internal_gateway.ip_address
    ip = azurerm_public_ip.gateway.ip_address
    kubernetes_server_url = "https://${azurerm_kubernetes_cluster.vdc.fqdn}"
  }
}


