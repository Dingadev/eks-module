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

variable "eks_cluster_name" {
  description = "The name of the EKS cluster."
  type        = string
}

variable "eks_vpc_id" {
  description = "ID of the VPC that is housing the EKS cluster."
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
# OPTIONAL PARAMETERS
# These variables have defaults and may be overwritten
# ---------------------------------------------------------------------------------------------------------------------

# external-dns configuration options

variable "external_dns_route53_hosted_zone_id_filters" {
  description = "Only create records in hosted zones that match the provided IDs. Empty list (default) means match all zones. Zones must satisfy all three constraints (var.route53_hosted_zone_tag_filters, var.route53_hosted_zone_id_filters, and var.route53_hosted_zone_domain_filters)."
  type        = list(string)
  default     = []
}

variable "external_dns_route53_hosted_zone_tag_filters" {
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

variable "external_dns_route53_hosted_zone_domain_filters" {
  description = "Only create records in hosted zones that match the provided domain names. Empty list (default) means match all zones. Zones must satisfy all three constraints (var.route53_hosted_zone_tag_filters, var.route53_hosted_zone_id_filters, and var.route53_hosted_zone_domain_filters)."
  type        = list(string)
  default     = []
}

variable "cluster_autoscaler_version" {
  description = "Which version of the cluster autoscaler to install."
  type        = string
  default     = "v1.22.2"
  # NOTE: should match the major/minor version of your Kubernetes installation.
  # See https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler#releases
}

variable "use_kubergrunt_to_fetch_token" {
  description = "EKS clusters use short-lived authentication tokens that can expire in the middle of an 'apply' or 'destroy'. To avoid this issue, we use an exec-based plugin to fetch an up-to-date token. If this variable is set to true, we'll use kubergrunt to fetch the token (in which case, kubergrunt must be installed and on PATH); if this variable is set to false, we'll use the aws CLI to fetch the token (in which case, aws must be installed and on PATH)."
  type        = bool
  default     = true
}
