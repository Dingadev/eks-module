# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

variable "iam_role_for_service_accounts_config" {
  description = "Configuration for using the IAM role with Service Accounts feature to provide permissions to the helm charts. This expects a map with two properties: `openid_connect_provider_arn` and `openid_connect_provider_url`. The `openid_connect_provider_arn` is the ARN of the OpenID Connect Provider for EKS to retrieve IAM credentials, while `openid_connect_provider_url` is the URL. Set to null if you do not wish to use IAM role with Service Accounts."
  type = object({
    openid_connect_provider_arn = string
    openid_connect_provider_url = string
  })
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

variable "cloudwatch_configuration" {
  description = "Configurations for forwarding logs to CloudWatch Logs. Set to null if you do not wish to forward the logs to CloudWatch Logs."
  type = object({
    # The AWS region that holds the CloudWatch Log Group where the logs will be streamed to.
    region = string

    # The name of the AWS CloudWatch Log Group to use for all the logs shipped by the cluster. Set to null to use chart
    # default (`/aws/eks/fluentbit-cloudwatch/logs`).
    log_group_name = string

    # Prefix to append to all CloudWatch Log Streams in the group shipped by fluentbit. Use "" if you do not with to
    # attach a prefix, or null to use chart default (`fluentbit-`).
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
variable "extra_filters" {
  description = "Can be used to provide custom filtering of the log output. This string should be formatted according to Fluent Bit docs, as it will be injected directly into the fluent-bit.conf file."
  type        = string
  default     = ""
}

# https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/configuration-file#config_output
variable "extra_outputs" {
  description = "Can be used to fan out the log output to multiple additional clients beyond the AWS ones. This string should be formatted according to Fluent Bit docs, as it will be injected directly into the fluent-bit.conf file."
  type        = string
  default     = ""
}

variable "iam_role_name_prefix" {
  description = "Used to name IAM roles for the service account. Recommended when var.iam_role_for_service_accounts_config is configured."
  type        = string
  default     = null
}

variable "aws_for_fluent_bit_chart_version" {
  description = "The version of the aws-for-fluent-bit helm chart to deploy. Note that this is different from the app/container version (use var.aws_for_fluent_bit_version to control the app/container version)."
  type        = string
  default     = "0.1.15"
}

variable "aws_for_fluent_bit_version" {
  description = "Which version of aws-for-fluent-bit to install. When null, uses the default version set in the chart."
  type        = string
  default     = null
}

variable "aws_for_fluent_bit_image_repository" {
  description = "The Container repository to use for looking up the aws-for-fluent-bit Container image when deploying the pods. When null, uses the default repository set in the chart."
  type        = string
  default     = null
}

variable "pod_tolerations" {
  description = "Configure tolerations rules to allow the Pod to schedule on nodes that have been tainted. Each item in the list specifies a toleration rule."
  # Ideally we will use a more concrete type, but since list type requires all the objects to be the same type, using
  # list(any) won't be able to support maps that have different keys and values of different types, so we resort to
  # using any.
  type    = any
  default = []

  # Each item in the list represents a particular toleration. See
  # https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/ for the various rules you can specify.
  #
  # Example:
  #
  # [
  #   {
  #     key = "node.kubernetes.io/unreachable"
  #     operator = "Exists"
  #     effect = "NoExecute"
  #     tolerationSeconds = 6000
  #   }
  # ]
}

# TODO: build an abstraction that keeps the input simple, but still offers full flexibility of affinity.
variable "pod_node_affinity" {
  description = "Configure affinity rules for the Pod to control which nodes to schedule on. Each item in the list should be a map with the keys `key`, `values`, and `operator`, corresponding to the 3 properties of matchExpressions. Note that all expressions must be satisfied to schedule on the node."
  type = list(object({
    key      = string
    values   = list(string)
    operator = string
  }))
  default = []

  # Each item in the list represents a matchExpression for requiredDuringSchedulingIgnoredDuringExecution.
  # https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#affinity-and-anti-affinity for the various
  # configuration option.
  #
  # Example:
  #
  # [
  #   {
  #     "key" = "node-label-key"
  #     "values" = ["node-label-value", "another-node-label-value"]
  #     "operator" = "In"
  #   }
  # ]
  #
  # Translates to:
  #
  # nodeAffinity:
  #   requiredDuringSchedulingIgnoredDuringExecution:
  #     nodeSelectorTerms:
  #     - matchExpressions:
  #       - key: node-label-key
  #         operator: In
  #         values:
  #         - node-label-value
  #         - another-node-label-value
}

variable "pod_resources" {
  description = "Specify the resource limits and requests for the fluent-bit pods. Set to null (default) to use chart defaults."
  # We use type any because this is freeform, as it can be any object accepted by the resources section in the spec. See
  # below for an example.
  type    = any
  default = null

  # This object is passed through to the resources section of a pod spec as described in
  # https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
  # Example:
  #
  # {
  #   requests = {
  #     cpu    = "250m"
  #     memory = "128Mi"
  #   }
  #   limits = {
  #     cpu    = "500m"
  #     memory = "256Mi"
  #   }
  # }
}


# ---------------------------------------------------------------------------------------------------------------------
# MODULE DEPENDENCIES
# Workaround Terraform limitation where there is no module depends_on.
# See https://github.com/hashicorp/terraform/issues/1178 for more details.
# This can be used to make sure the module resources are created after other bootstrapping resources have been created.
# For example, you can pass in "${null_resource.deploy_tiller.id}" to ensure Tiller is deployed and available before
# provisioning the resources in this module.
# ---------------------------------------------------------------------------------------------------------------------

variable "dependencies" {
  description = "Create a dependency between the resources in this module to the interpolated values in this list (and thus the source resources). In other words, the resources in this module will now depend on the resources backing the values in this list such that those resources need to be created before the resources in this module, and the resources in this module need to be destroyed before the resources in the list."
  type        = list(string)
  default     = []
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
