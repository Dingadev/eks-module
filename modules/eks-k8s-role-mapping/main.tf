# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# MAP AWS IAM ROLES TO KUBERNETES RBAC GROUPS
# These templates create the `aws-auth` ConfigMap in the configured Kubernetes cluster so that IAM roles or users can be
# mapped to Kubernetes RBAC groups.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM REQUIREMENTS FOR RUNNING THIS MODULE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "< 4.0"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE aws-auth CONFIGMAP
# The `aws-auth` ConfigMap is a singleton resource in Kubernetes that is used to lookup mappings between AWS IAM
# users/roles and Kubernetes RBAC groups.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_config_map" "eks_to_k8s_role_mapping" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = var.config_map_labels
  }

  data = {
    mapRoles = yamlencode(concat(local.worker_node_mappings, local.fargate_role_mappings, local.iam_role_mappings))
    mapUsers = yamlencode(local.iam_user_mappings)
  }
}

locals {
  worker_node_mappings = [
    for arn in var.eks_worker_iam_role_arns :
    {
      rolearn  = arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    }
  ]
  fargate_role_mappings = [
    for arn in var.eks_fargate_profile_executor_iam_role_arns :
    {
      rolearn  = arn
      username = "system:node:{{SessionName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
        "system:node-proxier",
      ]
    }
  ]
  iam_role_mappings = [
    for arn, groups in var.iam_role_to_rbac_group_mappings :
    {
      rolearn = arn
      groups  = groups

      # Use a RegEx (https://www.terraform.io/docs/configuration/functions/replace.html) that
      # takes a value like "arn:aws:iam::123456789012:role/S3Access" and looks for the string after the last "/".
      username = replace(arn, "/.*/(.*)/", "$1")
    }
  ]
  iam_user_mappings = [
    for arn, groups in var.iam_user_to_rbac_group_mappings :
    {
      userarn = arn
      groups  = groups

      # Use a RegEx (https://www.terraform.io/docs/configuration/functions/replace.html) that
      # takes a value like "arn:aws:iam::123456789012:role/S3Access" and looks for the string after the last "/".
      username = replace(arn, "/.*/(.*)/", "$1")
    }
  ]
}
