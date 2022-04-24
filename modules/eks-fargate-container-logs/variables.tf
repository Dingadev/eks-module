# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

variable "fargate_execution_iam_role_arns" {
  description = "List of ARNs of Fargate execution IAM roles that should have permission to talk to each output target. Policies that grant permissions to each output service will be attached to these IAM roles."
  type        = list(string)
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_partition" {
  description = "The AWS partition used for default AWS Resources."
  type        = string
  default     = "aws"
}

variable "namespace_labels" {
  description = "Labels to associate with the aws-observability Namespace"
  type        = map(string)
  default     = {}
}

variable "namespace_annotations" {
  description = "Annotations to associate with the aws-observability Namespace"
  type        = map(string)
  default     = {}
}

variable "configmap_labels" {
  description = "Labels to associate with the aws-logging ConfigMap"
  type        = map(string)
  default     = {}
}

variable "configmap_annotations" {
  description = "Annotations to associate with the aws-logging ConfigMap"
  type        = map(string)
  default     = {}
}

variable "cloudwatch_configuration" {
  description = "Configurations for forwarding logs to CloudWatch Logs. Set to null if you do not wish to forward the logs to CloudWatch Logs."
  type = object({
    # The AWS region that holds the CloudWatch Log Group where the logs will be streamed to.
    region = string

    # The name of the AWS CloudWatch Log Group to use for all the logs shipped by the cluster.
    log_group_name = string

    # Prefix to append to all CloudWatch Log Streams in the group shipped by fluentbit.
    log_stream_prefix = string
  })
  default = null
}

variable "firehose_configuration" {
  description = "Configurations for forwarding logs to Kinesis Firehose. Set to null if you do not wish to forward the logs to Firehose."
  type = object({
    # The AWS region that holds the Firehose delivery stream.
    region = string

    # The name of the delivery stream you want log records sent to. This must already exist.
    delivery_stream_name = string
  })
  default = null
}

variable "kinesis_configuration" {
  description = "Configurations for forwarding logs to Kinesis stream. Set to null if you do not wish to forward the logs to Kinesis."
  type = object({
    # The AWS region that holds the Kinesis stream.
    region = string

    # The name of the stream you want log records sent to. This must already exist.
    stream_name = string
  })
  default = null
}

variable "aws_elasticsearch_configuration" {
  description = "Configurations for forwarding logs to AWS managed Elasticsearch. Set to null if you do not wish to forward the logs to ES."
  type = object({
    # The AWS region where the Elasticsearch instance is deployed.
    region = string

    # Elasticsearch endpoint to ship logs to.
    endpoint = object({
      host = string
      port = number
    })

    # Whether or not AWS based authentication and authorization is enabled on the Elasticsearch instance.
    use_aws_auth = bool

    # Whether or not TLS is enabled on the Elasticsearch endpoint.
    use_tls = bool

    # Match string for logs to send to Elasticsearch.
    match = string
  })
  default = null
}

# https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/configuration-file#config_filter
# Note that Fargate only supports a limited range of filters. Refer to
# https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html for list of supported filters by Fargate.
variable "extra_filters" {
  description = "Can be used to provide custom filtering of the log output. This string should be formatted according to Fluent Bit docs, as it will be injected directly into the fluent-bit.conf file."
  type        = string
  default     = ""
}

# https://docs.fluentbit.io/manual/pipeline/parsers
# Note that Fargate only supports a limited range of parsers. Refer to
# https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html for list of supported parsers by Fargate.
variable "extra_parsers" {
  description = "Can be used to provide custom parsers of the log output. This string should be formatted according to Fluent Bit docs, as it will be injected directly into the fluent-bit.conf file."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------------------------------------------------
# BACKWARD COMPATIBILITY FEATURE FLAGS
# The following variables are feature flags to enable and disable certain features in the module. These are primarily
# introduced to maintain backward compatibility by avoiding unnecessary resource creation.
# ---------------------------------------------------------------------------------------------------------------------

variable "use_managed_iam_policies" {
  description = "When true, all IAM policies will be managed as dedicated policies rather than inline policies attached to the IAM roles. Dedicated managed policies are friendlier to automated policy checkers, which may scan a single resource for findings. As such, it is important to avoid inline policies when targeting compliance with various security standards."
  type        = bool
  default     = true
}

locals {
  use_inline_policies = var.use_managed_iam_policies == false
}
