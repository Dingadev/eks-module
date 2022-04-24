# EKS Cluster Managed Workers Module

**This module provisions [EKS Managed Node Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html), as opposed to self managed ASGs. See the [eks-cluster-workers](../eks-cluster-workers) module for a module to provision self managed worker groups.**

This Terraform module launches worker nodes using [EKS Managed Node
Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html) that you can use to run Kubernetes
Pods and Deployments.

This module is responsible for the EKS Worker Nodes in [the EKS cluster
topology](/modules/eks-cluster-control-plane/README.md#what-is-an-eks-cluster). You must launch a control plane in order
for the worker nodes to function. See the [eks-cluster-control-plane module](/modules/eks-cluster-control-plane) for
managing an EKS control plane.


## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See the [examples](/examples) folder for example usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See [outputs.tf](./outputs.tf) for all the variables that are outputed by this module.


## Differences with self managed workers

Managed Node Groups is a feature of EKS where you rely on EKS to manage the lifecycle of your worker nodes. This
includes:

- Automatic IAM role registration
- Upgrades to platform versions and AMIs
- Scaling up and down
- Security Groups

Instead of manually managing Auto Scaling Groups and AMIs, you rely on EKS to manage those for you. This allows you to
offload concerns such as upgrading and graceful scale out of your worker pools to AWS so that you don't have to manage
them using tools like `kubergrunt`.

However, the trade off here is that managed node groups are more limited on the options for customizing the deployed
servers. For example, you can not use any arbitrary AMI for managed node groups: they must be the officially published
EKS optimized AMIs. You can't even use a custom AMI that is based off of the optimized AMIs. This means that you can't
use utilities like [ssh-grunt](https://github.com/gruntwork-io/terraform-aws-security/tree/master/modules/ssh-grunt) or
[ip-lockdown](https://github.com/gruntwork-io/terraform-aws-security/tree/master/modules/ip-lockdown) with Managed Node Groups.

Which flavor of worker pools to use depends on your infrastructure needs. Note that you can have both managed and self
managed worker pools on a single EKS cluster, should you find the need for additional customizations.

Here is a list of additional tradeoffs to consider between the two flavors:

|                                 | Managed Node Groups                                                                                                        | Self Managed Node Groups                                                                                                 |
|---------------------------------|----------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| Graceful Scale in and Scale out | Supported automatically without needing additional tooling.                                                                | Requires specialized tooling (e.g `kubergrunt`) to implement.                                                            |
| Boot scripts                    | Not supported.                                                                                                             | Supported via user-data scripts in the ASG configuration.                                                                |
| OS                              | Only supports Amazon Linux.                                                                                                | Supports any arbitrary AMI, including Windows.                                                                           |
| SSH access                      | Only supports EC2 key pair, and restrictions by Security Group ID.                                                         | Supports any PAM customized either in the AMI or boot scripts. Also supports any arbitrary security group configuration. |
| EBS Volumes                     | Only supports adjusting the root EBS volume.                                                                               | Supports any EBS volume configuration, including attaching additional block devices.                                     |
| ELB                             | Supports automatic configuration via Kubernetes mechanisms. There is no way to manually register target groups to the ASG. | Supports both automatic configuration by Kubernetes, and manual configuration with target group registration.            |
| GPU support                     | Supported via the GPU compatible EKS Optimized AMI.                                                                        | Supported via a GPU compatible AMI.                                                                                      |


## How do I enable cluster auto-scaling?

This module will not automatically scale in response to resource usage by default, the
`autoscaling_group_configurations.*.max_size` option is only used to give room for new instances during rolling updates.
To enable auto-scaling in response to resource utilization, deploy the [Kubernetes Cluster Autoscaler module](../eks-k8s-cluster-autoscaler).

Note that the cluster autoscaler supports ASGs that manage nodes in a single availability zone or ASGs that manage nodes in multiple availability zones. However, there is a caveat:

- If you intend to use EBS volumes, you need to make sure that the autoscaler scales the correct ASG for pods that are localized to the availability zone. This is because EBS volumes are local to the availability zone. You need to carefully provision the managed node groups such that you have one group per AZ if you wish to use the cluster autoscaler in this case, which you can do by ensuring that the `subnet_ids` in each `autoscaling_group_configurations` input map entry come from the same AZ.

- You can certainly use a single ASG that spans multiple AZs if you don't intend to use EBS volumes.

- AWS now supports EFS as a persistent storage solution with EKS. This can be used with ASGs that span a single or multiple AZs.

Refer to the [Kubernetes Autoscaler](https://github.com/kubernetes/autoscaler) documentation for more details.


## How do I roll out an update to the instances?

Due to the way managed node groups work in Terraform, currently there is no way to rotate the instances without downtime
when using terraform. Changes to the AMI or instance type will automatically cause the node group to be replaced.
Additionally, the current resource does not support a mechanism to create the new group before destroying (the resource
does not support `name_prefix`, and you can't create a new node group with the same name). As such, a naive update to
the properties of the node group will likely lead to a period of reduced capacity as terraform replaces the groups.

To avoid downtime when updating your node groups, use a [blue-green
deployment](https://martinfowler.com/bliki/BlueGreenDeployment.html):

1. Provision a new node group with the updated, desired properties. You can do this by adding a new entry into the input
   map `var.node_group_configurations`.
1. Apply the updated config using `terraform apply` to create the replacement node group.
1. Once the new node group scales up, remove the old node group configuration from the input map.
1. Apply the updated config using `terraform apply` to remove the old node group. The managed node group will
   gracefully scale down the nodes in Kubernetes (honoring
   [PodDisruptionBudgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)) before terminating them.
   During this process, the workloads will reschedule to the new nodes.

## How do I perform a blue green release to roll out new versions of the module?

Gruntwork tries to provide migration paths that avoid downtime when rolling out new versions of the module. These are
usually implemented as feature flags, or a list of state migration calls that allow you to avoid a resource recreation.
However, it is not always possible to avoid a resource recreation with Managed Node Groups.

When it is not possible to avoid resource recreation, you can perform a blue-green release of the entire worker pool. In
this deployment model, you can deploy a new worker pool using the updated module version, and migrate the Kubernetes
workload to the new cluster prior to spinning down the old one.

The following are the steps you can take to perform a blue-green release for this module:

- Add a new module block that calls the `eks-cluster-managed-workers` module using the new version, leaving the old module block
  with the old version untouched. E.g.,

      # old version
      module "workers" {
        source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-managed-workers?ref=v0.37.2"
        # other args omitted for brevity
      }

      # new version
      module "workers_next_version" {
        source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-managed-workers?ref=v0.38.0"
        # other args omitted for brevity
      }

  This will spin up the new worker pool on the updated version in parallel with the old workers, without touching the
  old ones.

- Make sure to add the IAM role for the new worker set to the `aws-auth` ConfigMap so that the workers can authenticate
  to the Kubernetes API. This can be done by adding the `eks_worker_iam_role_arn` output of the new module block to the
  `eks_worker_iam_role_arns` input list for the module call to `eks-k8s-role-mapping`.

- Verify that the new workers are registered to the Kubernetes cluster by checking the output of `kubectl get nodes`. If
  the nodes are not in the list, or don't reach the `Ready` state, you will want to troubleshoot by introspecting the
  system logs.

- Once the new workers are up and registered to the Kubernetes Control Plane, you can run `kubectl cordon` and `kubectl
  drain` on each instance in the old ASG to transition the workload over to the new worker pool. `kubergrunt` provides
  [a helper command](https://github.com/gruntwork-io/kubergrunt/#drain) to make it easier to run this:

      kubergrunt eks drain --asg-name my-asg-a --asg-name my-asg-b --asg-name my-asg-c --region us-east-2

  This command will cordon and drain all the nodes associated with the given ASGs.

- Once the workload is transitioned, you can tear down the old worker pool by dropping the old module block and running
  `terraform apply`.
