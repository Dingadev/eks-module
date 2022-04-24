output "vpc_id" {
  description = "ID of the VPC created as part of the example."
  value       = module.vpc_app.vpc_id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster resource that is created."
  value       = module.eks_cluster.eks_cluster_name
}

output "eks_cluster_arn" {
  description = "AWS ARN identifier of the EKS cluster resource that is created."
  value       = module.eks_cluster.eks_cluster_arn
}

output "eks_worker_iam_role_arn" {
  description = "AWS ARN identifier of the IAM role created for the EKS worker nodes."
  value       = module.eks_workers.eks_worker_iam_role_arn
}

output "eks_fargate_default_execution_role_arn" {
  description = "AWS ARN identifier of the IAM role created for EKS Fargate nodes."
  value       = module.eks_cluster.eks_default_fargate_execution_role_arn
}

output "example_iam_role_arn" {
  description = "AWS ARN of the example IAM role created in the example."
  value       = aws_iam_role.example.arn
}

output "eks_worker_asg_names" {
  description = "Names of each ASG for the EKS worker nodes."
  value       = module.eks_workers.eks_worker_asg_names
}
