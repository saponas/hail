
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

resource "random_id" "log_analytics_workspace_name_suffix" {
    byte_length = 8
}

resource "azurerm_log_analytics_workspace" "la" {
    # The Workspace name has to be unique across the whole of azure, not just the current subscription/tenant.
    name                = "loganalytics-${random_id.log_analytics_workspace_name_suffix.dec}"
    location            = data.azurerm_resource_group.rg.location
    resource_group_name = data.azurerm_resource_group.rg.name
    sku                 = "PerGB2018"
}

resource "azurerm_log_analytics_solution" "la" {
    solution_name         = "ContainerInsights"
    location              = azurerm_log_analytics_workspace.la.location
    resource_group_name   = data.azurerm_resource_group.rg.name
    workspace_resource_id = azurerm_log_analytics_workspace.la.id
    workspace_name        = azurerm_log_analytics_workspace.la.name

    plan {
        publisher = "Microsoft"
        product   = "OMSGallery/ContainerInsights"
    }
}

resource "azurerm_kubernetes_cluster" "vdc" {
    name                = "${var.deployment_name}vdc"
    location            = data.azurerm_resource_group.rg.location
    resource_group_name = data.azurerm_resource_group.rg.name
    dns_prefix          = "${var.deployment_name}vdc"

    # linux_profile {
    #     admin_username = "ubuntu"

    #     ssh_key {
    #         key_data = file(var.ssh_public_key)
    #     }
    # }

    default_node_pool {
        name            = "agentpool"
        node_count      = 3
        vm_size         = "Standard_D2_v2"
    }

    identity {
        type             = "SystemAssigned"
    }

    addon_profile {
        oms_agent {
        enabled                    = true
        log_analytics_workspace_id = azurerm_log_analytics_workspace.la.id
        }
    }

    network_profile {
        load_balancer_sku = "Standard"
        network_plugin = "kubenet"
    }

    tags = {
        Environment = "Development"
    }
}