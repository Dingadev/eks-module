# EKS Cluster Workers Module

**This module provisions self managed ASGs, in contrast to [EKS Managed Node Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html). See the [eks-cluster-managed-workers](../eks-cluster-managed-workers) module for a module to deploy Managed Node Groups.**

This Terraform Module launches worker nodes for an [Elastic Container Service for Kubernetes
Cluster](https://docs.aws.amazon.com/eks/latest/userguide/clusters.html) that you can use to run Kubernetes Pods and
Deployments.

This module is responsible for the EKS Worker Nodes in [the EKS cluster
topology](/modules/eks-cluster-control-plane/README.md#what-is-an-eks-cluster). You must launch a control plane in order
for the worker nodes to function. See the [eks-cluster-control-plane module](/modules/eks-cluster-control-plane) for
managing an EKS control plane.


## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See the [examples](/examples) folder for example usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See [outputs.tf](./outputs.tf) for all the variables that are outputed by this module.


## Differences with managed node groups

See the [Differences with self managed workers] section in the documentation for [eks-cluster-managed-workers
module](../eks-cluster-managed-workers) for a detailed overview of differences with EKS Managed Node Groups.


## What should be included in the user-data script?

In order for the EKS worker nodes to function, it must register itself to the Kubernetes API run by the EKS control
plane. This is handled by the bootstrap script provided in the EKS optimized AMI. The user-data script should call the
bootstrap script at some point during its execution. You can get this information from the [eks-cluster-control-plane
module](/modules/eks-cluster-control-plane).

For an example of a user data script, see the [eks-cluster example's user-data.sh
script](/examples/eks-cluster-with-iam-role-mappings/user-data/user-data.sh).

You can read more about the bootstrap script in [the official documentation for EKS](https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html).

## Which security group should I use?

EKS clusters using Kubernetes version 1.14 and above automatically create a managed security group known as the cluster
security group. The cluster security group is designed to allow all traffic from the control plane and worker nodes to
flow freely between each other. This security group has the following rules:

- Allow Kubernetes API traffic between the security group and the control plane security group.
- Allow all traffic between instances of the security group ("ingress all from self").
- Allow all outbound traffic.

EKS will automatically use this security group for the underlying worker instances used with managed node groups or
Fargate. This allows traffic to flow freely between Fargate Pods and worker instances managed with managed node groups.

You can read more about the cluster security group in [the AWS
docs](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html#cluster-sg).

By default this module will attach two security groups to the worker nodes managed by the module:

- The cluster security group.
- A custom security group that can be extended with additional rules.

You can attach additional security groups to the nodes using the `var.additional_security_group_ids` input variable.

If you would like to avoid the cluster security group (this is useful if
you wish to isolate at the network level the workers managed by this module from other workers in your cluster like
Fargate, Managed Node Groups, or other self managed ASGs), set the `use_cluster_security_group` input variable to
`false`. With this setting, the module will apply recommended security group rules to the custom group to allow the node
to function as a EKS worker. The rules used for the new security group are based on [the recommendations provided by
AWS](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html#control-plane-worker-node-sgs) for configuring
an EKS cluster.

### <a name="how-to-extend-security-group"></a>How do you add additional security group rules?

To add additional security group rules to the EKS cluster worker nodes, you can use the
[aws_security_group_rule](https://www.terraform.io/docs/providers/aws/r/security_group_rule.html) resource, and set its
`security_group_id` argument to the Terraform output of this module called `eks_worker_security_group_id` for the worker
nodes. For example, here is how you can allow the EC2 Instances in this cluster to allow incoming HTTP requests on port
8080:

```hcl
module "eks_workers" {
  # (arguments omitted)
}

resource "aws_security_group_rule" "allow_inbound_http_from_anywhere" {
  type = "ingress"
  from_port = 8080
  to_port = 8080
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = "${module.eks_workers.eks_worker_security_group_id}"
}
```

**Note**: The security group rules you add will apply to ALL Pods running on these EC2 Instances. There is currently no
way in EKS to manage security group rules on a per-Pod basis. Instead, rely on [Kubernetes Network
Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) to restrict network access within a
Kubernetes cluster.


## What IAM policies are attached to the EKS Cluster?

This module will create IAM roles for the EKS cluster worker nodes with the minimum set of policies necessary
for the cluster to function as a Kubernetes cluster. The policies attached to the roles are the same as those documented
in [the AWS getting started guide for EKS](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html).

### How do you add additional IAM policies?

To add additional IAM policies to the EKS cluster worker nodes, you can use the
[aws_iam_role_policy](https://www.terraform.io/docs/providers/aws/r/iam_role_policy.html) or
[aws_iam_policy_attachment](https://www.terraform.io/docs/providers/aws/r/iam_policy_attachment.html) resources, and set
the IAM role id to the Terraform output of this module called `eks_worker_iam_role_name` for the worker nodes. For
example, here is how you can allow the worker nodes in this cluster to access an S3 bucket:

```hcl
module "eks_workers" {
  # (arguments omitted)
}

resource "aws_iam_role_policy" "access_s3_bucket" {
    name = "access_s3_bucket"
    role = "${module.eks_workers.eks_worker_iam_role_name}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect":"Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::examplebucket/*"
    }
  ]
}
EOF
}
```

**Note**: The IAM policies you add will apply to ALL Pods running on these EC2 Instances. See the [How do I associate
IAM roles to the Pods?](/modules/eks-cluster-control-plane/README.md#how-do-i-associate-iam-roles-to-the-pods) section of the
`eks-cluster-control-plane` module README for more fine-grained allocation of IAM credentials to Pods.

## How do I SSH into the nodes?

This module provides options to allow you to SSH into the worker nodes of an EKS cluster that are managed by this
module. To do so, you must first use an AMI that is configured to allow SSH access. Then, you must setup the auto
scaling group to launch instances with a known keypair that you have access to by using the
`cluster_instance_keypair_name` option of the module. Finally, you need to configure the security group of the worker
node to allow access to the port for SSH by extending the security group of the worker nodes by following [the guide
above](#how-to-extend-security-group). This will allow SSH access to the instance using the specified keypair, provided
the server AMI is configured to run the ssh daemon.

**Note**: Using a single key pair shared with your whole team for all of your SSH access is not secure. For a more
secure option that allows each developer to use their own SSH key, and to manage server access via IAM or your Identity
Provider (e.g. Google, ADFS, Okta, etc), see [ssh-grunt](https://github.com/gruntwork-io/terraform-aws-security/tree/master/modules/ssh-grunt).


## How do I roll out an update to the instances?

Terraform and AWS do not provide a way to automatically roll out a change to the Instances in an EKS Cluster. Due to
Terraform limitations (see [here for a discussion](https://github.com/gruntwork-io/terraform-aws-ecs/pull/29)), there is
currently no way to implement this purely in Terraform code. Therefore, we've embedded this functionality into
`kubergrunt` that can do a zero-downtime roll out for you.

Refer to the [`deploy` subcommand documentation](https://github.com/gruntwork-io/kubergrunt#deploy) for more details on how this works.

## How do I perform a blue green release to roll out new versions of the module?

Gruntwork tries to provide migration paths that avoid downtime when rolling out new versions of the module. These are
usually implemented as feature flags, or a list of state migration calls that allow you to avoid a resource recreation.
However, it is not always possible to avoid a resource recreation with AutoScaling Groups.

When it is not possible to avoid resource recreation, you can perform a blue-green release of the worker pool. In this
deployment model, you can deploy a new worker pool using the updated version, and migrate the Kubernetes workload to the
new cluster prior to spinning down the old one.

The following are the steps you can take to perform a blue-green release for this module:

- Add a new module block that calls the `eks-cluster-workers` module using the new version, leaving the old module block
  with the old version untouched. E.g.,

      # old version
      module "workers" {
        source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-workers?ref=v0.37.2"
        # other args omitted for brevity
      }

      # new version
      module "workers_next_version" {
        source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-workers?ref=v0.38.0"
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



## How do I enable cluster auto-scaling?

This module will not automatically scale in response to resource usage by default, the
`autoscaling_group_configurations.*.max_size` option is only used to give room for new instances during rolling updates.
To enable auto-scaling in response to resource utilization, you must set the `include_autoscaler_discovery_tags` input
variable to `true` and also deploy the [Kubernetes Cluster Autoscaler module](../eks-k8s-cluster-autoscaler).

Note that the cluster autoscaler supports ASGs that manage nodes in a single availability zone or ASGs that manage nodes in multiple availability zones. However, there is a caveat:

- If you intend to use EBS volumes, you need to make sure that the autoscaler scales the correct ASG for pods that are localized to the availability zone. This is because EBS volumes are local to the availability zone. You need to carefully provision the managed node groups such that you have one group per AZ if you wish to use the cluster autoscaler in this case, which you can do by ensuring that the `subnet_ids` in each `autoscaling_group_configurations` input map entry come from the same AZ.

- You can certainly use a single ASG that spans multiple AZs if you don't intend to use EBS volumes.

- AWS now supports EFS as a persistent storage solution with EKS. This can be used with ASGs that span a single or multiple AZs.

Refer to the [Kubernetes Autoscaler](https://github.com/kubernetes/autoscaler) documentation for more details.
