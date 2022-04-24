# EKS Managed Workers Cluster

This folder shows an example of how to use the EKS modules to deploy a minimal EKS cluster with managed worker groups.

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

## Known instabilities

- EKS relies on the [`amazon-vpc-cni-k8s`](https://github.com/aws/amazon-vpc-cni-k8s) plugin to allocate IP addresses to
  the Pods in the Kubernetes cluster. This plugin works by allocating secondary ENI devices to the underlying worker
  when Pods are created, and removing them when Pods are deleted. `terraform` could shutdown the instances before the
  VPC CNI pod had a chance to cull the ENI devices. These devices are managed outside of terraform, so if they linger,
  it could interfere with destroying the VPC.
    - To workaround this limitation, you have to go into the console and delete the ENI associated with the VPC. Then,
      retry the destroy call.
