# EKS Cluster Control Plane Module

This Terraform Module launches an [Elastic Container Service for Kubernetes
Cluster](https://docs.aws.amazon.com/eks/latest/userguide/clusters.html).

This module is responsible for the EKS Control Plane in [the EKS cluster topology](#what-is-an-eks-cluster). You must
launch worker nodes in order to be able to schedule pods on your cluster. See the [eks-cluster-workers
module](/modules/eks-cluster-workers) for managing EKS worker nodes.


## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See the [examples](/examples) folder for example usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See [outputs.tf](./outputs.tf) for all the variables that are outputed by this module.
* This module depends on a packaged python binary, which requires a working python install.
* This module depends on [`kubectl`](https://kubernetes.io/docs/tasks/tools/install-kubectl/).
* See [How do I authenticate kubectl to the EKS cluster?](/core-concepts.md#how-to-authenticate-kubectl) for information on how
  to authenticate kubectl.
  * You will need to install [`kubectl`](https://kubernetes.io/docs/tasks/tools/install-kubectl/) to follow the
    instructions.
  * If you wish to use the automatic configuration, you will need
    [`kubergrunt`](https://github.com/gruntwork-io/kubergrunt). Refer to the `kubergrunt` documentation for installation
    instructions.


## What is the EKS Control Plane?

The EKS Control Plane is a managed service entrirely managed by AWS. This contains the resources and endpoint to run and
access the [Kubernetes master components](https://kubernetes.io/docs/concepts/overview/components/#master-components).
The resources are deployed into your VPC so that they inherit the network rules you configure for your VPC.

Specifically, the control plane consists of:

- [`etcd`](https://coreos.com/etcd/): A distributed key value store used by Kubernetes to hold the metadata and cluster
  state.
- `kube-apiserver`: Web service that exposes the Kubernetes API. This is the main entrypoint for interacting with the
  Kubernetes cluster.
- `kube-scheduler`: This component is responsible for watching for newly created Pods on the cluster, and scheduling
  them on to the available worker nodes.
- `kube-controller-manager`: This component is responsible for executing the controller logic. Controllers are
  responsible for managing the Pods on the cluster. For example, you can use a
  [`Deployment`](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) controller to ensure that a
  specified number of replicas of a Pod is running on the cluster.
- `cloud-controller-manager`: This component is responsible for managing cloud components that Kubernetes will manage.
  This includes resources like the
  [`LoadBalancers`](https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/).

You can read more about the different components of EKS in [the project README](/core-concepts.md#what-is-an-eks-cluster).


## What security group rules are created?

This module will create a security group for the EKS cluster master nodes to allow them to function as a Kubernetes
cluster. The rules are based on [the recommendations provided by
AWS](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html) for configuring an EKS cluster.


### <a name="how-to-extend-security-group"></a>How do you add additional security group rules?

To add additional security group rules to the EKS cluster master nodes, you can use the
[aws_security_group_rule](https://www.terraform.io/docs/providers/aws/r/security_group_rule.html) resource, and set its
`security_group_id` argument to the Terraform output of this module called `eks_control_plane_security_group_id`. For example, here is how you can allow the master nodes
in this cluster to allow incoming HTTPS requests on port 443 from an additional security group that is not the workers:

```hcl
module "eks_cluster" {
  # (arguments omitted)
}

resource "aws_security_group_rule" "allow_inbound_http_from_anywhere" {
  type      = "ingress"
  from_port = 443
  to_port   = 443
  protocol  = "tcp"

  security_group_id        = module.eks_cluster.eks_control_plane_security_group_id
  source_security_group_id = var.source_aws_security_group_id
}
```


## What IAM policies are attached to the EKS Cluster?

This module will create IAM roles for the EKS cluster master nodes with the minimum set of policies necessary
for the cluster to function as a Kubernetes cluster. The policies attached to the roles are the same as those documented
in [the AWS getting started guide for EKS](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html).

### How do you add additional IAM policies?

To add additional IAM policies to the EKS cluster master nodes, you can use the
[aws_iam_role_policy](https://www.terraform.io/docs/providers/aws/r/iam_role_policy.html) or
[aws_iam_policy_attachment](https://www.terraform.io/docs/providers/aws/r/iam_policy_attachment.html) resources, and set
the IAM role id to the Terraform output of this module called `eks_control_plane_iam_role_name` for the master nodes. For
example, here is how you can allow the master nodes in this cluster to access an S3 bucket:

```hcl
module "eks_cluster" {
  # (arguments omitted)
}

resource "aws_iam_role_policy" "access_s3_bucket" {
    name = "access_s3_bucket"
    role = module.eks_cluster.eks_control_plane_iam_role_name
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


## How do I associate IAM roles to the Pods?

**NOTE: This configuration depends on [kubergrunt](https://github.com/gruntwork-io/kubergrunt), minimum version 0.5.3**

This module will set up the OpenID Connect Provider that can be used with the [IAM Roles for Service
Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) feature. When this
feature is enabled, you can exchange the Kubernetes Service Account Tokens for IAM role credentials using the
`sts:AssumeRoleWithWebIdentity` AWS API in the STS service.

To allow Kubernetes Service Accounts to assume the roles, you need to grant the proper assume role IAM policies to the
role that is being assumed. Specifically, you need to:

- Allow the OpenID Connect Provider to assume the role.
- Specify any conditions on assuming the role. You can restrict by:
    - Service Accounts that can assume the role
    - Which Namespaces have full access to assume the role (meaning, all Service Accounts in the Namespace can assume
      that role).

You can use the
[eks-iam-role-assume-role-policy-for-service-account module](../eks-iam-role-assume-role-policy-for-service-account) to
construct the policy using a more convenient interface. Refer to the module documentation for more info.

Once you have an IAM Role that can be assumed by the Kubernetes Service Account, you can configure your Pods to exchange
them for IAM role credentials. EKS will automatically configure the correct environment variables that the SDK expects
on the Pods when you annotate the associated Service Account with the role it should assume.

The following shows an example Kubernetes manifest that configures the Service Account to assume the IAM role `arn:aws:iam::123456789012:role/myrole`:

```
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/myrole
```

Note that the AWS SDK will automatically assume the role if you are using a compatible version. The following is a list
of the minimum SDK version for various platforms that support the `AWS_WEB_IDENTITY_TOKEN_FILE` environment variable
used by IRSA:

```
Java   1.11.623
Java2  2.7.36
Go     1.23.13
Python 1.9.220
Node   2.521.0
Ruby   2.11.345
PHP    3.110.7
.NET   3.3.580.0
```


## How do I SSH into the nodes?

By design, AWS does not allow you to SSH into the master nodes of an EKS cluster.


## API Access and Networking

By default this module enables both the Public Kubernetes API Endpoint and the Private Kubernetes API VPC Endpoint. The
public endpoint is used for network requests originating from outside the VPC, while requests originating from within
the VPC (including worker nodes) use the private VPC endpoint.

To restrict access to the public endpoint, you can use the `endpoint_public_access_cidrs` input variable. When set, only
requests originating from the list of CIDR blocks will be allowed access from outside the VPC.

To restrict access to the private VPC endpoint, you can use the `endpoint_private_access_cidrs` and
`endpoint_private_access_security_group_ids` input variables. When set, requests originating from within the VPC and from the
list of CIDRs/Security Group IDs will be allowed access.

Note that even if an IP is allowed access to the public endpoint via the `endpoint_public_access_cidrs` variable, if that IP originates from within the VPC of the EKS cluster, that request will not be allowed unless it is allowed to access the private endpoint. That is, setting `endpoint_public_access_cids = 0.0.0.0/0`, will not automatically allow access to the Kubernetes API from within the VPC. You must configure `endpoint_private_access_cidrs` or `endpoint_private_access_security_group_ids` to allow access to requests originating from within the VPC.

The public endpoint makes operations easier when configuring the EKS cluster control plane. However, for added security,
you can disable the public endpoint by setting the `endpoint_public_access` input variable to `false`.


## Control Plane Logging

EKS supports exporting various logs to CloudWatch. By default, none of the logging options are enabled by this module.
To enable logs, you can pass in the relevant type strings to the `enabled_cluster_log_types` input variable. For
example, to enable API server and audit logs, you can pass in the list `["api", "audit"]`. See [the official
documentation](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html) for a list of available log
types.


## How do I configure encryption at rest for Secrets?

Kubernetes [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) are resources in the cluster designed to
store and manage sensitive information. These behave like
[ConfigMaps](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/), but have a few extra
properties that enhance their security profile.

All EKS clusters encrypt Kubernetes Secrets at rest at the disk level using shared AWS managed KMS keys. Alternatively,
you can provide your own KMS Customer Master Key (CMK) to use for envelope encryption. In envelope encryption,
Kubernetes will use the provided CMK to encrypt the secret keys used to encrypt the Kubernetes Secrets. For each Secret,
Kubernetes will dynamically generate a new data encryption key (DEK) for the purposes of encrypting and decrypting the
secret. This key is then encrypted using the provided CMK before being stored in the cluster. In this way, you can
manage access to the Secret (indirectly by restricting access to the DEK) through the KMS permissions. For example, you
can disable all access to any Secrets in the EKS cluster by removing the permissions to encrypt/decrypt using the KMS
key in case of a breach.

To enable envelope encryption, provide the KMS key ARN you would like to use using the variable
`secret_envelope_encryption_kms_key_arn`. Note that if the KMS key belongs to another account, you will need to grant
access to manage permissions for the key to the account holding the EKS cluster. See [Allowing users in other accounts
to use a CMK](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-modifying-external-accounts.html) from
the official AWS docs for more information.


## How do I deploy Pods on Fargate?

[AWS Fargate](https://aws.amazon.com/fargate/) is an AWS managed infrastructure for running ECS Tasks and EKS Pods
without any worker nodes. With Fargate, your EKS Pods will automatically be assigned a node from a shared pool of VMs
that are fully managed by AWS. This means that you can focus entirely on the application you are deploying and not have
to worry about servers, clusters, and the underlying infrastructure as a whole.

To use Fargate with your EKS Pods, you need to create a Fargate Profile to select the Pods that you want to run. You can
use Namespaces and Labels to restrict which Pods of the EKS cluster will run on Fargate. This means that Pods that match
the specifications of the Fargate Profile will automatically be deployed to Fargate without any further configuration.

Some additional notes on using Fargate:

- Fargate Profiles require a Pod Execution Role, which is an IAM role that will be assigned to the underlying
  `kubelet` of the Fargate instance. At a minimum, this role must be given enough permissions to pull the images
  used by the Pod. Note that **this role is NOT made available to the Pods!** Use [the IAM Role for Service Accounts
  (IRSA) feature of EKS](#how-do-i-associate-iam-roles-to-pods) to assign IAM roles for use by the Pods themselves.
- If you set the input variable `schedule_control_plane_services_on_fargate` on this module, the module will
  automatically allocate a Fargate Profile that selects the core control plane services deployed in the `kube-system`
  Namespace (e.g., `core-dns`). This profile is highly selective and will most likely not match any other Pods in the
  cluster. To deploy additional Pods onto Fargate, you must manually create Fargate Profiles that select those Pods (use
  [the `aws_eks_fargate_profile` resource](https://www.terraform.io/docs/providers/aws/r/eks_fargate_profile.html) to
  provision Fargate Profiles with Terraform). The Pod Execution Role created by the module may be reused for other
  Fargate Profiles.
- Fargate does not support DaemonSets. This means that you can't rely on the [eks-container-logs](../eks-container-logs)
  module to forward logs to CloudWatch. Instead, you need to manually configure a sidecar `fluentd` container that
  forwards the log entries to CloudWatch Logs. Refer to [this AWS blog
  post](https://aws.amazon.com/blogs/containers/how-to-capture-application-logs-when-using-amazon-eks-on-aws-fargate/)
  for documentation on how to setup `fluentd` with Fargate.

## How do I upgrade the Kubernetes Version of the cluster?

To upgrade the minor version of Kubernetes deployed on the EKS cluster, you need to update the `kubernetes_version`
input variable. **You must upgrade one minor version at a time**, as EKS does not support upgrading by more than one
minor version.

### Updating core components

When you upgrade the cluster, you can update the cluster core components with either Kubergrunt or
using [Amazon EKS add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html). If `use_upgrade_cluster_script` is
set to `true` then `kubergrunt` is used to update the core components. If `enable_eks_addons` is set to `true`,
then EKS add-ons are used. If both are set to true, then `enable_eks_addons` takes precedence.

Note that customized VPC CNI configurations (e.g., enabling prefix delegation) is not fully supported with add-ons as the 
automated add-on lifecycles could potentially undo the configuration changes. As such, it is not recommended to use EKS 
add-ons if you wish to use the VPC CNI customization features.

#### Using Kubergrunt

When you bump minor versions, the module will automatically update the deployed Kubernetes components as described in
the [official upgrade guide](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html). This is handled by
`kubergrunt` (**minimum version 0.6.2**) using the [eks
sync-core-components](https://github.com/gruntwork-io/kubergrunt#sync-core-components) command, which will look up the
deployed Kubernetes version and make the required `kubectl` calls to deploy the updated components.

#### Using EKS add-ons

If you have specified explicit `addon_version` in `eks_addons`, you must update the `addon_version` to match
the cluster version. All add-on version details can be found in [the official documentation](https://docs.aws.amazon.com/eks/latest/userguide/add-ons-configuration.html).
If you omit the `addon_version`, correct versions are automatically applied.

### Updating worker node AMIs

Note that you must update the nodes to use the corresponding `kubelet` version as well. This means that when you update
minor versions, you will also need to update the AMIs used by the worker nodes to match the version and rotate the
workers. For more information on rotating worker nodes, refer to [How do I roll out an update to the
instances?](../eks-cluster-workers/README.md#how-do-i-roll-out-an-update-to-the-instances) in the `eks-cluster-workers`
module README.

### Detailed upgrade steps

Here are detailed steps on how to update your cluster:

1. Bump the `kubernetes_version` in the module variable to the next minor version in your module block for
   `eks-cluster-control-plane`.
1. For self managed worker nodes (`eks-cluster-workers` module), build a new AMI for your worker nodes that depend on
   an EKS optimized AMI for the Kubernetes minor version. Update the `asg_default_instance_ami` variable to the new AMI in
   your module block for `eks-cluster-workers`.
1. Apply the changes. This will update the Kubernetes version on the EKS control plane, and stage the updates for your
   workers. Note that your cluster will continue to function as Kubernetes supports worker nodes that are 1 minor
   version behind.
1. Roll out the AMI update using `kubergrunt eks deploy`.

## How do I increase the number of Pods for my worker nodes?

By default, this module deploys an EKS cluster that uses the [AWS VPC CNI](https://github.com/aws/amazon-vpc-cni-k8s)
to manage internal networking for the cluster. This plugin works to source IP addresses from the assigned VPC of the
cluster to assign to each Pod within Kubernetes.

The AWS VPC CNI works by allocating secondary IP addresses and Elastic Network Interfaces to the worker nodes to assign
to the Pods that are scheduled on them. This means that there is a limit on the number of IP addresses that can be made
available to the Pods per node. You can look up the various limits per instance type in [the official AWS
documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI).

Unfortunately, these limits are typically significantly less than the available compute and memory resources that the
node has. This means that the worker nodes will often hit the IP address limit well before it reaches compute and memory
limits of the nodes, greatly reducing the Pod scheduling potential of your cluster.

To address this, you can use prefix delegation mode for managing the available IP addresses on your workers. In prefix
delegation mode, each ENI is assigned an IPv4 address prefix instead of an individual IP for each secondary address
slot. This means that for each individual IP address that was previously available, you now have up to 16 IP addresses
that the worker node can assign to the container, greatly increasing the number of IP addresses that each worker can
assign to the Pods.

To enable prefix delegation mode, set the `vpc_cni_enable_prefix_delegation` input variable to `true`.

Note that prefix delegation mode greatly increases the number of IP addresses that each worker node will keep in standby
for the Pods. This is because worker nodes can only allocate IP addresses in blocks of 16. This means that each worker
will consume a minimum of 16 IP addresses from the VPC, and potentially more depending on the number of Pods that are
scheduled (e.g., a worker with 17 Pods will consume 32 IP addresses - 2 prefixes of 16 IP addresses each).

You can tweak the allocation behavior by configuring the `vpc_cni_warm_ip_target` and `vpc_cni_minimum_ip_target`
variables.

The warm IP target indicates the target number of IP addresses each node should have available. For example, if you set
the warm IP target to 5, then the node will only preallocate the next prefix of 16 IP addresses when the current prefix
reaches 68.75% utilization (11 out of 16 used). On the other hand, if the warm IP target is set to 16 (the default),
then the next prefix will be allocated as soon as one Pod is scheduled on the current prefix.

The minimum IP target indicates the target number of IP addresses that should be available on each node during
initialization. For example, if you set this to 32, then each node will start with 2 prefixes being preallocated at
launch time. On the other hand, if the minimum IP target is 16 (the default), then each node starts with only 1 prefix.

You can learn more details about how prefix delegation mode works, and the behavior of warm IP target and minimum IP
target in [the official AWS blog
post](https://aws.amazon.com/blogs/containers/amazon-vpc-cni-increases-pods-per-node-limits/) about the feature.


## Troubleshooting

### AccessDenied when provisioning Services of LoadBalancer type

On brand new accounts, AWS needs to provision a new Service Linked Role for ELBs when an ELB is first provisioned. EKS
automatically creates the Service Linked Role if it doesn't exist, but it needs more permissions than is provided by
default. Since the permission is only needed as a one time thing, binding the necessary permissions would be a violation
of least privileges.

As such, this module does not bind the requisite permissions, and instead we recommend taking one of the following
approaches:

- Create a one time wrapper module that appends the following IAM permissions to the control plane IAM role (the output
  `eks_master_iam_role_arn`), and deploy the EKS cluster with `LoadBalancer` service:

        ec2:DescribeAccountAttributes
        ec2:DescribeInternetGateways

- Create an ELB using the AWS console, or the modules in [terraform-aws-load-balancer](https://github.com/gruntwork-io/terraform-aws-load-balancer/).

- Create the service linked role using [the Landing Zone
  modules](https://github.com/gruntwork-io/terraform-aws-service-catalog/tree/master/modules/landingzone).
