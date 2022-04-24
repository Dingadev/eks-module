output "vpc_id" {
  description = "ID of the VPC created as part of the example."
  value       = module.vpc_app.vpc_id
}

output "eks_cluster_arn" {
  description = "AWS ARN identifier of the EKS cluster resource that is created."
  value       = module.eks_cluster.eks_cluster_arn
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster resource that is created."
  value       = module.eks_cluster.eks_cluster_name
}

output "eks_cluster_managed_security_group_id" {
  description = "The ID of the EKS Cluster Security Group, which is automatically attached to managed workers."
  value       = module.eks_cluster.eks_cluster_managed_security_group_id
}

output "eks_openid_connect_provider_arn" {
  description = "ARN of the OpenID Connect Provider that can be used to attach AWS IAM Roles to Kubernetes Service Accounts."
  value       = module.eks_cluster.eks_iam_openid_connect_provider_arn
}

output "eks_openid_connect_provider_url" {
  description = "URL of the OpenID Connect Provider that can be used to attach AWS IAM Roles to Kubernetes Service Accounts."
  value       = module.eks_cluster.eks_iam_openid_connect_provider_url
}

output "eks_cluster_addons" {
  description = "Map of attribute maps for enabled EKS cluster addons"
  value       = module.eks_cluster.eks_cluster_addons
}
