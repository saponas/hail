resource "azurerm_resource_group" "rg" {
    name     = var.resource_group_name
    location = var.location
}

### Log Analytics Resources ###

resource "random_id" "log_analytics_workspace_name_suffix" {
    byte_length = 8
}

resource "azurerm_log_analytics_workspace" "laworkspace" {
    # The WorkSpace name has to be unique across the whole of azure, not just the current subscription/tenant.
    name                = "${var.deployment_name}la-${random_id.log_analytics_workspace_name_suffix.dec}"
    # Note, log analytics workspace not available in all regions, see https://azure.microsoft.com/en-us/global-infrastructure/services/?products=monitor
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
    sku                 = "PerGB2018"
}

resource "azurerm_log_analytics_solution" "test" {
    solution_name         = "ContainerInsights"
    location              = azurerm_log_analytics_workspace.laworkspace.location
    resource_group_name   = azurerm_resource_group.rg.name
    workspace_resource_id = azurerm_log_analytics_workspace.laworkspace.id
    workspace_name        = azurerm_log_analytics_workspace.laworkspace.name

    plan {
        publisher = "Microsoft"
        product   = "OMSGallery/ContainerInsights"
    }
}

### Container Registry Resources ###

resource "azurerm_container_registry" "acr" {
    name                = "${var.deployment_name}acr"
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location
    sku                 = "Premium"
}

### K8s Resources ###

# resource "azurerm_user_assigned_identity" "uai" {
#     name                = "${var.deployment_name}_uai"
#     location            = azurerm_resource_group.rg.location
#     resource_group_name = azurerm_resource_group.rg.name
# }

resource "azurerm_kubernetes_cluster" "k8s" {
    name                = var.k8s_cluster_name
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    dns_prefix          = "${var.deployment_name}k8s"

    linux_profile {
        admin_username = "ubuntu"

        ssh_key {
            key_data = file(var.ssh_public_key)
        }
    }

    default_node_pool {
        name            = "agentpool"
        node_count      = var.agent_count
        vm_size         = "Standard_D2_v2"
    }

    identity {
        type                      = "SystemAssigned"
    }

    addon_profile {
        oms_agent {
        enabled                    = true
        log_analytics_workspace_id = azurerm_log_analytics_workspace.laworkspace.id
        }
    }

    network_profile {
        load_balancer_sku = "Standard"
        network_plugin = "kubenet"
    }
}

resource "azurerm_role_assignment" "k8s_acr_pull" {
    scope = azurerm_container_registry.acr.id
    role_definition_name = "AcrPull"
    principal_id = azurerm_kubernetes_cluster.k8s.kubelet_identity[0].object_id
}
