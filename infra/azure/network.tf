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
  address_prefixes     = ["10.1.0.0/22"]
}

resource "azurerm_public_ip" "gateway" {
  name                = "gateway"
  location            = data.azurerm_resource_group.node_rg.location
  resource_group_name = data.azurerm_resource_group.node_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}
