# EKS Cluster with Self Managed Workers and Additional IAM Roles

This folder shows an example of how to use the EKS modules to:

- deploy an EKS cluster
- deploy a self managed worker pool
- setup `kubectl` to deploy applications on it using the Kubernetes interface
- create a sample IAM role and bind a Kubernetes RBAC group to it

After this example, your `kubectl` binary should be configured to access the EKS cluster. See [How do I authenticate
kubectl to the EKS cluster?](/core-concepts.md#how-do-i-authenticate-kubectl-to-the-eks-cluster) for more information.

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
  the pods in the Kubernetes cluster. This plugin works by allocating secondary ENI devices to the underlying worker
  instances. Depending on timing, this plugin could interfere with destroying the cluster in this example. Specifically,
  terraform could shutdown the instances before the VPC CNI pod had a chance to cull the ENI devices. These devices are
  managed outside of terraform, so if they linger, it could interfere with destroying the VPC.
    - To workaround this limitation, you have to go into the console and delete the ENI associated with the VPC. Then,
      retry the destroy call.
