output "vpc_eks_tags" {
  description = "Tags for the VPC to use for integration with EKS."

  value = {
    for cluster_name in var.eks_cluster_names :
    "kubernetes.io/cluster/${cluster_name}" => "shared"
  }
}

output "vpc_public_subnet_eks_tags" {
  description = "Tags for public subnets in the VPC to use for integration with EKS."

  value = merge(
    { for cluster_name in var.eks_cluster_names :
    "kubernetes.io/cluster/${cluster_name}" => "shared" },
    { "kubernetes.io/role/elb" = "1" }
  )
}

output "vpc_private_app_subnet_eks_tags" {
  description = "Tags for private application subnets in the VPC to use for integration with EKS."

  # Tag the private app subnets for use when provisioning internal ELBs as part of internal LoadBalancer service type.
  # See https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer for more details about internal
  # loadbalancers managed by Kubernetes.
  value = merge(
    { for cluster_name in var.eks_cluster_names :
    "kubernetes.io/cluster/${cluster_name}" => "shared" },
    { "kubernetes.io/role/internal-elb" = "1" }
  )
}

output "vpc_private_persistence_subnet_eks_tags" {
  description = "Tags for private persistence tier subnets in the VPC to use for integration with EKS."

  value = {
    for cluster_name in var.eks_cluster_names :
    "kubernetes.io/cluster/${cluster_name}" => "shared"
  }
}
