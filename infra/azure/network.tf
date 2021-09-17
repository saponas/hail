resource "azurerm_virtual_network" "default" {
  name                = "default"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]
}

resource "azurerm_subnet" "kubesubnet" {
  name                 = "kubesubnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.1.60.0/22"]  # supports 1022 nodes
  service_endpoints    = ["Microsoft.Sql"] # Enable service endpoint to MySQL
}

resource "azurerm_public_ip" "gateway" {
  name                = "gateway"
  location            = data.azurerm_resource_group.node_rg.location
  resource_group_name = data.azurerm_resource_group.node_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  # Seems to be a new TF bug forcing replacement despite no change...
  lifecycle {
    ignore_changes  = ["location", ]
  }
}

locals {
  # Fixed IP for internal-lb gateway - must be in the AKS subnet but unused,
  # so we pick a value at the very top of the space beyond the max node IP
  internal_ip = "10.1.63.254"
  # Top-level external domain name. External to the Terraform setup this domain
  # must be purchased and name servers set up to resolve to the "gateway" public IP.
  domain = "az${var.deployment_name}.net"
}
