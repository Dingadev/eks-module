# EKS IAM Role Assume Role Policy for Kubernetes Service Accounts

This Terraform module can be used to create Assume Role policies for IAM Roles such that they can be used with
Kubernetes Service Accounts. This requires a compatible EKS cluster that supports the [IAM Roles for Service
Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) feature.

See the [corresponding section of the eks-cluster-control-plane module
README](/modules/eks-cluster-control-plane/README.md#how-do-i-associate-iam-roles-to-the-pods) for information on how to set
up IRSA and how it works.


## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See [outputs.tf](./outputs.tf) for all the variables that are outputed by this module.

This module is intended to be passed to the `assume_role_policy` input for an IAM role. For example:

```
module "assume_role_policy" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-iam-role-assume-role-policy-for-service-account?ref=v0.7.0"

  eks_openid_connect_provider_arn = module.eks_cluster.eks_iam_openid_connect_provider_arn
  eks_openid_connect_provider_url = module.eks_cluster.eks_iam_openid_connect_provider_url
  namespaces                      = ["default"]
  service_accounts                = []
}

resource "aws_iam_role" "example" {
  name               = "example-iam-role"
  assume_role_policy = module.assume_role_policy.assume_role_policy_json
}
```

The above example will configure the IAM role `example-iam-role` such that it is availble to be assumed by the EKS
cluster provisioned in the `eks_cluster` module block (not shown). Note that we restrict it so that it can only be
assumed by Service Accounts in the Namespace `default`. You can restrict it further to specific Service Accounts if you
specify the `service_accounts` input variable.

If you want to allow additional Namespaces, append them to the `namespaces` input. For example, if you want to allow
Service Accounts in _either_ the `default` Namespace or `kube-system` Namespace:

```
module "assume_role_policy" {
  # Other parameters omitted for brevity

  namespaces = ["default", "kube-system"]
}
```

You can also restrict to specific Service Accounts. For example, to only allow the `list-eks-clusters-sa` Service
Account in the `default` Namespace to assume the role:

```
module "assume_role_policy" {
  # Other parameters omitted for brevity

  namespaces       = []
  service_accounts = [{
    namespace = "default"
    name      = "list-eks-clusters-sa"
  }]
}
```

You can allow other Service Accounts as well by expanding the list.

If you wish to allow any Service Account in your cluster to assume the role, you can set both `namespaces` and
`service_accounts` to an empty list.

Note that this module does not support specifying both `namespaces` and `service_accounts` at the same time. You must
use one or the other.

Refer to the [corresponding section of the eks-cluster-control-plane module
README](../eks-cluster-control-plane/README.md#how-do-i-associate-iam-roles-to-the-pods) for information on how to use
the IAM role in your Pods.
