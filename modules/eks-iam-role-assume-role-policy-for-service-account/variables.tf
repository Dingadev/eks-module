# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

variable "eks_openid_connect_provider_arn" {
  description = "ARN of the OpenID Connect Provider provisioned for the EKS cluster."
  type        = string
}

variable "eks_openid_connect_provider_url" {
  description = "URL of the OpenID Connect Provider provisioned for the EKS cluster."
  type        = string
}

variable "namespaces" {
  description = "The Kubernetes Namespaces that are allowed to assume the attached IAM Role. Only one of `var.namespaces` or `var.service_accounts` can be set. If both are set, you may end up with an impossible rule! If both are set to null, then this will allow all namespaces and all service accounts."
  type        = list(string)
}

variable "service_accounts" {
  description = "The Kubernetes Service Accounts that are allowed to assume the attached IAM Role. Only one of `var.namespaces` or `var.service_accounts` can be set. If both are set, you may end up with an impossible rule! If both are set to null, then this will allow all namespaces and all service accounts."
  type = list(object({
    name      = string
    namespace = string
  }))
}


# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# ---------------------------------------------------------------------------------------------------------------------

variable "service_accounts_condition_operator" {
  description = "The string operator to use when evaluating the AWS IAM condition for determining which Service Accounts are allowed to assume the IAM role. Examples: StringEquals, StringLike, etc."
  type        = string
  default     = "StringEquals"
}
