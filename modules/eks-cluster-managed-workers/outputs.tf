output "eks_worker_iam_role_arn" {
  description = "AWS ARN identifier of the IAM role created for the EKS worker nodes."
  value       = local.iam_role_arn

  # Add depends_on logic to ensure this is only returned if the IAM role is ready
  depends_on = [
    aws_iam_role_policy_attachment.worker_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.worker_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.worker_AmazonEC2ContainerRegistryReadOnly,
  ]
}

output "eks_worker_iam_role_name" {
  description = "Name of the IAM role created for the EKS worker nodes."
  value       = local.iam_role_name

  # Add depends_on logic to ensure this is only returned if the IAM role is ready
  depends_on = [
    aws_iam_role_policy_attachment.worker_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.worker_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.worker_AmazonEC2ContainerRegistryReadOnly,
  ]
}

output "eks_worker_asg_names" {
  description = "Map of Node Group names to Auto Scaling Group names"
  value = {
    for name, obj in aws_eks_node_group.eks_worker :
    name => flatten([
      for r in obj.resources :
      [for asg in r.autoscaling_groups : asg.name]
    ])
  }
}

output "eks_worker_node_group_arns" {
  description = "Map of Node Group names to ARNs of the created EKS Node Groups"
  value = {
    for name, obj in aws_eks_node_group.eks_worker :
    name => obj.arn
  }
}

output "eks_worker_asg_security_group_ids" {
  description = "Map of Node Group names to Auto Scaling Group security group IDs. Empty if var.cluster_instance_keypair_name is not set."
  value = {
    for name, obj in aws_eks_node_group.eks_worker :
    name => compact([
      for r in obj.resources :
      r.remote_access_security_group_id
    ])
  }
}
