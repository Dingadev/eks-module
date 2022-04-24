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

variable "eks_cluster_name" {
  description = "Name of the EKS cluster where resources are deployed to."
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "namespace" {
  description = "Namespace to create the resources in."
  type        = string
  default     = "kube-system"
}

variable "iam_role_name_prefix" {
  description = "Used to name IAM roles for the service account. Recommended when var.iam_role_for_service_accounts_config is configured."
  type        = string
  default     = null
}

variable "aws_cloudwatch_metrics_chart_version" {
  description = "The version of the aws-cloudwatch-metrics helm chart to deploy. Note that this is different from the app/container version (use var.aws_cloudwatch_agent_version to control the app/container version)."
  type        = string
  default     = "0.0.6"
}

variable "aws_cloudwatch_agent_version" {
  description = "Which version of amazon/cloudwatch-agent to install. When null, uses the default version set in the chart."
  type        = string
  default     = null
}

variable "aws_cloudwatch_agent_image_repository" {
  description = "The Container repository to use for looking up the cloudwatch-agent Container image when deploying the pods. When null, uses the default repository set in the chart."
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
  description = "Specify the resource limits and requests for the cloudwatch-agent pods. Set to null (default) to use chart defaults."
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
