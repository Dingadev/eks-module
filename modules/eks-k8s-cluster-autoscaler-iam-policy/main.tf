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
# CREATE AN IAM POLICY THAT ADDS PERMISSIIONS TO MANAGE EC2 AUTOSCALING
# To use this IAM policy, use an aws_iam_role_policy_attachment resource.
# https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md#permissions
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_policy" "k8s_cluster_autoscaler" {
  count       = var.create_resources ? 1 : 0
  name        = "${var.name_prefix}-k8s-cluster-autoscaler"
  description = "A policy that grants the ability to monitor autoscaling groups and scale up and down their instances."
  policy      = data.aws_iam_policy_document.k8s_cluster_autoscaler.json
}

data "aws_iam_policy_document" "k8s_cluster_autoscaler" {
  statement {
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.eks_worker_asg_arns) > 0 ? ["include"] : []
    content {
      actions = [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
      ]
      resources = var.eks_worker_asg_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.eks_worker_asg_arns) == 0 ? ["include"] : []
    content {
      actions = [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
      ]
      resources = ["*"]
      condition {
        test     = "Null"
        values   = ["false"]
        variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.name_prefix}"
      }
    }
  }
}
