# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE FARGATE LOGGING NAMESPACE AND CONFIGURATION
# These templates provision the aws-observability namespace and aws-logging ConfigMap in the EKS cluster.
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
# CONSTANTS USED THROUGHOUT MODULE
# ---------------------------------------------------------------------------------------------------------------------

locals {
  namespace_name = "aws-observability"
  configmap_name = "aws-logging"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE NAMESPACE
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_namespace" "namespace" {
  metadata {
    name = local.namespace_name
    labels = merge(
      {
        aws-observability = "enabled"
      },
      var.namespace_labels
    )
    annotations = var.namespace_annotations
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE fluent-bit CONFIGMAP
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_config_map" "logging" {
  metadata {
    name        = local.configmap_name
    namespace   = kubernetes_namespace.namespace.metadata[0].name
    labels      = var.configmap_labels
    annotations = var.configmap_annotations
  }

  data = merge(
    (
      local.output_conf != ""
      ? {
        "output.conf" = trimspace(local.output_conf)
      }
      : {}
    ),
    (
      local.parser_conf != ""
      ? {
        "parsers.conf" = trimspace(local.parser_conf)
      }
      : {}
    ),
    (
      local.filter_conf != ""
      ? {
        "filters.conf" = trimspace(local.filter_conf)
      }
      : {}
    ),
  )

  depends_on = [
    aws_iam_role_policy.firehose,
    aws_iam_role_policy.kinesis,
    aws_iam_role_policy.cloudwatch,
    aws_iam_role_policy_attachment.firehose,
    aws_iam_role_policy_attachment.kinesis,
    aws_iam_role_policy_attachment.cloudwatch,
  ]
}

locals {
  # Format of OUTPUT blocks are documented in the official fluent-bit docs:
  # https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/configuration-file#config_output
  # Note that Fargate only supports a limited range of outputs. Refer to
  # https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html for list of supported outputs by Fargate.
  output_conf = <<ENDOUTPUTS
%{if var.cloudwatch_configuration != null~}
[OUTPUT]
  Name cloudwatch_logs
  Match   *
  region ${var.cloudwatch_configuration.region}
  log_group_name ${var.cloudwatch_configuration.log_group_name}
%{~if var.cloudwatch_configuration.log_stream_prefix != null}
  log_stream_prefix ${var.cloudwatch_configuration.log_stream_prefix}
%{~endif}
  auto_create_group true
%{~endif}

%{if var.firehose_configuration != null~}
[OUTPUT]
  Name  kinesis_firehose
  Match *
  region ${var.firehose_configuration.region}
  delivery_stream ${var.firehose_configuration.delivery_stream_name}
%{~endif}

%{if var.kinesis_configuration != null~}
[OUTPUT]
  Name  kinesis
  Match *
  region ${var.kinesis_configuration.region}
  stream ${var.kinesis_configuration.stream_name}
%{~endif}

%{if var.aws_elasticsearch_configuration != null~}
[OUTPUT]
  Name  es
  Match ${var.aws_elasticsearch_configuration.match}
  AWS_Region ${var.aws_elasticsearch_configuration.region}
  AWS_Auth ${var.aws_elasticsearch_configuration.use_aws_auth ? "On" : "Off"}
  Host ${var.aws_elasticsearch_configuration.endpoint.host}
  Port ${var.aws_elasticsearch_configuration.endpoint.port}
  TLS ${var.aws_elasticsearch_configuration.use_tls ? "On" : "Off"}
%{endif~}
ENDOUTPUTS

  parser_conf = var.extra_parsers
  filter_conf = var.extra_filters
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH IAM POLICIES FOR OUTPUTS
# Depending on the configuration, the Fluent Bit Pod needs to access CloudWatch Logs, Kinesis, or Kinesis Firehose.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role_policy" "firehose" {
  for_each = var.firehose_configuration != null && local.use_inline_policies ? local.fargate_iam_role_arns_map : {}
  role     = each.value
  policy   = data.aws_iam_policy_document.firehose.json
}

resource "aws_iam_policy" "firehose" {
  count       = var.firehose_configuration != null && var.use_managed_iam_policies ? 1 : 0
  name_prefix = "allow-output-to-firehose"
  policy      = data.aws_iam_policy_document.firehose.json
}

resource "aws_iam_role_policy_attachment" "firehose" {
  for_each   = var.firehose_configuration != null && var.use_managed_iam_policies ? local.fargate_iam_role_arns_map : {}
  role       = each.value
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
  for_each = var.kinesis_configuration != null && local.use_inline_policies ? local.fargate_iam_role_arns_map : {}
  role     = each.value
  policy   = data.aws_iam_policy_document.kinesis.json
}

resource "aws_iam_policy" "kinesis" {
  count       = var.kinesis_configuration != null && var.use_managed_iam_policies ? 1 : 0
  name_prefix = "allow-output-to-kinesis"
  policy      = data.aws_iam_policy_document.kinesis.json
}

resource "aws_iam_role_policy_attachment" "kinesis" {
  for_each   = var.kinesis_configuration != null && var.use_managed_iam_policies ? local.fargate_iam_role_arns_map : {}
  role       = each.value
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
  for_each = var.cloudwatch_configuration != null && local.use_inline_policies ? local.fargate_iam_role_arns_map : {}
  name     = "allow-publish-cloudwatch-logs"
  role     = each.value
  policy   = data.aws_iam_policy_document.cloudwatch.json
}

resource "aws_iam_policy" "cloudwatch" {
  count       = var.cloudwatch_configuration != null && var.use_managed_iam_policies ? 1 : 0
  name_prefix = "allow-publish-cloudwatch-logs"
  policy      = data.aws_iam_policy_document.cloudwatch.json
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  for_each   = var.cloudwatch_configuration != null && var.use_managed_iam_policies ? local.fargate_iam_role_arns_map : {}
  role       = each.value
  policy_arn = aws_iam_policy.cloudwatch[0].arn
}

data "aws_iam_policy_document" "cloudwatch" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:CreateLogGroup",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

locals {
  fargate_iam_role_arns_map = {
    for arn in var.fargate_execution_iam_role_arns :
    # We take the ARN of the IAM role and extract the name. The ARN is in the format
    # arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME , so we use a RegEx to only grab the name by looking for the first element
    # in the path after `role`.
    arn => replace(arn, "/.*role/([^/]+).*/", "$1")
  }
}

data "aws_caller_identity" "current" {}
