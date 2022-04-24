# K8S Cluster Autoscaler Module

This Terraform Module installs a [Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
to automatically scale up and down the nodes in a cluster in response to resource utilization.

This module is responsible for manipulating each Auto Scaling Group (ASG) that was created by the [EKS cluster
workers](/modules/eks-cluster-workers) module. By default, the ASG is configured to allow zero-downtime
deployments but is not configured to scale automatically. You must launch an [EKS control
plane](/modules/eks-cluster-control-plane) with worker nodes for this module to function.


## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.


## Important Considerations

- The autoscaler doesn't account for CPU or Memory usage in deciding to scale up, it scales up when Pods fail to
  schedule due to insufficient resources. This means it's important to carefully the manage the compute resources you
  assign to your deployments. See [the Kubernetes
  documentation](https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container) on compute
  resources for more information.
- Scaling down happens when utilization dips below a specified threshold and there are pods that are able to be moved
  to another node. There are [a variety of conditions](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#what-types-of-pods-can-prevent-ca-from-removing-a-node)
  to be aware of that can prevent pods from being automatically removable which can result in wasted capacity.


## How do I deploy the Pods to Fargate?

To deploy the Pods to Fargate, you can use the `create_fargate_profile` variable to `true` and specify the subnet IDs
for Fargate using `vpc_worker_subnet_ids`. Note that if you are using Fargate, you must rely on the IAM Roles for
Service Accounts (IRSA) feature to grant the necessary AWS IAM permissions to the Pod. This is configured using the
`use_iam_role_for_service_accounts`, `eks_openid_connect_provider_arn`, and `eks_openid_connect_provider_url` input
variables.
