
resource "random_password" "db_root_password" {
  length = 22
}

resource "azurerm_mysql_server" "db_server" {
  name                = "${var.deployment_name}dbserver"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  administrator_login          = "dbroot"
  administrator_login_password = random_password.db_root_password.result

  sku_name   = "GP_Gen5_2"
  storage_mb = 5120
  version    = "5.7"

  # Disabling public access also disables service endpoints.
  # TODO consider private link/private endpoint instead
  # public_network_access_enabled = false
  ssl_enforcement_enabled = true
}

# Create a VNET rule that only accepts connections from the cluster.
resource "azurerm_mysql_virtual_network_rule" "mysql_vnet_rule" {
  name                = "mysql-vnet-rule"
  resource_group_name = data.azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_server.db_server.name
  subnet_id           = azurerm_subnet.kubesubnet.id
}

resource "azurerm_mysql_database" "db" {
  name                = "auth"
  resource_group_name = data.azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_server.db_server.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}

# Note, SSL/TLS connectivity in Azure Database for MySQL currently only allows use of a predefined 
# certificate to connect to a DB. See https://docs.microsoft.com/en-us/azure/mysql/concepts-ssl-connection-security
# data "http" "mysql_ca_cert" {
#   url = "https://www.digicert.com/CACerts/BaltimoreCyberTrustRoot.crt.pem"
# }
