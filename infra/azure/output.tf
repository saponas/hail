#outputs
output "kube_config" {
  value     = azurerm_kubernetes_cluster.vdc.kube_config_raw
  sensitive = true
}
