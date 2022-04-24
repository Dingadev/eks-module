# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM RUNTIME REQUIREMENTS
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "< 4.0"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN IAM POLICY THAT ADDS ALB INGRESS CONTROLLER PERMISSIONS
# To use this IAM policy, use an aws_iam_role_policy_attachment resource.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_policy" "alb_ingress_controller" {
  count       = var.create_resources ? 1 : 0
  name        = "${var.name_prefix}-alb-ingress-controller"
  description = "A policy that grants the ability to manage ALBs, which is necessary for the ALB Ingress Controller to function."
  policy      = file("${path.module}/iampolicy.json")
}
