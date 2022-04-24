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

output "eks_app_worker_iam_role_arn" {
  description = "AWS ARN identifier of the IAM role created for the EKS application worker nodes."
  value       = module.eks_workers.eks_worker_iam_role_arn
}

output "eks_app_worker_iam_role_name" {
  description = "Name of the IAM role created for the EKS application worker nodes."
  value       = module.eks_workers.eks_worker_iam_role_name
}

output "eks_core_worker_iam_role_arn" {
  description = "AWS ARN identifier of the IAM role created for the EKS core services worker nodes."
  value       = module.eks_core_workers.eks_worker_iam_role_arn
}

output "eks_core_worker_iam_role_name" {
  description = "Name of the IAM role created for the EKS core services worker nodes."
  value       = module.eks_core_workers.eks_worker_iam_role_name
}

output "eks_app_worker_asg_names" {
  description = "Names of each ASG for the EKS application worker nodes."
  value       = module.eks_workers.eks_worker_asg_names
}

output "eks_app_worker_asg_arns" {
  description = "ARNs of each ASG for the EKS application worker nodes."
  value       = module.eks_workers.eks_worker_asg_arns
}

output "eks_core_worker_asg_names" {
  description = "Names of each ASG for the EKS core worker nodes."
  value       = module.eks_core_workers.eks_worker_asg_names
}

output "eks_core_worker_asg_arns" {
  description = "ARNs of each ASG for the EKS core services worker nodes."
  value       = module.eks_core_workers.eks_worker_asg_arns
}

output "eks_openid_connect_provider_arn" {
  description = "ARN of the OpenID Connect Provider that can be used to attach AWS IAM Roles to Kubernetes Service Accounts."
  value       = module.eks_cluster.eks_iam_openid_connect_provider_arn
}

output "eks_openid_connect_provider_url" {
  description = "URL of the OpenID Connect Provider that can be used to attach AWS IAM Roles to Kubernetes Service Accounts."
  value       = module.eks_cluster.eks_iam_openid_connect_provider_url
}
