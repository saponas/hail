
resource "azurerm_kubernetes_cluster" "vdc" {
  name                = "${var.deployment_name}vdc"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  dns_prefix          = "${var.deployment_name}vdc"
  node_resource_group = "${var.deployment_name}-node-rg"

  #   linux_profile {
  #     admin_username = var.vm_user_name

  #     ssh_key {
  #       key_data = file(var.public_ssh_key_path)
  #     }
  #   }

  addon_profile {
    http_application_routing {
      enabled = false
    }
    ingress_application_gateway {
        enabled = true
        gateway_name = "appgateway1"
        subnet_cidr = "15.1.0.0/16"
    }
  }

  default_node_pool {
    name           = "agentpool"
    node_count     = 2
    vm_size        = "Standard_D2_v2"
    vnet_subnet_id = resource.azurerm_subnet.kubesubnet.id
  }

  identity {
    type = "SystemAssigned"
  }

#   network_profile {
#     network_plugin = "azure"
#     service_cidr   = "10.0.0.0/16"
#     # Address within the Kubernetes service range for kube-dns
#     dns_service_ip     = "10.0.0.10"
#     docker_bridge_cidr = "172.17.0.1/16"
#   }

  depends_on = [azurerm_virtual_network.default]
}
