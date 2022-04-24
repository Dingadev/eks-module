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
  service_account_name = "aws-alb-ingress-controller"
  chart_namespace      = var.namespace
  release_name         = "aws-alb-ingress-controller"
  chart_name           = "aws-load-balancer-controller"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY AWS ALB INGRESS CONTROLLER
# Use helm to deploy the aws-alb-ingress-controller incubator chart.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "aws_alb_ingress_controller" {
  # Due to a bug in the helm provider in repository management, it is more stable to use the repository URL directly.
  # See https://github.com/terraform-providers/terraform-provider-helm/issues/416#issuecomment-598828730 for more
  # information.
  repository = "https://aws.github.io/eks-charts"
  name       = local.release_name
  chart      = local.chart_name
  version    = var.chart_version
  namespace  = local.chart_namespace

  values = [yamlencode(local.values)]

  depends_on = [
    null_resource.dependency_getter,
    aws_eks_fargate_profile.alb_ingress,
  ]
}

locals {
  values = merge(
    (
      var.enable_restricted_sg_rules
      ? {
        disableRestrictedSecurityGroupRules = false
      }
      : {
        disableRestrictedSecurityGroupRules = true
      }
    ),
    {
      clusterName = var.eks_cluster_name
      region      = var.aws_region
      vpcId       = var.vpc_id
      image = {
        repository = var.docker_image_repo
        tag        = var.docker_image_tag
      }
      replicaCount = var.pod_replica_count

      rbac = {
        create = true
      }
      serviceAccount = {
        create = true
        name   = local.service_account_name
        annotations = (
          local.use_iam_role_for_service_accounts
          ? {
            "eks.amazonaws.com/role-arn" = aws_iam_role.alb_ingress[0].arn
          }
          : {}
        )
      }

      podLabels      = var.pod_labels
      podAnnotations = var.pod_annotations
      tolerations    = var.pod_tolerations
      affinity = (
        length(var.pod_node_affinity) > 0
        ? {
          nodeAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = {
              nodeSelectorTerms = [
                {
                  matchExpressions = var.pod_node_affinity
                }
              ]
            }
          }
        }
        : {}
      )
    },
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE IAM ROLE FOR SERVICE ACCOUNT
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "alb_ingress" {
  count              = local.use_iam_role_for_service_accounts ? 1 : 0
  name               = "${var.eks_cluster_name}-alb-ingress"
  assume_role_policy = module.service_account_assume_role_policy.assume_role_policy_json
  depends_on = [
    null_resource.dependency_getter,
  ]
}

resource "aws_iam_role_policy_attachment" "alb_ingress" {
  count      = local.use_iam_role_for_service_accounts ? 1 : 0
  policy_arn = module.alb_ingress_iam_policy.alb_ingress_controller_policy_arn
  role       = local.use_iam_role_for_service_accounts ? aws_iam_role.alb_ingress[0].name : null
}

module "alb_ingress_iam_policy" {
  source           = "../eks-alb-ingress-controller-iam-policy"
  create_resources = local.use_iam_role_for_service_accounts
  name_prefix      = var.eks_cluster_name
}

module "service_account_assume_role_policy" {
  source = "../eks-iam-role-assume-role-policy-for-service-account"

  eks_openid_connect_provider_arn = local.eks_openid_connect_provider_arn
  eks_openid_connect_provider_url = local.eks_openid_connect_provider_url
  namespaces                      = []
  service_accounts = [{
    name      = local.service_account_name
    namespace = local.chart_namespace
  }]
}

locals {
  use_iam_role_for_service_accounts = var.iam_role_for_service_accounts_config != null
  eks_openid_connect_provider_arn   = local.use_iam_role_for_service_accounts ? var.iam_role_for_service_accounts_config.openid_connect_provider_arn : ""
  eks_openid_connect_provider_url   = local.use_iam_role_for_service_accounts ? var.iam_role_for_service_accounts_config.openid_connect_provider_url : ""
}


# ---------------------------------------------------------------------------------------------------------------------
# CREATE FARGATE PROFILE AND EXECUTION ROLE IF REQUESTED
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_eks_fargate_profile" "alb_ingress" {
  count                  = var.create_fargate_profile ? 1 : 0
  cluster_name           = var.eks_cluster_name
  fargate_profile_name   = "alb-ingress-controller"
  pod_execution_role_arn = local.create_fargate_execution_role ? aws_iam_role.alb_ingress_fargate_role[0].arn : var.pod_execution_iam_role_arn
  subnet_ids             = var.vpc_worker_subnet_ids

  selector {
    namespace = local.chart_namespace
    labels = {
      "app.kubernetes.io/name"     = local.release_name
      "app.kubernetes.io/instance" = local.chart_name
    }
  }

  depends_on = [
    null_resource.dependency_getter,
  ]
}

resource "aws_iam_role" "alb_ingress_fargate_role" {
  count              = local.create_fargate_execution_role ? 1 : 0
  name               = "${var.eks_cluster_name}-albingress-fargate-execution-role"
  assume_role_policy = data.aws_iam_policy_document.allow_fargate_to_assume_role.json
}

resource "aws_iam_role_policy_attachment" "base_fargate_policy" {
  count      = local.create_fargate_execution_role ? 1 : 0
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = local.create_fargate_execution_role ? aws_iam_role.alb_ingress_fargate_role[0].name : null
}

data "aws_iam_policy_document" "allow_fargate_to_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
  }
}

locals {
  create_fargate_execution_role = var.create_fargate_profile && (var.pod_execution_iam_role_arn == null)
}
