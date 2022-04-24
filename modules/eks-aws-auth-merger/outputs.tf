output "namespace" {
  description = "The name of the namespace that is used. If create_namespace is true, this output is only computed after the namespace is done creating."
  value       = local.namespace_name
}
