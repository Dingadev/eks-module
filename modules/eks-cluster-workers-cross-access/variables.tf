# This is necessary so that `eks_worker_security_group_ids` can contain interpolations. Otherwise, the `count` cannot be
# computed due to a terraform limitation. See https://github.com/hashicorp/terraform/issues/12570 for more information.
variable "num_eks_worker_security_group_ids" {
  description = "The number of Security Group IDs passed into the module. This should be equal to the length of the var.eks_worker_security_group_ids input list."
  type        = number
}

variable "eks_worker_security_group_ids" {
  description = "The list of Security Group IDs for EKS workers that should have reciprocating ingress rules for the port information provided in var.ports. For each group in the list, there will be an ingress rule created for all ports provided for all the other groups in the list."
  type        = list(string)
}

variable "ports" {
  description = "The list of port ranges that should be allowed into the security groups."
  type = list(object({
    from_port = number
    to_port   = number
    protocol  = string
  }))

  default = [
    {
      from_port = 0
      to_port   = 0
      protocol  = "-1"
    },
  ]
}
