output "aws_auth_config_map_name" {
  description = "The name of the ConfigMap created to store the mapping. This exists so that downstream resources can depend on the mapping being setup."
  value       = kubernetes_config_map.eks_to_k8s_role_mapping.metadata[0].name
}
