output "config_map_id" {
  description = "The ID of the Kubernetes ConfigMap containing the logging configuration. This can be used to chain other downstream dependencies to the ConfigMap."
  value       = kubernetes_config_map.logging.id
}
