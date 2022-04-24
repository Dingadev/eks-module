# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# IAM ROLE: ASSUME ROLE POLICY FOR SERVICE ACCOUNT
# This module creates a policy document that allows Kubernetes Namespaces or Service Accounts to assume the IAM role
# attached to the module. If neither Namespaces nor Service Accounts are provided, the created policy allows all to
# assume the IAM role.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM REQUIREMENTS FOR RUNNING THIS MODULE
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

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEFINE POLICY STATEMENT FOR EKS ASSUME ROLE TO ALLOW IAM ROLE FOR SERVICE ACCOUNT USE
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

data "aws_iam_policy_document" "eks_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      identifiers = [var.eks_openid_connect_provider_arn]
      type        = "Federated"
    }

    # When both `var.service_accounts` and `var.namespaces` are empty lists, both condition blocks are dropped. This
    # will in turn allow all namespaces and all service accounts. Note that it isn't necessary to add a further
    # condition field here because the policy is already restricted to federated access from the given OpenID connect
    # provider (by the principals block).

    # Allow if any one of the service accounts, but only add in the condition if user specified service accounts in the
    # input list.
    dynamic "condition" {
      # The string for the `for_each` key doesn't matter in this case, since we are using it to determine if this block
      # should be included or not.
      for_each = length(var.service_accounts) > 0 ? ["has-service-accounts"] : []

      content {
        test     = var.service_accounts_condition_operator
        variable = "${replace(var.eks_openid_connect_provider_url, "https://", "")}:sub"
        values   = [for service_account in var.service_accounts : "system:serviceaccount:${service_account.namespace}:${service_account.name}"]
      }
    }

    # Allow if a service account in any one of the namespaces, but only add in the condition if user specified
    # namespaces in the input list.
    dynamic "condition" {
      # The string for the `for_each` key doesn't matter in this case, since we are using it to determine if this block
      # should be included or not.
      for_each = length(var.namespaces) > 0 ? ["has-namespaces"] : []

      content {
        test     = "StringLike"
        variable = "${replace(var.eks_openid_connect_provider_url, "https://", "")}:sub"
        values   = [for namespace in var.namespaces : "system:serviceaccount:${namespace}:*"]
      }
    }
  }
}
