output "deployment_name" {
  value = var.deployment_name
}
output "resource_group" {
  value = data.azurerm_resource_group.rg.name
}
output "location" {
  value = data.azurerm_resource_group.rg.location
}
output "k8sname" {
  value = azurerm_kubernetes_cluster.vdc.name
}
output "container_registry" {
  value = azurerm_container_registry.acr.name
}
output "kube_config" {
  value     = azurerm_kubernetes_cluster.vdc.kube_config_raw
  sensitive = true
}
output "global_config" {
  value     = kubernetes_secret.global_config.data
  sensitive = true
}

# output "client_key" {
#   value = azurerm_kubernetes_cluster.vdc.kube_config.0.client_key
# }
# output "client_certificate" {
#   value = azurerm_kubernetes_cluster.vdc.kube_config.0.client_certificate
# }
# output "cluster_ca_certificate" {
#   value = azurerm_kubernetes_cluster.vdc.kube_config.0.cluster_ca_certificate
# }
# output "cluster_username" {
#   value = azurerm_kubernetes_cluster.vdc.kube_config.0.username
# }
# output "cluster_password" {
#   value = azurerm_kubernetes_cluster.vdc.kube_config.0.password
# }

