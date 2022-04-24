# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM RUNTIME REQUIREMENTS
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "< 4.0"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE RECIPROCAL ACCESS ACROSS THE PROVIDED SECURITY GROUPS
# ---------------------------------------------------------------------------------------------------------------------

# Since we can't have nested loops in terraform, we have to be creative in constructing the security group rule:
# - We first pair up each of the security groups with each other to construct an NxN matrix, where N is the number of
#   security groups passed in. Each entry in the matrix denotes a rule for allowing X->Y on the ports.
# - However, we need to filter out the diagonal of the matrix, where X=Y. This is because eks-cluster-workers already
#   allows all ports between nodes within the same group, and AWS will reject the duplicate rule.
# - Since Terraform has limited support for conditionals, we do the filtering by first encoding each pair as the string
#   "X,Y". In the process, if we detect that the entry is a diagonal (X=Y), we encode it as the empty string.
# - To construct the pairings, we use arithmetic. We do a single loop of N^2, where x = i/N and y = i%N to get the
#   indexes into the matrix.
# - At this point, we have constructed a list of strings in the eks_worker_ingress_pairs.
#   E.g if we pass in ["foo", "bar"] as the list of security group IDs, the result will be ["foo,bar", "", "bar,foo", ""].
# - We then filter out the empty strings using the compact function.
# - Finally, we do another loop that combines looping over the ports with the new list of pairs to create the security
#   group. We decode the encoded pair "X,Y" here by doing a split and element lookup.

locals {
  eks_worker_ingress_pairs = [
    for i in range(var.num_eks_worker_security_group_ids * var.num_eks_worker_security_group_ids) :
    (
      element(var.eks_worker_security_group_ids, floor(i / var.num_eks_worker_security_group_ids))
      ==
      element(var.eks_worker_security_group_ids, i % var.num_eks_worker_security_group_ids)
      ? ""
      : join(
        ",",
        [
          element(var.eks_worker_security_group_ids, floor(i / var.num_eks_worker_security_group_ids)),
          element(var.eks_worker_security_group_ids, i % var.num_eks_worker_security_group_ids),
        ],
      )
    )
  ]
  eks_worker_ingress_pairs_without_self_pair = compact(local.eks_worker_ingress_pairs)

  # Number of security groups created is N^2 - N, because we take out the diagonal, which is the entries where X=X, so
  # there is one entry removed per security group.
  num_security_groups = (var.num_eks_worker_security_group_ids * var.num_eks_worker_security_group_ids) - var.num_eks_worker_security_group_ids
}

# We have a nested loop here that needs to be simulated with arithmetic. Specifically, for each port pair we need to
# make a security group rule for each of the security group pairs.
# ports_index          = count.index / num_security_groups
# security_group_index = count.index % num_security_groups
resource "aws_security_group_rule" "eks_worker_ingress_other_workers" {
  count = length(var.ports) * local.num_security_groups

  description = "Allow worker nodes from different group to communicate with each other"

  source_security_group_id = element(
    split(
      ",",
      element(
        local.eks_worker_ingress_pairs_without_self_pair,
        count.index % local.num_security_groups,
      ),
    ),
    0,
  )

  security_group_id = element(
    split(
      ",",
      element(
        local.eks_worker_ingress_pairs_without_self_pair,
        count.index % local.num_security_groups,
      ),
    ),
    1,
  )

  protocol  = var.ports[floor(count.index / local.num_security_groups)]["protocol"]
  from_port = var.ports[floor(count.index / local.num_security_groups)]["from_port"]
  to_port   = var.ports[floor(count.index / local.num_security_groups)]["to_port"]
  type      = "ingress"
}
