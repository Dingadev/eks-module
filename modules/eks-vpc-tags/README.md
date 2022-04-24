# EKS VPC Tags Module

This Terraform Module exports a set of known tags for VPCs that are used for an [Elastic Container Service for
Kubernetes Cluster](https://docs.aws.amazon.com/eks/latest/userguide/clusters.html).

EKS relies on various tags on resources related to the cluster to provide integrations with plugins in Kubernetes. For
example, VPC subnets must be tagged with `kubernetes.io/cluster/EKS_CLUSTER_NAME=shared` so that the [amazon-vpc-cni-k8s
plugin](https://github.com/aws/amazon-vpc-cni-k8s) knows which subnet to use to allocate IPs for Kubernetes pods. The
tags exported by this module are the most common recommended tags to use for a newly created VPC intended to be used
with EKS.


## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See the [eks-fargate-cluster examples](/examples/eks-fargate-cluster) folder for example usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See [outputs.tf](./outputs.tf) for all the variables that are outputed by this module.
