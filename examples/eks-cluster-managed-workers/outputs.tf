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

output "eks_worker_iam_role_arn" {
  description = "AWS ARN identifier of the IAM role created for the EKS worker nodes."
  value       = module.eks_workers.eks_worker_iam_role_arn
}

output "eks_worker_asg_names" {
  description = "Map of Node Group names to Auto Scaling Group names"
  value       = module.eks_workers.eks_worker_asg_names
}

output "eks_worker_node_group_arns" {
  description = "Map of Node Group names to ARNs of the created EKS Node Groups"
  value       = module.eks_workers.eks_worker_node_group_arns
}

output "eks_worker_asg_security_group_ids" {
  description = "Map of Node Group names to Auto Scaling Group security group IDs. Empty if var.cluster_instance_keypair_name is not set."
  value       = module.eks_workers.eks_worker_asg_security_group_ids
}

output "eks_worker_launch_template_id" {
  description = "If the node group was configured with launch templates, return the ID of the launch template that was created for it."
  value = (
    length(aws_launch_template.template) > 0
    ? aws_launch_template.template[0].id
    : null
  )
}

output "eks_cluster_addons" {
  description = "Map of attribute maps for enabled EKS cluster addons"
  value       = module.eks_cluster.eks_cluster_addons
}

output "bastion_host_ip" {
  description = "Public IP of the bastion host you can use to access the worker nodes over SSH."
  value       = aws_instance.bastion.public_ip
}
