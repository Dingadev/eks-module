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

variable "vpc_id" {
  description = "The ID of the VPC that is housing the EKS cluster."
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These variables have defaults and may be overwritten
# ---------------------------------------------------------------------------------------------------------------------

variable "use_private_hostname" {
  description = "When true, this will create a Route 53 private hosted zone to front the domain, and set a host based routing rule for the Ingress resource of the Service. Note that if you set this to true, the host is only available from within the VPC."
  type        = bool
  default     = false
}

variable "use_public_hostname" {
  description = "When true, this will lookup and use a Route 53 Public Hosted Zone to front the domain, and set a host based routing rule for the Ingress resource of the Service. Note that if you set this to true, you must also provide var.route53_hosted_zone_name. If both use_private_hostname and use_public_hostname is true, use_public_hostname will be preferred."
  type        = bool
  default     = false
}

variable "route53_hosted_zone_name" {
  description = "The domain name for the Route 53 Public Hosted Zone that should be used as the base hostname for the nginx service. Required if var.use_public_hostname is true."
  type        = string
  default     = null
}

variable "route53_hosted_zone_tags" {
  description = "Search for the domain in var.route53_hosted_zone_name by filtering using these tags. Also, any new Hosted Zones created will be tagged with this."
  type        = map(string)
  default     = {}
}

variable "subdomain_suffix" {
  description = "This string will be appended to the subdomain used for the nginx service when `use_public_hostname` or `use_private_hostname` is set to true."
  type        = string
  default     = ""
}

variable "kubectl_config_context_name" {
  description = "Name of the kubectl config file context for accessing the EKS cluster."
  type        = string
  default     = ""
}

variable "kubectl_config_path" {
  description = "Path to the kubectl config file. Defaults to $HOME/.kube/config"
  type        = string
  default     = ""
}

variable "helm_home" {
  description = "The path to the home directory for helm that you wish to use for this deployment. Defaults to ~/.helm"
  type        = string
  default     = ""
}

variable "application_name" {
  description = "Name of the application in Kubernetes. Use to namespace the deployment so that you can deploy multiple copies."
  type        = string
  default     = "nginx"
}
