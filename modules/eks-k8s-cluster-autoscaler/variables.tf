# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  description = "The AWS region that the EKS cluster resides in."
  type        = string
}

variable "aws_partition" {
  description = "The AWS partition used for default AWS Resources."
  type        = string
  default     = "aws"
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster (e.g. eks-prod). This is used to assist with auto-discovery of the cluster workers ASG."
  type        = string
}

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

variable "namespace" {
  description = "Which Kubernetes Namespace to deploy the chart into."
  type        = string
  default     = "kube-system"
}

variable "release_name" {
  description = "The name of the helm release to use. Using different release names are useful for deploying different copies of the cluster autoscaler."
  type        = string
  default     = "cluster-autoscaler"
}

variable "cluster_autoscaler_version" {
  description = "Which version of the cluster autoscaler to install."
  type        = string
  default     = "v1.22.2"
  # NOTE: should match the major/minor version of your Kubernetes installation.
  # See https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler#releases
}

variable "cluster_autoscaler_repository" {
  description = "Which docker repository to use to install the cluster autoscaler. Check the following link for valid repositories to use https://github.com/kubernetes/autoscaler/releases"
  type        = string
  default     = "us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler"
}

variable "scaling_strategy" {
  description = "Specifies an 'expander' for the cluster autoscaler. This helps determine which ASG to scale when additional resource capacity is needed."
  type        = string
  default     = "least-waste"
  # See https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#what-are-expanders
}

variable "container_extra_args" {
  description = "Map of extra arguments to pass to the container."
  type        = map(string)
  default     = {}
}

variable "expander_priorities" {
  description = "If scaling_strategy is set to 'priority', you can use this variable to define cluster-autoscaler-priority-expander priorities. See: https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/expander/priority/readme.md"
  type        = map(list(string))
  default     = {}
  # Example:
  #
  # expander_priorities = {
  #   10 = [".*t2\.large.*", ".*t3\.large.*"]
  #   50 = [".*m4\.4xlarge.*"]
  # }
}

variable "priority_config_map_annotations" {
  description = "If scaling_strategy is set to 'priority', you can use this to specify annotations to add to the cluster-autoscaler-priority-expander ConfigMap."
  type        = map(string)
  default     = {}
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

variable "pod_priority_class_name" {
  description = "Configure priorityClassName of pods to allow scheduler to order pending pods by their priority."
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

variable "pod_replica_count" {
  description = "Number of replicas of the cluster autoscaler Pod to deploy."
  type        = number
  default     = 1
}

variable "pod_resources" {
  description = "Pod resource requests and limits to use. Refer to https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ for more information."

  # We use any type here to avoid maintaining the kubernetes defined type spec for the resources here. That way, we can
  # support wide range of kubernetes versions.
  type = any

  default = null
}

# Fargate parameters

variable "create_fargate_profile" {
  description = "When set to true, create a dedicated Fargate execution profile for the cluster autoscaler."
  type        = bool
  default     = false
}

variable "create_fargate_execution_role" {
  description = "When set to true, create a dedicated Fargate execution role for the cluster autoscaler. When false, you must provide an existing fargate execution role in the variable var.pod_execution_iam_role_arn. Only used if var.create_fargate_profile is true."
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

variable "cluster_autoscaler_chart_version" {
  description = "The version of the cluster-autoscaler helm chart to deploy. Note that this is different from the app/container version, which is sepecified with var.cluster_autoscaler_version."
  type        = string
  default     = "9.17.0"
}

variable "cluster_autoscaler_absolute_arns" {
  description = "Restrict the cluster autoscaler to a list of absolute ASG ARNs upon initial apply to ensure no new ASGs can be managed by the autoscaler without explicitly running another apply. Setting this to false will ensure that the cluster autoscaler is automatically given access to manage any new ASGs with the k8s.io/cluster-autoscaler/CLUSTER_NAME tag applied."
  type        = bool
  default     = true
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
