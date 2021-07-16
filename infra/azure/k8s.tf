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

data "azurerm_resource_group" "node_rg" {
  name = azurerm_kubernetes_cluster.vdc.node_resource_group
}

resource "azurerm_kubernetes_cluster_node_pool" "vdc_preemptible_pool" {
  # TODO, name change from GCP configuration. Look for impact throughout codebase
  name                  = "preempt"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.vdc.id
  vm_size               = "Standard_D2_v2"
  enable_auto_scaling   = true
  max_count             = 200
  min_count             = 0
  # Must explicitly specify subnet or node pool will be recreated on every apply.
  vnet_subnet_id = resource.azurerm_subnet.kubesubnet.id
  # Spot priority adds default labels, taints, and eviction policy that are 
  # specified explicitly to avoid node pool getting recreated on every apply.
  priority        = "Spot"
  eviction_policy = "Delete"

  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
    "preemptible"                           = "true"
  }
  node_taints = [
    "preemptible=true:NoSchedule",
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "vdc_nonpreemptible_pool" {
  # TODO, name change from GCP configuration. Look for impact throughout codebase.
  name                  = "nonpreempt"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.vdc.id
  vm_size               = "Standard_D2_v2"
  enable_auto_scaling   = true
  max_count             = 200
  min_count             = 0
  # Must explicitly specify subnet or node pool will be recreated on every apply.
  vnet_subnet_id = resource.azurerm_subnet.kubesubnet.id

  node_labels = {
    "preemptible" = "false"
  }
}

resource "kubernetes_secret" "global_config" {
  metadata {
    name = "global-config"
  }

  data = {
    batch_gcp_regions     = "TODO"
    batch_logs_bucket     = "TODO"
    hail_query_gcs_path   = "TODO"
    default_namespace     = "default"
    docker_root_image     = "${azurerm_container_registry.acr.login_server}/ubuntu:18.04"
    domain                = "TODO"
    gcp_project           = "TODO"
    gcp_region            = "TODO"
    gcp_zone              = "TODO"
    docker_prefix         = azurerm_container_registry.acr.login_server
    gsuite_organization   = "TODO"
    internal_ip           = "TODO"
    ip                    = azurerm_public_ip.gateway.ip_address
    kubernetes_server_url = "https://${azurerm_kubernetes_cluster.vdc.fqdn}"
  }
}

resource "azurerm_container_registry" "acr" {
  name                = "${var.deployment_name}acr"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  sku                 = "Premium"
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.vdc.kubelet_identity[0].object_id
}

resource "azurerm_role_assignment" "acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_kubernetes_cluster.vdc.kubelet_identity[0].object_id
}
