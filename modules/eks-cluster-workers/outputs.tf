output "eks_worker_security_group_id" {
  description = "AWS ID of the security group created for the EKS worker nodes."
  value       = var.create_resources && length(aws_security_group.eks_worker) > 0 ? aws_security_group.eks_worker[0].id : null
}

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
  value       = local.iam_role_name_for_references

  # Add depends_on logic to ensure this is only returned if the IAM role is ready
  depends_on = [
    aws_iam_role_policy_attachment.worker_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.worker_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.worker_AmazonEC2ContainerRegistryReadOnly,
  ]
}

output "eks_worker_asg_ids" {
  description = "AWS IDs of the auto scaling group for the EKS worker nodes."
  value       = flatten([for e in aws_autoscaling_group.eks_worker : e.*.id])
}

output "eks_worker_asg_names" {
  description = "Names of the auto scaling groups for the EKS worker nodes."
  value       = flatten([for e in aws_autoscaling_group.eks_worker : e.*.name])
}

output "eks_worker_asg_arns" {
  description = "AWS ARNs of the auto scaling groups for the EKS worker nodes."
  value       = flatten([for e in aws_autoscaling_group.eks_worker : e.*.arn])
}
