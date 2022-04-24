# Basic EKS Cluster

This folder shows an example of how to use the EKS modules to deploy a minimal EKS cluster using Fargate.

Note that by default this example does not setup `kubectl` to be able to access the cluster. You can use `kubergrunt` or
the AWS CLI to configure `kubectl` to authenticate to the deployed cluster. See [How do I authenticate kubectl to the
EKS cluster?](/core-concepts.md#how-do-i-authenticate-kubectl-to-the-eks-cluster) for more information.


## How do you run this example?

To run this example, apply the Terraform templates:

1. Install [kubergrunt](https://github.com/gruntwork-io/kubergrunt), minimum version: `0.6.2`.
1. Install [Terraform](https://www.terraform.io/), minimum version `1.0.0`.
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables
   that don't have a default.
1. Run `terraform init`.
1. Run `terraform apply`.
