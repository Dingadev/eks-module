# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

variable "name_prefix" {
  description = "A name that uniquely identified in which context this module is being invoked. This also helps to avoid creating two resources with the same name from different terraform applies."
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "create_resources" {
  description = "If you set this variable to false, this module will not create any resources. This is used as a workaround because Terraform does not allow you to use the 'count' parameter on modules. By using this parameter, you can optionally create or not create the resources within this module."
  type        = bool
  default     = true
}

variable "eks_worker_asg_arns" {
  description = "ARNs of the Auto Scaling Groups to grant access to. If this is not specified the policy will match based on tags only (specifically, the tag 'k8s.io/cluster-autoscaler/NAME_PREFIX')."
  type        = list(string)
  default     = []
}
