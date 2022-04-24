# EKS Cluster with IAM Role for Service Accounts (IRSA)

This folder shows an example of how to use the EKS modules to deploy an EKS cluster with support for IAM Roles for
Service Accounts (IRSA). See [the official docs for more information on
IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html).

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


## Assigning the IAM Role to a Pod

By default this example creates an IAM role with permissions to list EKS clusters that is configured to be assumed by
Service Accounts in the `default` Namespace. You can exchange the Service Account token for any Service Account in the
`default` Namespace for IAM credentials that correspond to the created IAM role. Refer to [How do I associate IAM roles
to the Pods?](/modules/eks-cluster-control-plane/README.md#how-do-i-associate-iam-roles-to-the-pods) section of the
`eks-cluster-control-plane` module README for more information on how to do that.

You can allow additional or different Namespaces by modifying the `allowed_namespaces_for_iam_role` input parameter. You
can also restrict to specific Service Accounts by using the `allowed_service_accounts_for_iam_role` input parameter.
