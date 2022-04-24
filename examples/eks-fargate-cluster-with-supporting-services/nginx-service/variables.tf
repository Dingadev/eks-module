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

variable "route53_hosted_zone_name" {
  description = "The domain name for the Route 53 Public Hosted Zone that should be used as the base hostname for the nginx service."
  type        = string
}


# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These variables have defaults and may be overwritten
# ---------------------------------------------------------------------------------------------------------------------

variable "application_name" {
  description = "Name of the application in Kubernetes. Use to namespace the deployment so that you can deploy multiple copies."
  type        = string
  default     = "nginx"
}

variable "subdomain_suffix" {
  description = "This string will be appended to the subdomain used for the nginx service."
  type        = string
  default     = ""
}

variable "route53_hosted_zone_tags" {
  description = "Search for the domain in var.route53_hosted_zone_name by filtering using these tags. Also, any new Hosted Zones created will be tagged with this."
  type        = map(string)
  default     = {}
}
