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
  service_account_name = "external-dns"
  chart_namespace      = var.namespace
  release_name         = var.release_name
  chart_name           = "external-dns"
}


# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY K8S EXTERNAL DNS
# Use helm to deploy the external-dns chart.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "k8s_external_dns" {
  # Due to a bug in the helm provider in repository management, it is more stable to use the repository URL directly.
  # See https://github.com/terraform-providers/terraform-provider-helm/issues/416#issuecomment-598828730 for more
  # information.
  repository = "https://charts.bitnami.com/bitnami"
  name       = local.release_name
  chart      = local.chart_name
  version    = var.external_dns_chart_version
  namespace  = local.chart_namespace

  values = [yamlencode(local.helm_chart_input)]

  depends_on = [
    aws_eks_fargate_profile.external_dns,
    null_resource.dependency_getter,
  ]
}

locals {
  # We use `merge` to merge in optional fields conditionally. That is, if a field should be omitted due to conditional
  # logic, it will resolve to `{}` so that the attribute is not included in the final input.
  helm_chart_input = merge(
    local.maybe_endpoints_namespace,
    local.maybe_node_affinity,
    {
      podLabels      = var.pod_labels
      podAnnotations = var.pod_annotations
      tolerations    = var.pod_tolerations

      provider = "aws"
      aws = {
        region = var.aws_region
      }
      policy             = var.route53_record_update_policy
      domainFilters      = var.route53_hosted_zone_domain_filters
      zoneIdFilters      = var.route53_hosted_zone_id_filters
      txtOwnerId         = var.txt_owner_id
      logFormat          = var.log_format
      triggerLoopOnEvent = var.trigger_loop_on_event

      sources = var.sources

      serviceAccount = {
        create = true

        # Annotate the service account with the IAM role to use for managing Route 53 when using IRSA
        annotations = merge(
          local.use_iam_role_for_service_accounts
          ? {
            "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns[0].arn
          }
          : {},
          var.service_account_annotations,
        )
      }

      extraArgs = (
        local.zone_tag_filters != ""
        ? {
          "aws-zone-tags" = local.zone_tag_filters
        }
        : {}
      )
    },
  )

  maybe_endpoints_namespace = (
    var.endpoints_namespace == null
    ? {}
    : {
      namespace = var.endpoints_namespace
    }
  )

  node_affinity_expression = {
    nodeAffinity = {
      requiredDuringSchedulingIgnoredDuringExecution = {
        nodeSelectorTerms = [{
          matchExpressions = var.pod_node_affinity
        }]
      }
    }
  }
  maybe_node_affinity = (
    length(var.pod_node_affinity) > 0
    ? {
      affinity = local.node_affinity_expression
    }
    : {
      affinity = {}
    }
  )
}

# Convert list of maps to a CSV of the format key=value by using a for expression to construct the formatted value.
locals {
  zone_tag_filters = join(
    ",",
    [for tag in var.route53_hosted_zone_tag_filters : "${tag.key}=${tag.value}"],
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE IAM ROLE FOR SERVICE ACCOUNT
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "external_dns" {
  count              = local.use_iam_role_for_service_accounts ? 1 : 0
  name               = "${local.name_prefix}-${var.release_name}"
  assume_role_policy = module.service_account_assume_role_policy.assume_role_policy_json
  depends_on = [
    null_resource.dependency_getter,
  ]
}

resource "aws_iam_role_policy_attachment" "external_dns_policy_attachment" {
  count      = local.use_iam_role_for_service_accounts ? 1 : 0
  policy_arn = module.k8s_external_dns_iam_policy.k8s_external_dns_policy_arn
  role       = local.use_iam_role_for_service_accounts ? aws_iam_role.external_dns[0].name : null
}

module "k8s_external_dns_iam_policy" {
  source           = "../eks-k8s-external-dns-iam-policy"
  create_resources = local.use_iam_role_for_service_accounts
  name_prefix      = local.name_prefix
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
  name_prefix                       = var.eks_cluster_name != "" && var.eks_cluster_name != null ? var.eks_cluster_name : "eks"
  use_iam_role_for_service_accounts = var.iam_role_for_service_accounts_config != null
  eks_openid_connect_provider_arn   = local.use_iam_role_for_service_accounts ? var.iam_role_for_service_accounts_config.openid_connect_provider_arn : ""
  eks_openid_connect_provider_url   = local.use_iam_role_for_service_accounts ? var.iam_role_for_service_accounts_config.openid_connect_provider_url : ""
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE FARGATE PROFILE AND EXECUTION ROLE IF REQUESTED
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_eks_fargate_profile" "external_dns" {
  count                  = var.create_fargate_profile ? 1 : 0
  cluster_name           = var.eks_cluster_name
  fargate_profile_name   = "external-dns"
  pod_execution_role_arn = local.create_fargate_execution_role ? aws_iam_role.external_dns_fargate_role[0].arn : var.pod_execution_iam_role_arn
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

resource "aws_iam_role" "external_dns_fargate_role" {
  count              = local.create_fargate_execution_role ? 1 : 0
  name               = "${var.eks_cluster_name}-externaldns-fargate-execution-role"
  assume_role_policy = data.aws_iam_policy_document.allow_fargate_to_assume_role.json
}

resource "aws_iam_role_policy_attachment" "base_fargate_policy" {
  count      = local.create_fargate_execution_role ? 1 : 0
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = local.create_fargate_execution_role ? aws_iam_role.external_dns_fargate_role[0].name : null
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
