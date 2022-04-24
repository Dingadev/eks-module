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
# CREATE AN IAM POLICY THAT ADDS PERMISSIONS TO MANAGE ROUTE 53 RECORDS
# To use this IAM policy, use an aws_iam_role_policy_attachment resource.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_policy" "k8s_external_dns" {
  count       = var.create_resources ? 1 : 0
  name        = "${var.name_prefix}-k8s-external-dns"
  description = "A policy that grants the ability to manage Route 53 Records on a Hosted Zone, which is necessary for the external-dns app to function."
  policy      = data.aws_iam_policy_document.policy_for_external_dns.json
}

data "aws_iam_policy_document" "policy_for_external_dns" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListTagsForResource",
    ]

    resources = [
      "arn:${var.aws_partition}:route53:::hostedzone/*",
    ]
  }

  statement {
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
    ]

    resources = ["*"]
  }
}
