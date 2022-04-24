# EKS Cluster Workers Cross Access Module

This Terraform Module creates reciprocating ingress security group rules for the ports that are provided, so that you
can configure network access between separate ASG worker groups.

This module should be used when you have core services that can be scheduled on any of your available worker groups, and
services on either group depend on them. For example, `coredns` is an essential service on EKS clusters that provide DNS
capabilities within the Kubernetes cluster. `coredns` has tolerations such that it can be scheduled on any node.
Therefore, you will typically want to ensure port 53 is available between all your worker pools. To allow port 53 access
between all your worker groups, you can add the following module block:

```hcl
module "allow_all_access_between_worker_pools" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-workers-cross-access?ref=v0.3.1"

  # This should be the number of security groups in the list eks_worker_security_group_ids.
  num_eks_worker_security_group_ids = 2

  eks_worker_security_group_ids = [
    # Include the security group ID of each worker group
  ]

  ports = [
    {
      from_port = 53
      to_port   = 53
    },
  ]
}
```

Note that this module will configure the security group rules to go both ways for each pair in the provided list. If you
have more complex network topologies, you should manually construct the security group rules instead of using this
module.


## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See the [eks-cluster-with-supporting-services example](/examples/eks-cluster-with-supporting-services) folder for
  example usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
