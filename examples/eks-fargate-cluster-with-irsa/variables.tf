# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# ---------------------------------------------------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  description = "The AWS region in which all resources will be created. You must use a region with EKS available."
  type        = string
}

variable "vpc_name" {
  description = "The name of the VPC that will be created to house the EKS cluster."
  type        = string
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster."
  type        = string
}

# NOTE: Setting this to a CIDR block that you do not own will prevent your ability to reach the API server. You will
# also be unable to configure the EKS IAM role mapping remotely through this terraform code.
variable "endpoint_public_access_cidrs" {
  description = "A list of CIDR blocks that should be allowed network access to the Kubernetes public API endpoint. When null or empty, allow access from the whole world (0.0.0.0/0). Note that this only restricts network reachability to the API, and does not account for authentication to the API."
  type        = list(string)
}


# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These variables have defaults and may be overwritten
# ---------------------------------------------------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Version of Kubernetes to use. Refer to EKS docs for list of available versions (https://docs.aws.amazon.com/eks/latest/userguide/platform-versions.html)."
  type        = string
  default     = "1.22"
}

variable "allowed_availability_zones" {
  description = "A list of availability zones in the region that we can use to deploy the cluster. You can use this to avoid availability zones that may not be able to provision the resources (e.g ran out of capacity). If empty, will allow all availability zones."
  type        = list(string)
  default     = []
}

variable "unique_identifier" {
  description = "A unique identifier that can be used to index the test IAM resources"
  type        = string
  default     = ""
}

variable "example_iam_role_name_prefix" {
  description = "Prefix of the name for the IAM role to create as an example. The final name is this prefix with the unique_identifier appended to it."
  type        = string
  default     = ""
}

variable "allowed_namespaces_for_iam_role" {
  description = "The list of Namespaces where Service Accounts are allowed to assume the example IAM Role in the EKS cluster. Note that if you set this, `var.allowed_service_accounts_for_iam_role` should be empty."
  type        = list(string)
  default     = ["default"]
}

variable "allowed_service_accounts_for_iam_role" {
  description = "The list of Service Accounts are allowed to assume the example IAM Role in the EKS cluster. Note that if you set this, `var.allowed_namespaces_for_iam_role` should be empty."
  type = list(object({
    name      = string
    namespace = string
  }))
  default = []
}

# Kubectl configuration options

variable "configure_kubectl" {
  description = "Configure the kubeconfig file so that kubectl can be used to access the deployed EKS cluster."
  type        = bool
  default     = false
}

variable "kubectl_config_path" {
  description = "The path to the configuration file to use for kubectl, if var.configure_kubectl is true. Defaults to ~/.kube/config."
  type        = string

  # The underlying command will use the default path when empty
  default = ""
}

variable "use_kubergrunt_to_fetch_token" {
  description = "EKS clusters use short-lived authentication tokens that can expire in the middle of an 'apply' or 'destroy'. To avoid this issue, we use an exec-based plugin to fetch an up-to-date token. If this variable is set to true, we'll use kubergrunt to fetch the token (in which case, kubergrunt must be installed and on PATH); if this variable is set to false, we'll use the aws CLI to fetch the token (in which case, aws must be installed and on PATH)."
  type        = bool
  default     = true
}
