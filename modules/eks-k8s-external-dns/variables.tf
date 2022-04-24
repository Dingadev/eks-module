# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  description = "The AWS region to deploy ALB resources into."
  type        = string
}

variable "aws_partition" {
  description = "The AWS partition used for default AWS Resources."
  type        = string
  default     = "aws"
}

variable "iam_role_for_service_accounts_config" {
  description = "Configuration for using the IAM role with Service Accounts feature to provide permissions to the helm charts. This expects a map with two properties: `openid_connect_provider_arn` and `openid_connect_provider_url`. The `openid_connect_provider_arn` is the ARN of the OpenID Connect Provider for EKS to retrieve IAM credentials, while `openid_connect_provider_url` is the URL. Set to null if you do not wish to use IAM role with Service Accounts, or if you wish to provide an IAM role directly via service_account_annotations."
  type = object({
    openid_connect_provider_arn = string
    openid_connect_provider_url = string
  })
}


# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "namespace" {
  description = "Which Kubernetes Namespace to deploy the chart into."
  type        = string
  default     = "kube-system"
}

variable "release_name" {
  description = "Name of helm release for external-dns. Useful when running 2 deployments for custom configrations such as cross account access."
  type        = string
  default     = "external-dns"
}

variable "route53_record_update_policy" {
  description = "Policy for how DNS records are sychronized between sources and providers (options: sync, upsert-only )."
  type        = string
  default     = "upsert-only"
  # NOTE: external-dns is designed not to touch any records that it has not created, even in sync mode.
  # See https://github.com/kubernetes-incubator/external-dns/blob/master/docs/faq.md#im-afraid-you-will-mess-up-my-dns-records
}

variable "route53_hosted_zone_id_filters" {
  description = "Only create records in hosted zones that match the provided IDs. Empty list (default) means match all zones. Zones must satisfy all three constraints (var.route53_hosted_zone_tag_filters, var.route53_hosted_zone_id_filters, and var.route53_hosted_zone_domain_filters)."
  type        = list(string)
  default     = []
}

variable "route53_hosted_zone_tag_filters" {
  description = "Only create records in hosted zones that match the provided tags. Each item in the list should specify tag key and tag value as a map. Empty list (default) means match all zones. Zones must satisfy all three constraints (var.route53_hosted_zone_tag_filters, var.route53_hosted_zone_id_filters, and var.route53_hosted_zone_domain_filters)."
  type = list(object({
    key   = string
    value = string
  }))
  default = []

  # Example:
  # [
  #   {
  #     key = "Name"
  #     value = "current"
  #   }
  # ]
}

variable "route53_hosted_zone_domain_filters" {
  description = "Only create records in hosted zones that match the provided domain names. Empty list (default) means match all zones. Zones must satisfy all three constraints (var.route53_hosted_zone_tag_filters, var.route53_hosted_zone_id_filters, and var.route53_hosted_zone_domain_filters)."
  type        = list(string)
  default     = []
}

variable "pod_labels" {
  description = "Labels to apply to the Pod that is deployed, as key value pairs."
  type        = map(string)
  default     = {}
}

variable "pod_annotations" {
  description = "Annotations to apply to the Pod that is deployed, as key value pairs."
  type        = map(string)
  default     = {}
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

variable "service_account_annotations" {
  description = "Annotations to apply to the ServiceAccount created for the external-dns app, formatted as key value pairs."
  type        = map(string)
  default     = {}
}


variable "sources" {
  description = "K8s resources type to be observed for new DNS entries by ExternalDNS."
  type        = list(string)

  # NOTE ON ISTIO: By default, external-dns will listen for "ingress" and "service" events. To use it with Istio, make
  # sure to include the "istio-gateway" events here. See the docs for more details:
  # https://github.com/kubernetes-incubator/external-dns/blob/master/docs/tutorials/istio.md
  default = ["ingress", "service"]
}

variable "endpoints_namespace" {
  description = "Limit sources of endpoints to a specific namespace (default: all namespaces)."
  type        = string
  default     = null
}

variable "txt_owner_id" {
  description = "A unique identifier used to identify this instance of external-dns. This is used to tag the DNS TXT records to know which domains are owned by this instance of external-dns, in case multiple external-dns services are managing the same Hosted Zone."
  type        = string
  default     = "default"
}

variable "eks_cluster_name" {
  description = "Used to name IAM roles for the service account. Recommended when var.use_iam_role_for_service_accounts is true. Also used for creating the Fargate profile when var.create_fargate_profile is true."
  type        = string
  default     = null
}

variable "log_format" {
  description = "Which format to output external-dns logs in (options: text, json)"
  type        = string
  default     = "text"
}

# Fargate parameters

variable "create_fargate_profile" {
  description = "When set to true, create a dedicated Fargate execution profile for the external-dns service. Note that this is not necessary to deploy to Fargate. For example, if you already have an execution profile for the kube-system Namespace, you do not need another one."
  type        = bool
  default     = false
}

variable "vpc_worker_subnet_ids" {
  description = "A list of the subnets into which the EKS Cluster's administrative pods will be launched. These should usually be all private subnets and include one in each AWS Availability Zone. Required when var.create_fargate_profile is true."
  type        = list(string)
  default     = []
}

variable "pod_execution_iam_role_arn" {
  description = "ARN of IAM Role to use as the Pod execution role for Fargate. Set to null (default) to create a new one. Only used when var.create_fargate_profile is true."
  type        = string
  default     = null
}

variable "external_dns_chart_version" {
  description = "The version of the helm chart to use. Note that this is different from the app/container version."
  type        = string
  default     = "6.2.4"
}

variable "trigger_loop_on_event" {
  description = "When enabled, triggers external-dns run loop on create/update/delete events (optional, in addition of regular interval)"
  type        = bool
  default     = false
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
