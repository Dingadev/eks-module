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

variable "vpc_id" {
  description = "The ID of the VPC where the EKS cluster resides. Used for determining where to deploy the ALB."
  type        = string
}

variable "eks_cluster_name" {
  description = "The ALB Ingress Controller application uses this to find resources (e.g. subnets) to associate with ALBs. Additionally, AWS resources created by the Ingress controller will be prefixed with this value."
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

variable "pod_replica_count" {
  description = "Number of replicas of the ingress controller Pod to deploy."
  type        = number
  default     = 1
}

variable "destroy_lifecycle_command" {
  description = "Command to run before uninstalling the AWS ALB Ingress Controller during `terraform destroy`. Since the ingress controller manages AWS resources, you may want to remove Ingress objects from the cluster and give the application enough time time to notice and remove the associated resources from AWS."
  type        = string
  default     = "exit 0"
}

variable "destroy_lifecycle_environment" {
  description = "Environment variables that will be available when var.destroy_lifecycle_command runs"
  type        = map(string)
  default     = {}
}

# Fargate parameters

variable "create_fargate_profile" {
  description = "When set to true, create a dedicated Fargate execution profile for the alb ingress controller. Note that this is not necessary to deploy to Fargate. For example, if you already have an execution profile for the kube-system Namespace, you do not need another one."
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

variable "docker_image_repo" {
  description = "The repository of the docker image that should be deployed."
  type        = string
  default     = "602401143452.dkr.ecr.us-west-2.amazonaws.com/amazon/aws-load-balancer-controller"
}

variable "docker_image_tag" {
  description = "The tag of the docker image that should be deployed."
  type        = string
  default     = "v2.4.1"
}

variable "chart_version" {
  description = "The version of the aws-load-balancer-controller helmchart to use."
  type        = string
  default     = "1.4.1"
}

variable "enable_restricted_sg_rules" {
  description = "Enables restricted Security Group rules for the load balancers managed by the controller. When this is true, the load balancer will restrict the target group security group rules to only use the ports that it needs."
  type        = bool

  # NOTE: We intentionally default this to false as there are bugs with this feature when using IP target rules, which
  # is the only way the controller works with Fargate services. See
  # https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/2317 for more details. If you are not using
  # Fargate services, you can enable this for a better security posture for your deployment.
  default = false
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
