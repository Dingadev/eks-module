# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

variable "eks_cluster_names" {
  description = "Names of the EKS clusters that you would like to associate with this VPC."
  type        = list(string)
}
