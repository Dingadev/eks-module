# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM RUNTIME REQUIREMENTS
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"

  required_providers {
    helm = "~> 2.0"
    aws = {
      source  = "hashicorp/aws"
      version = "< 4.0"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# SET MODULE DEPENDENCY RESOURCE
# This works around a terraform limitation where we can not specify module dependencies natively.
# See https://github.com/hashicorp/terraform/issues/1178 for more discussion.
# By resolving and computing the dependencies list, we are able to make all the resources in this module depend on the
# resources backing the values in the dependencies list.
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "dependency_getter" {
  provisioner "local-exec" {
    command = "echo ${length(var.dependencies)}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CONSTANTS USED THROUGHOUT MODULE
# ---------------------------------------------------------------------------------------------------------------------

locals {
  service_account_name = "aws-cloudwatch-agent"
  release_name         = "aws-cloudwatch-agent"
  chart_name           = "aws-cloudwatch-metrics"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY AWS CLOUDWATCH AGENT
# Use helm to deploy the aws-cloudwatch-metrics EKS chart.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "aws_cloudwatch_metrics" {
  repository = "https://aws.github.io/eks-charts"
  name       = local.release_name
  chart      = local.chart_name
  version    = var.aws_cloudwatch_metrics_chart_version
  namespace  = var.namespace

  values = [yamlencode(local.chart_values)]

  depends_on = [
    null_resource.dependency_getter,
  ]
}

locals {
  # Annotate the service account with the IAM role to use for accessing CloudWatch when using IRSA
  service_account_annotations = (
    local.use_iam_role_for_service_accounts
    ? {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_cloudwatch_agent[0].arn
    }
    : {}
  )

  # Image configuration
  aws_cloudwatch_agent_image_config = merge(
    (
      var.aws_cloudwatch_agent_version != null
      ? {
        tag = var.aws_cloudwatch_agent_version
      }
      : {}
    ),
    (
      var.aws_cloudwatch_agent_image_repository != null
      ? {
        repository = var.aws_cloudwatch_agent_image_repository
      }
      : {}
    ),
  )

  # We use merge to conditionally override the resources parameter only if the user provides it in the variables.
  chart_values = merge(
    {
      clusterName = var.eks_cluster_name

      serviceAccount = {
        create      = true
        name        = local.service_account_name
        annotations = local.service_account_annotations
      }

      affinity = (
        length(var.pod_node_affinity) > 0
        ? {
          nodeAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = {
              nodeSelectorTerms = [{
                matchExpressions = var.pod_node_affinity
              }]
            }
          }
        }
        : {}
      )

      tolerations = var.pod_tolerations
    },
    (
      var.pod_resources != null
      ? {
        resources = var.pod_resources
      }
      : {}
    ),
    (
      length(local.aws_cloudwatch_agent_image_config) > 0
      ? {
        image = local.aws_cloudwatch_agent_image_config
      }
      : {}
    ),
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE IAM ROLE FOR SERVICE ACCOUNT
# The CloudWatch Agent Pod needs to access CloudWatch Metrics.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "aws_cloudwatch_agent" {
  count              = local.use_iam_role_for_service_accounts ? 1 : 0
  name               = "${local.irsa_name_prefix}-cloudwatch-agent"
  assume_role_policy = module.service_account_assume_role_policy.assume_role_policy_json
  depends_on = [
    null_resource.dependency_getter,
  ]
}

module "service_account_assume_role_policy" {
  source = "../eks-iam-role-assume-role-policy-for-service-account"

  eks_openid_connect_provider_arn = local.eks_openid_connect_provider_arn
  eks_openid_connect_provider_url = local.eks_openid_connect_provider_url
  namespaces                      = []
  service_accounts = [{
    name      = local.service_account_name
    namespace = var.namespace
  }]
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server" {
  count      = local.use_iam_role_for_service_accounts ? 1 : 0
  role       = aws_iam_role.aws_cloudwatch_agent[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

locals {
  irsa_name_prefix                  = var.iam_role_name_prefix != "" && var.iam_role_name_prefix != null ? var.iam_role_name_prefix : "eks"
  use_iam_role_for_service_accounts = var.iam_role_for_service_accounts_config != null
  eks_openid_connect_provider_arn   = local.use_iam_role_for_service_accounts ? var.iam_role_for_service_accounts_config.openid_connect_provider_arn : ""
  eks_openid_connect_provider_url   = local.use_iam_role_for_service_accounts ? var.iam_role_for_service_accounts_config.openid_connect_provider_url : ""
}

data "aws_caller_identity" "current" {}
