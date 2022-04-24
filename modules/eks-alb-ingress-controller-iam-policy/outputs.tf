output "alb_ingress_controller_policy_name" {
  description = "The name of the IAM policy created with the permissions for the ALB ingress controller."
  value       = var.create_resources ? aws_iam_policy.alb_ingress_controller[0].name : null
}

output "alb_ingress_controller_policy_id" {
  description = "The AWS ID of the IAM policy created with the permissions for the ALB ingress controller."
  value       = var.create_resources ? aws_iam_policy.alb_ingress_controller[0].id : null
}

output "alb_ingress_controller_policy_arn" {
  description = "The ARN of the IAM policy created with the permissions for the ALB ingress controller."
  value       = var.create_resources ? aws_iam_policy.alb_ingress_controller[0].arn : null
}
