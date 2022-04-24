# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DATA SOURCES
# These resources must already exist.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

data "aws_eks_cluster" "eks" {
  count = var.create_resources && var.use_existing_cluster_config ? 1 : 0
  name  = var.cluster_name
}

locals {
  eks_cluster_vpc_config = try(data.aws_eks_cluster.eks[0].vpc_config[0], null)
  eks_control_plane_security_group_id = (
    var.create_resources && var.eks_control_plane_security_group_id == null
    # security_group_ids is a set so convert to list and sort it to get consistent security group
    ? sort(tolist(local.eks_cluster_vpc_config.security_group_ids))[0]
    : var.eks_control_plane_security_group_id
  )
}
