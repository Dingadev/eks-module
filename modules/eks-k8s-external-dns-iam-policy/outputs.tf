output "k8s_external_dns_policy_name" {
  description = "The name of the IAM policy created with the permissions for the external-dns Kubernetes app."
  value       = var.create_resources ? aws_iam_policy.k8s_external_dns[0].name : null
}

output "k8s_external_dns_policy_id" {
  description = "The AWS ID of the IAM policy created with the permissions for the external-dns Kubernetes app."
  value       = var.create_resources ? aws_iam_policy.k8s_external_dns[0].id : null
}

output "k8s_external_dns_policy_arn" {
  description = "The ARN of the IAM policy created with the permissions for the external-dns Kubernetes app."
  value       = var.create_resources ? aws_iam_policy.k8s_external_dns[0].arn : null
}
