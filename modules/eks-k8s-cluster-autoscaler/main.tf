# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM RUNTIME REQUIREMENTS
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    aws = {
      source = "hashicorp/aws"
    }
    null = {
      source = "hashicorp/null"
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
  service_account_name = "cluster-autoscaler-aws-cluster-autoscaler"
  chart_namespace      = var.namespace
  release_name         = var.release_name
  chart_name           = "cluster-autoscaler"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY CLUSTER AUTOSCALER
# Use Helm to deploy the cluster-autoscaler chart.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "k8s_autoscaler" {
  # Due to a bug in the helm provider in repository management, it is more stable to use the repository URL directly.
  # See https://github.com/terraform-providers/terraform-provider-helm/issues/416#issuecomment-598828730 for more
  # information.
  repository = "https://kubernetes.github.io/autoscaler"
  name       = local.release_name
  chart      = local.chart_name
  version    = var.cluster_autoscaler_chart_version
  namespace  = local.chart_namespace

  values = [yamlencode(local.chart_values)]

  depends_on = [
    aws_eks_fargate_profile.cluster_autoscaler,
    null_resource.dependency_getter,
  ]
}

locals {
  # Annotate the service account with the IAM role to use for accessing ASG when using IRSA
  service_account_annotations = (
    local.use_iam_role_for_service_accounts
    ? {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler[0].arn
    }
    : {}
  )

  # We use merge to conditionally override the resources parameter only if the user provides it in the variables.
  chart_values = merge(
    {
      image = {
        repository = var.cluster_autoscaler_repository
        tag        = var.cluster_autoscaler_version
      }

      cloudProvider = "aws"
      awsRegion     = var.aws_region
      autoDiscovery = {
        clusterName = var.eks_cluster_name
      }

      rbac = {
        create = true
        serviceAccount = {
          create      = true
          name        = local.service_account_name
          annotations = local.service_account_annotations
        }
      }

      replicaCount   = var.pod_replica_count
      podLabels      = var.pod_labels
      podAnnotations = var.pod_annotations

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

      expanderPriorities           = var.expander_priorities
      priorityConfigMapAnnotations = var.priority_config_map_annotations

      extraArgs = merge(
        {
          expander                    = var.scaling_strategy
          balance-similar-node-groups = "true"
        },
        var.container_extra_args,
      )
    },
    (
      var.pod_resources != null
      ? {
        resources = var.pod_resources
      }
      : {}
    ),
    (
      var.pod_priority_class_name != null
      ? {
        priorityClassName = var.pod_priority_class_name
      }
      : {}
    ),
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE IAM ROLE FOR SERVICE ACCOUNT
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "cluster_autoscaler" {
  count              = local.use_iam_role_for_service_accounts ? 1 : 0
  name               = "${var.eks_cluster_name}-cluster-autoscaler"
  assume_role_policy = module.service_account_assume_role_policy.assume_role_policy_json
  depends_on = [
    null_resource.dependency_getter,
  ]
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  count      = local.use_iam_role_for_service_accounts ? 1 : 0
  policy_arn = module.k8s_cluster_autoscaler_iam_policy.k8s_cluster_autoscaler_policy_arn
  role       = local.use_iam_role_for_service_accounts ? aws_iam_role.cluster_autoscaler[0].name : null
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

module "k8s_cluster_autoscaler_iam_policy" {
  source              = "../eks-k8s-cluster-autoscaler-iam-policy"
  name_prefix         = var.eks_cluster_name
  create_resources    = local.use_iam_role_for_service_accounts
  eks_worker_asg_arns = var.cluster_autoscaler_absolute_arns ? data.aws_autoscaling_groups.autoscaling_workers.arns : []
}

data "aws_autoscaling_groups" "autoscaling_workers" {
  filter {
    name   = "key"
    values = ["k8s.io/cluster-autoscaler/${var.eks_cluster_name}"]
  }
}

locals {
  use_iam_role_for_service_accounts = var.iam_role_for_service_accounts_config != null
  eks_openid_connect_provider_arn   = local.use_iam_role_for_service_accounts ? var.iam_role_for_service_accounts_config.openid_connect_provider_arn : ""
  eks_openid_connect_provider_url   = local.use_iam_role_for_service_accounts ? var.iam_role_for_service_accounts_config.openid_connect_provider_url : ""
}


# ---------------------------------------------------------------------------------------------------------------------
# CREATE FARGATE PROFILE AND EXECUTION ROLE IF REQUESTED
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_eks_fargate_profile" "cluster_autoscaler" {
  count                = var.create_fargate_profile ? 1 : 0
  cluster_name         = var.eks_cluster_name
  fargate_profile_name = "cluster-autoscaler"
  pod_execution_role_arn = (
    var.create_fargate_execution_role
    ? aws_iam_role.cluster_autoscaler_fargate_role[0].arn
    : var.pod_execution_iam_role_arn
  )
  subnet_ids = var.vpc_worker_subnet_ids

  selector {
    namespace = local.chart_namespace
    labels = {
      "app.kubernetes.io/name"     = "aws-${local.chart_name}"
      "app.kubernetes.io/instance" = local.release_name
    }
  }

  depends_on = [
    null_resource.dependency_getter,
  ]
}

resource "aws_iam_role" "cluster_autoscaler_fargate_role" {
  count              = var.create_fargate_execution_role ? 1 : 0
  name               = "${var.eks_cluster_name}-clusterautoscaler-fargate-execution-role"
  assume_role_policy = data.aws_iam_policy_document.allow_fargate_to_assume_role.json
}

resource "aws_iam_role_policy_attachment" "base_fargate_policy" {
  count      = var.create_fargate_execution_role ? 1 : 0
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = var.create_fargate_execution_role ? aws_iam_role.cluster_autoscaler_fargate_role[0].name : null
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
