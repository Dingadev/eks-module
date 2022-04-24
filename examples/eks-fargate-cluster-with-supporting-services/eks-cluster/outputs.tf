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

output "eks_vpc_worker_subnet_ids" {
  description = "A list of the subnets into which Fargate workloads should be launched."
  value       = module.vpc_app.private_app_subnet_ids
}

output "eks_fargate_default_execution_role_arn" {
  description = "A basic IAM Role ARN that has the minimal permissions to pull images from ECR that can be used for most Pods that do not need to interact with AWS."
  value       = module.eks_cluster.eks_default_fargate_execution_role_arn
}

output "eks_openid_connect_provider_arn" {
  description = "ARN of the OpenID Connect Provider that can be used to attach AWS IAM Roles to Kubernetes Service Accounts."
  value       = module.eks_cluster.eks_iam_openid_connect_provider_arn
}

output "eks_openid_connect_provider_url" {
  description = "URL of the OpenID Connect Provider that can be used to attach AWS IAM Roles to Kubernetes Service Accounts."
  value       = module.eks_cluster.eks_iam_openid_connect_provider_url
}
