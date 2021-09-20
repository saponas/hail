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

  network_profile {
    network_plugin = "kubenet"
    # Address range for pods - each node gets a /24 sub-range
    pod_cidr = "10.244.0.0/16"
    # Address range for services
    service_cidr = "10.0.0.0/16"
    # Address within the Kubernetes service range for kube-dns
    dns_service_ip     = "10.0.0.10"
    docker_bridge_cidr = "172.17.0.1/16"
  }

  depends_on = [azurerm_virtual_network.default]
}

resource "azurerm_role_assignment" "aks_subnet" {
  scope                = resource.azurerm_subnet.kubesubnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.vdc.identity[0].principal_id
}

# Get a reference to the resource group created by AKS for the VM nodes.
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
    internal_ip           = local.internal_ip
    ip                    = azurerm_public_ip.gateway.ip_address
    kubernetes_server_url = "https://${azurerm_kubernetes_cluster.vdc.fqdn}"
    admin_email           = "${var.admin_email}"
  }
}

resource "kubernetes_secret" "deploy_config" {
  metadata {
    name = "deploy-config"
  }

  data = {
    "deploy-config.json" = "{\"location\":\"k8s\",\"default_namespace\":\"default\",\"domain\":\"${local.domain}\"}"
  }
}

resource "random_id" "fernet_key" {
  byte_length = 32
}

resource "kubernetes_secret" "session_secret_key" {
  metadata {
    name = "session-secret-key"
  }

  binary_data = {
    "session-secret-key" = "${random_id.fernet_key.b64_std}"
  }
}

resource "azurerm_container_registry" "acr" {
  name                = "${var.deployment_name}acr"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  sku                 = "Premium"
  # Need a username/password for kaniko config.json.
  admin_enabled       = true
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

# This secret is integral to the CI/CD process as kaniko is used for all image 
# building and needs permissions to push to the private registry. With a GCP setup 
# this secret is a service account key translated to a kaniko config before kaniko
# exec; In the Azure setup the secret is already in kaniko's config.json format and
# is simply copied over.
resource "kubernetes_secret" "acr_push_config" {
  metadata {
    name = "gcr-push-service-account-key"
  }

  data = {
    "gcr-push-service-account-key.json" = "{\"auths\":{\"${azurerm_container_registry.acr.name}.azurecr.io\":{\"username\":\"${azurerm_container_registry.acr.admin_username}\",\"password\":\"${azurerm_container_registry.acr.admin_password}\"}}}"
  }
}