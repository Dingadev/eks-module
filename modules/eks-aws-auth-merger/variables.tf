# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

variable "namespace" {
  description = "Namespace to deploy the aws-auth-merger into. The app will watch for ConfigMaps in this Namespace to merge into the aws-auth ConfigMap."
  type        = string
}

variable "aws_auth_merger_image" {
  description = "Location of the container image to use for the aws-auth-merger app."
  type = object({
    # Container image repository where the aws-auth-merger app container image lives
    repo = string
    # Tag of the aws-auth-merger container to deploy
    tag = string
  })
}


# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

# App configuration

variable "configmap_label_selector" {
  description = "A Kubernetes Label Selector for the Namespace to look for ConfigMaps that should be merged into the main aws-auth ConfigMap."
  type        = string
  default     = ""
}

variable "autocreate_labels" {
  description = "Labels to apply to ConfigMaps that are created automatically by the aws-auth-merger when snapshotting the existing main ConfigMap. This must match the label selector provided in configmap_label_selector."
  type        = map(string)
  default     = {}
}

variable "refresh_interval" {
  description = "Interval to poll the Namespace for aws-auth ConfigMaps to merge as a duration string (e.g. 5m10s for 5 minutes 10 seconds)."
  type        = string
  default     = "5m"
}

# Deployment Configuration

variable "deployment_name" {
  description = "Name to apply to the Deployment for the aws-auth-merger app."
  type        = string
  default     = "aws-auth-merger"
}

variable "deployment_labels" {
  description = "Key value pairs of strings to apply as labels on the Deployment."
  type        = map(string)
  default     = {}
}

variable "deployment_annotations" {
  description = "Key value pairs of strings to apply as annotations on the Deployment."
  type        = map(string)
  default     = {}
}

variable "pod_labels" {
  description = "Key value pairs of strings to apply as labels on the Pod."
  type        = map(string)
  default     = {}
}

variable "pod_annotations" {
  description = "Key value pairs of strings to apply as annotations on the Pod."
  type        = map(string)
  default     = {}
}


# ServiceAccount configuration

variable "service_account_name" {
  description = "Name to apply to the ServiceAccount for the aws-auth-merger app."
  type        = string
  default     = "aws-auth-merger"
}

variable "service_account_labels" {
  description = "Key value pairs of strings to apply as labels on the ServiceAccount."
  type        = map(string)
  default     = {}
}

variable "service_account_annotations" {
  description = "Key value pairs of strings to apply as annotations on the ServiceAccount."
  type        = map(string)
  default     = {}
}

variable "service_account_role_name" {
  description = "Name to apply to the RBAC Role for the ServiceAccount."
  type        = string
  default     = "aws-auth-merger"
}

variable "service_account_role_labels" {
  description = "Key value pairs of strings to apply as labels on the RBAC Role for the ServiceAccount."
  type        = map(string)
  default     = {}
}

variable "service_account_role_annotations" {
  description = "Key value pairs of strings to apply as annotations on the RBAC Role for the ServiceAccount."
  type        = map(string)
  default     = {}
}

variable "service_account_role_binding_name" {
  description = "Name to apply to the RBAC Role Binding for the ServiceAccount."
  type        = string
  default     = "aws-auth-merger"
}

variable "service_account_role_binding_labels" {
  description = "Key value pairs of strings to apply as labels on the RBAC Role Binding for the ServiceAccount."
  type        = map(string)
  default     = {}
}

variable "service_account_role_binding_annotations" {
  description = "Key value pairs of strings to apply as annotations on the RBAC Role Binding for the ServiceAccount."
  type        = map(string)
  default     = {}
}

# Namespace configuration

variable "create_namespace" {
  description = "When true this will inform the module to create the Namespace."
  type        = bool
  default     = true
}

variable "create_fargate_profile" {
  description = "If true, create a Fargate Profile so that the aws-auth-merger app runs on Fargate."
  type        = bool
  default     = false
}

variable "fargate_profile" {
  description = "Configuration options for the Fargate Profile. Only used if create_fargate_profile is set to true."
  type = object({
    # Name of the Fargate Profile (this must be unique per cluster).
    name = string

    # Name of the EKS cluster that the Fargate Profile belongs to.
    eks_cluster_name = string

    # List of VPC subnet IDs to use for the Pods.
    worker_subnet_ids = list(string)

    # ARN of an IAM role to use for the Pod execution. This role is primarily used to setup the container, like pulling
    # the container image, setting up volumes, mounting secrets, etc.
    pod_execution_role_arn = string
  })
  default = null
}

variable "create_resources" {
  description = "If you set this variable to false, this module will not create any resources. This is used as a workaround because Terraform does not allow you to use the 'count' parameter on modules. By using this parameter, you can optionally create or not create the resources within this module."
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Logging verbosity level. Must be one of (in order of most verbose to least): trace, debug, info, warn, error, fatal, panic."
  type        = string
  default     = "info"
}
