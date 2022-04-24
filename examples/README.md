# Quickstart Guides and Examples

This folder contains various examples that demonstrate how to use the Terraform Modules provided by this repository.
Each example has a detailed README that provides a step by step guide on how to deploy the example. Each example is
meant to capture a common use case for the Modules in this repo.

If you are new to EKS and Kubernetes, start with the [eks-fargate-cluster](./eks-fargate-cluster) example. This example
will setup a minimal EKS cluster that you can use to explore:

- How the modules provision the EKS cluster control plane with Fargate.
- How to authenticate to the cluster using [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/).
- How to authenticate the Terraform kubernetes provider to manage Kubernetes resources using Terraform.

Once you have a basic understanding of the modules and concepts surrounding EKS, Kubernetes, and Terraform, you can move
on to the other examples:

- Check out the [eks-fargate-cluster-with-irsa
  example](https://github.com/gruntwork-io/terraform-aws-eks/tree/master/examples/eks-fargate-cluster-with-irsa) for setting up
  IAM roles that can be assumed by Kubernetes Service Accounts.
- Check out the [eks-fargate-cluster-with-supporting-services
  example](https://github.com/gruntwork-io/terraform-aws-eks/tree/master/examples/eks-fargate-cluster-with-supporting-services)
  for how to deploy EKS with additional services to enhance the experience (e.g Tiller or Helm Server for managing apps,
  ALB ingress controller for exposing services outside the cluster, etc).
- Check out the [eks-cluster-managed-workers
  example](https://github.com/gruntwork-io/terraform-aws-eks/tree/master/examples/eks-cluster-managed-workers) for
  setting up Managed Node Groups to use as workers.
- Check out the [eks-cluster-with-iam-role-mappings
  example](https://github.com/gruntwork-io/terraform-aws-eks/tree/master/examples/eks-cluster-with-iam-role-mappings)
  for how to use self managed workers and grant additional IAM users and roles access to the cluster.
- Check out the [eks-cluster-with-supporting-services
  example](https://github.com/gruntwork-io/terraform-aws-eks/tree/master/examples/eks-cluster-with-supporting-services)
  for how to deploy EKS with self managed workers, including:
    - Multiple worker groups and how to use labels to distinguish between the two.
    - Additional supporting services to enhance the experience (e.g Tiller or Helm Server for managing apps, fluentd for
      log shipping, cluster-autoscaler, etc).



## Which example should I use for production?

When you are ready to integrate EKS into your infrastructure, we recommend using the
[eks-fargate cluster-with-supporting-services
example](https://github.com/gruntwork-io/terraform-aws-eks/tree/master/examples/eks-cluster-with-supporting-services) or
the [eks-cluster-with-supporting-services
example](https://github.com/gruntwork-io/terraform-aws-eks/tree/master/examples/eks-cluster-with-supporting-services) as
a template for your infrastructure code. These examples includes everything you need to get started with running and
managing your EKS cluster.
