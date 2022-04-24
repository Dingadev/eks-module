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
  service_account_name = "aws-for-fluent-bit"
  chart_namespace      = "kube-system"
  release_name         = "aws-for-fluent-bit"
  chart_name           = "aws-for-fluent-bit"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY AWS FOR FLUENT BIT
# Use helm to deploy the aws-for-fluent-bit EKS chart.
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "aws_for_fluent_bit" {
  repository = "https://aws.github.io/eks-charts"
  name       = local.release_name
  chart      = local.chart_name
  version    = var.aws_for_fluent_bit_chart_version
  namespace  = local.chart_namespace

  values = [yamlencode(local.chart_values)]

  depends_on = [
    null_resource.dependency_getter,
  ]
}

locals {
  # Annotate the service account with the IAM role to use for accessing CloudWatch Logs when using IRSA
  service_account_annotations = (
    local.use_iam_role_for_service_accounts
    ? {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_for_fluent_bit[0].arn
    }
    : {}
  )

  disable_json = jsonencode({ enabled = false })

  # Translate input variables to configurations for the helm chart. It is necessary to use json as an intermediary
  # representation to avoid terraform type coercion. That is, if terraform decides to turn this into a `map` type as
  # opposed to `object` type, then the bools get converted to strings.
  cloudwatch_configuration_raw = (
    var.cloudwatch_configuration != null
    ? jsonencode({
      enabled         = true
      autoCreateGroup = true
      region          = var.cloudwatch_configuration.region
      logGroupName    = var.cloudwatch_configuration.log_group_name
      logStreamPrefix = var.cloudwatch_configuration.log_stream_prefix
    })
    : local.disable_json
  )
  firehose_configuration_raw = (
    var.firehose_configuration != null
    ? jsonencode({
      enabled        = true
      region         = var.firehose_configuration.region
      deliveryStream = var.firehose_configuration.delivery_stream_name
    })
    : local.disable_json
  )
  kinesis_configuration_raw = (
    var.kinesis_configuration != null
    ? jsonencode({
      enabled = true
      region  = var.kinesis_configuration.region
      stream  = var.kinesis_configuration.stream_name
    })
    : local.disable_json
  )
  aws_elasticsearch_configuration_raw = (
    var.aws_elasticsearch_configuration != null
    ? jsonencode({
      enabled   = true
      match     = var.aws_elasticsearch_configuration.match
      awsRegion = var.aws_elasticsearch_configuration.region
      awsAuth   = var.aws_elasticsearch_configuration.use_aws_auth ? "On" : "Off"
      tls       = var.aws_elasticsearch_configuration.use_tls ? "On" : "Off"
      host      = var.aws_elasticsearch_configuration.endpoint.host
      port      = tostring(var.aws_elasticsearch_configuration.endpoint.port)
    })
    : local.disable_json
  )

  # Filter out anything set to null so that we can use the chart default.
  cloudwatch_configuration = jsonencode({
    for key, value in jsondecode(local.cloudwatch_configuration_raw) : key => value
    if value != null
  })
  firehose_configuration = jsonencode({
    for key, value in jsondecode(local.firehose_configuration_raw) : key => value
    if value != null
  })
  kinesis_configuration = jsonencode({
    for key, value in jsondecode(local.kinesis_configuration_raw) : key => value
    if value != null
  })
  aws_elasticsearch_configuration = jsonencode({
    for key, value in jsondecode(local.aws_elasticsearch_configuration_raw) : key => value
    if value != null
  })

  # Image configuration
  aws_for_fluent_bit_image_config = merge(
    (
      var.aws_for_fluent_bit_version != null
      ? {
        tag = var.aws_for_fluent_bit_version
      }
      : {}
    ),
    (
      var.aws_for_fluent_bit_image_repository != null
      ? {
        repository = var.aws_for_fluent_bit_image_repository
      }
      : {}
    ),
  )

  # We use merge to conditionally override the resources parameter only if the user provides it in the variables.
  chart_values = merge(
    {
      serviceAccount = {
        create      = true
        annotations = local.service_account_annotations
      }

      cloudWatch    = jsondecode(local.cloudwatch_configuration)
      firehose      = jsondecode(local.firehose_configuration)
      kinesis       = jsondecode(local.kinesis_configuration)
      elasticsearch = jsondecode(local.aws_elasticsearch_configuration)
      extraOutputs  = var.extra_outputs
      extraFilters  = var.extra_filters

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
      length(local.aws_for_fluent_bit_image_config) > 0
      ? {
        image = local.aws_for_fluent_bit_image_config
      }
      : {}
    ),
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE IAM ROLE FOR SERVICE ACCOUNT
# Depending on the configuration, the Fluent Bit Pod needs to access CloudWatch Logs, Kinesis, or Kinesis Firehose.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "aws_for_fluent_bit" {
  count              = local.use_iam_role_for_service_accounts ? 1 : 0
  name               = "${local.irsa_name_prefix}-fluent-bit-cloudwatch"
  assume_role_policy = module.service_account_assume_role_policy.assume_role_policy_json
  depends_on = [
    null_resource.dependency_getter,
  ]
}

resource "aws_iam_role_policy" "firehose" {
  count = (
    local.use_iam_role_for_service_accounts && var.firehose_configuration != null && local.use_inline_policies
    ? 1 : 0
  )
  role   = aws_iam_role.aws_for_fluent_bit[0].name
  policy = data.aws_iam_policy_document.firehose.json
}

resource "aws_iam_policy" "firehose" {
  count = (
    local.use_iam_role_for_service_accounts && var.firehose_configuration != null && var.use_managed_iam_policies
    ? 1 : 0
  )
  name_prefix = "allow-output-to-firehose"
  policy      = data.aws_iam_policy_document.firehose.json
}

resource "aws_iam_role_policy_attachment" "firehose" {
  count = (
    local.use_iam_role_for_service_accounts && var.firehose_configuration != null && var.use_managed_iam_policies
    ? 1 : 0
  )
  role       = aws_iam_role.aws_for_fluent_bit[0].name
  policy_arn = aws_iam_policy.firehose[0].arn
}

data "aws_iam_policy_document" "firehose" {
  statement {
    actions = ["firehose:PutRecordBatch"]
    resources = compact([
      (
        var.firehose_configuration != null
        ? "arn:${var.aws_partition}:firehose:${var.firehose_configuration.region}:${data.aws_caller_identity.current.account_id}:deliverystream/${var.firehose_configuration.delivery_stream_name}"
        : null
      )
    ])
  }
}

resource "aws_iam_role_policy" "kinesis" {
  count = (
    local.use_iam_role_for_service_accounts && var.kinesis_configuration != null && local.use_inline_policies
    ? 1 : 0
  )
  role   = aws_iam_role.aws_for_fluent_bit[0].name
  policy = data.aws_iam_policy_document.kinesis.json
}

resource "aws_iam_policy" "kinesis" {
  count = (
    local.use_iam_role_for_service_accounts && var.kinesis_configuration != null && var.use_managed_iam_policies
    ? 1 : 0
  )
  name_prefix = "allow-output-to-kinesis"
  policy      = data.aws_iam_policy_document.kinesis.json
}

resource "aws_iam_role_policy_attachment" "kinesis" {
  count = (
    local.use_iam_role_for_service_accounts && var.kinesis_configuration != null && var.use_managed_iam_policies
    ? 1 : 0
  )
  role       = aws_iam_role.aws_for_fluent_bit[0].name
  policy_arn = aws_iam_policy.kinesis[0].arn
}

data "aws_iam_policy_document" "kinesis" {
  statement {
    actions = ["kinesis:PutRecords"]
    resources = compact([
      (
        var.kinesis_configuration != null
        ? "arn:${var.aws_partition}:kinesis:${var.kinesis_configuration.region}:${data.aws_caller_identity.current.account_id}:stream/${var.kinesis_configuration.stream_name}"
        : null
      )
    ])
  }
}

resource "aws_iam_role_policy" "cloudwatch" {
  count  = local.use_iam_role_for_service_accounts && local.use_inline_policies ? 1 : 0
  name   = "allow-publish-cloudwatch-logs"
  role   = aws_iam_role.aws_for_fluent_bit[0].name
  policy = module.cloudwatch_log_aggregation_iam_policy.cloudwatch_logs_permissions_json
}

resource "aws_iam_policy" "cloudwatch" {
  count       = local.use_iam_role_for_service_accounts && var.use_managed_iam_policies ? 1 : 0
  name_prefix = "allow-publish-cloudwatch-logs"
  policy      = module.cloudwatch_log_aggregation_iam_policy.cloudwatch_logs_permissions_json
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count      = local.use_iam_role_for_service_accounts && var.use_managed_iam_policies ? 1 : 0
  role       = aws_iam_role.aws_for_fluent_bit[0].name
  policy_arn = aws_iam_policy.cloudwatch[0].arn
}

module "cloudwatch_log_aggregation_iam_policy" {
  source           = "git::git@github.com:gruntwork-io/terraform-aws-monitoring.git//modules/logs/cloudwatch-log-aggregation-iam-policy?ref=v0.21.2"
  create_resources = false
  name_prefix      = local.irsa_name_prefix
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
  irsa_name_prefix                  = var.iam_role_name_prefix != "" && var.iam_role_name_prefix != null ? var.iam_role_name_prefix : "eks"
  use_iam_role_for_service_accounts = var.iam_role_for_service_accounts_config != null
  eks_openid_connect_provider_arn   = local.use_iam_role_for_service_accounts ? var.iam_role_for_service_accounts_config.openid_connect_provider_arn : ""
  eks_openid_connect_provider_url   = local.use_iam_role_for_service_accounts ? var.iam_role_for_service_accounts_config.openid_connect_provider_url : ""
}

data "aws_caller_identity" "current" {}
