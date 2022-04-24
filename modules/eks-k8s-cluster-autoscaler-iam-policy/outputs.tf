output "k8s_cluster_autoscaler_policy_name" {
  description = "The name of the IAM policy created with the permissions for the Kubernetes cluster autoscaler."
  value       = element(concat(aws_iam_policy.k8s_cluster_autoscaler.*.name, [""]), 0)
}

output "k8s_cluster_autoscaler_policy_id" {
  description = "The AWS ID of the IAM policy created with the permissions for the Kubernetes cluster autoscaler."
  value       = element(concat(aws_iam_policy.k8s_cluster_autoscaler.*.id, [""]), 0)
}

output "k8s_cluster_autoscaler_policy_arn" {
  description = "The ARN of the IAM policy created with the permissions for the Kubernetes cluster autoscaler."
  value       = element(concat(aws_iam_policy.k8s_cluster_autoscaler.*.arn, [""]), 0)
}

