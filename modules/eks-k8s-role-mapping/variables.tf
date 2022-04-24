# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

# Required parameters. This is minimally necessary to have the EKS cluster function properly.

variable "eks_worker_iam_role_arns" {
  description = "List of AWS ARNs of the IAM roles associated with the EKS worker nodes. Each IAM role passed in will be set up as a Node role in Kubernetes."
  type        = list(string)
}

# Optional parameters.

variable "eks_fargate_profile_executor_iam_role_arns" {
  description = "List of AWS ARNs of the IAM roles associated with launching fargate pods. Each IAM role passed in will be set up as a Node role in Kubernetes."
  type        = list(string)
  default     = []
}

variable "iam_role_to_rbac_group_mappings" {
  description = "Mapping of AWS IAM roles to RBAC groups, where the keys are AWS ARN of IAM roles and values are the mapped k8s RBAC group names as a list."
  type        = map(list(string))
  default     = {}
}

variable "iam_user_to_rbac_group_mappings" {
  description = "Mapping of AWS IAM users to RBAC groups, where the keys are AWS ARN of IAM users and values are the mapped k8s RBAC group names as a list."
  type        = map(list(string))
  default     = {}
}

variable "config_map_labels" {
  description = "Map of string keys and values that can be used to tag the ConfigMap resource that holds the mapping information."
  type        = map(string)
  default     = {}
}

variable "name" {
  description = "Name to apply to the ConfigMap that is created. Note that this must be called aws-auth, unless you are using the aws-auth-merger."
  type        = string
  default     = "aws-auth"
}

variable "namespace" {
  description = "Namespace to create the ConfigMap in. Note that this must be kube-system, unless you are using the aws-auth-merger."
  type        = string
  default     = "kube-system"
}
