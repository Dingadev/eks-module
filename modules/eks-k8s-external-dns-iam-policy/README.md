# K8S External DNS IAM Policy Module

This Terraform Module defines an [IAM
policy](http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/QuickStartEC2Instance.html#d0e22325) that
defines the minimal set of permissions necessary for the [external-dns
application](https://github.com/kubernetes-incubator/external-dns). This policy can then be attached to EC2
instances or IAM roles so that the app deployed has enough permissions to manage Route 53 Hosted Zones.

See [the eks-k8s-external-dns module](/modules/eks-k8s-external-dns) for a module that deploys the external-dns
application on to your EKS cluster.


## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See the [eks-cluster-with-supporting-services example](/examples/eks-cluster-with-supporting-services) for example
  usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See [outputs.tf](./outputs.tf) for all the variables that are outputed by this module.


## Attaching IAM policy to workers

To allow the external-dns app to manage Route 53 Hosted Zones, it needs IAM permissions to use the AWS API to manage the
zones. Currently, the way to grant Pods IAM privileges is to use the worker IAM profiles provisioned by [the
eks-cluster-workers module](/modules/eks-cluster-workers/README.md#how-do-you-add-additional-iam-policies).

The Terraform templates in this module create an IAM policy that has the required permissions. You then need to use an
[aws_iam_policy_attachment](https://www.terraform.io/docs/providers/aws/r/iam_policy_attachment.html) to attach that
policy to the IAM roles of your EC2 Instances.

```hcl
module "eks_workers" {
  # (arguments omitted)
}

module "k8s_external_dns_iam_policy" {
  # (arguments omitted)
}

resource "aws_iam_role_policy_attachment" "attach_k8s_external_dns_iam_policy" {
    role = "${module.eks_workers.eks_worker_iam_role_name}"
    policy_arn = "${module.k8s_external_dns_iam_policy.k8s_external_dns_policy_arn}"
}
```
