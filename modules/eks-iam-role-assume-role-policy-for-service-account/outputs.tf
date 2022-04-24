output "assume_role_policy_json" {
  description = "JSON value for IAM Role Assume Role Policy that allows Kubernetes Service Account to inherit IAM Role."
  value       = data.aws_iam_policy_document.eks_assume_role_policy.json
}
