# Background

## What is Kubernetes?

[Kubernetes](https://kubernetes.io) is an open source container management system for deploying, scaling, and managing
containerized applications. Kubernetes is built by Google based on their internal proprietary container management
systems (Borg and Omega). Kubernetes provides a cloud agnostic platform to deploy your containerized applications with
built in support for common operational tasks such as replication, autoscaling, self-healing, and rolling deployments.

You can learn more about Kubernetes from [the official documentation](https://kubernetes.io/docs/tutorials/kubernetes-basics/).


## What is Elastic Container Service for Kubernetes (EKS)?

Elastic Container Service for Kubernetes is the official AWS solution for running a [Kubernetes](https://kubernetes.io)
cluster within AWS. EKS provisions and manages the [Kubernetes Master
Components](https://kubernetes.io/docs/concepts/overview/components/#master-components) for you, removing a significant
operational burden for running Kubernetes. This means that EKS will automatically handle provisioning and scaling the
master components such that it is highly available and secure for your needs.

You can learn more about EKS from [the official
documentation](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html).


## What is an EKS Cluster?

An EKS cluster represents a Kubernetes cluster that is available within your VPC to be used for scheduling your Docker
containers as [Kubernetes Pods](https://kubernetes.io/docs/concepts/workloads/pods/pod/). EKS consists of two major
components that combine to formulate an EKS cluster, mapping to their Kubernetes counterparts:

- EKS Control Plane: Contains the resources and endpoint to run and access the Kubernetes master components within your
  VPC. The underlying resources are entirely managed by AWS. These correspond to
  [Kubernetes master components](https://kubernetes.io/docs/concepts/overview/components/#master-components).
- EKS Worker Nodes: Contains the resources that run your applications scheduled on the cluster as
  [Kubernetes Pods](https://kubernetes.io/docs/concepts/workloads/pods/pod/).
  These are EC2 instances that you provision with a special AMI designed to connect to the control plane so that it is
  available within your Kubernetes cluster. These correspond to
  [Kubernetes node components](https://kubernetes.io/docs/concepts/overview/components/#node-components).

You can read more about the individual components in [the official Kubernetes
docs](https://kubernetes.io/docs/concepts/overview/components).

This Module will provision both the EKS Control Plane and EKS Worker Nodes, utilizing an Auto Scaling Group so that
failed worker nodes will automatically be replaced, and we can easily scale the worker nodes in the cluster. You can
then use other modules in this package to package your Docker containers into Pods that can then be deployed on to the
EKS cluster.


## ECS vs EKS

[EC2 Container Service (ECS)](https://aws.amazon.com/ecs/) and [Elastic Container Service for
Kubernetes](https://aws.amazon.com/eks) are two AWS solutions for running Docker containers on EC2 instances or AWS
managed machines (via [Fargate](https://aws.amazon.com/fargate/) in the case of ECS). ECS is a proprietary solution by
AWS that provides a way of deploying your containerized applications on AWS resources without having to manually manage
them. EKS is a new offering by AWS that provides a managed Kubernetes experience on AWS resources with first class
support for AWS concepts like VPC, IAM roles, and Security Groups. Unlike ECS which uses proprietary technology, EKS
runs an open source platform (Kubernetes). As such, you can interface with it using the Kubernetes ecosystem of tools
and resources (e.g `kubectl`), just like any other Kubernetes cluster.

Which service you decide to go with is entirely dependent on your infrastructure needs. With ECS Fargate, you can focus
entirely on the application you are deploying and not have to worry about servers, clusters, and the underlying
infrastructure as a whole. However, if you want more control over your resources and infrastructure, you can use ECS
with EC2 instances. The downside with both is that you have to use a proprietary API to interact with the service that
is not portable outside of AWS (including no way to run ECS on your local computer for testing).

On the other hand, if you want to leverage existing tools and knowledge from the Kubernetes community, you can use EKS
instead. The code you develop to interface with EKS are to an extent portable to other Kubernetes clusters as well.
Furthermore, if you already have a Kubernetes cluster, you can reuse all of your kubernetes configuration. The downside
to using EKS over ECS, however, is that ECS provides simpler primitives for running your workloads, and mesh really well
with existing AWS infrastructure like Application and Network Load Balancers.

Here is a list of additional tradeoffs to consider between the two services:

- Kubernetes is cloud agnostic. All of the major cloud providers support a managed Kubernetes experience
  ([GKE](https://cloud.google.com/kubernetes-engine/), [EKS](https://aws.amazon.com/eks),
  [AKS](https://docs.microsoft.com/en-us/azure/aks/)). You can even deploy a Kubernetes cluster on prem on your own
  hardware, or run it locally for testing. ECS on the other hand is proprietary and only works on AWS.
- Kubernetes, being open, has a larger community than ECS with a ton of resources available including plugins, books,
  guides, tools, etc.
- Kubernetes has a built in solution for secrets management that works on all deployments of Kubernetes. With ECS, you
  need to use an external service like KMS or Secret Manager, neither of which have first class support within ECS and
  do not work locally.
- Kubernetes has a mature data volume solution in
  [`StatefulSets`](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) that allow you to leverage
  the dynamic nature of your containers without worrying about persistence locality. ECS has volumes for persistent
  state in containers, but require localizing the containers with the volumes.
- Kubernetes has an official service discovery solution in the form of the DNS plugin that automatically allocates a
  FQDN that route to your containerized application. ECS requires additional configuration with an external DNS system
  (Route53) to achieve the same effect.
- ECS has native integration with AWS IAM roles so that each container can have its own IAM role/permissions to access
  AWS resources. Kubernetes requires a custom solution or third party plugin (e.g
  [kube2iam](https://github.com/jtblin/kube2iam)) to achieve the same effect.
- You only have to pay for the EC2 costs of worker nodes in ECS. EKS has a high premium for running the control plane,
  in addition to the EC2 costs of worker nodes.
- ECS has a simpler configuration setup and therefore is easier to learn and get started with compared to Kubernetes.
- As of October 2018, Terraform support for ECS is stronger than for Kubernetes.

If you would like to use ECS, Gruntwork also provides Modules for managing ECS resources in the
[`terraform-aws-ecs`](https://github.com/gruntwork-io/terraform-aws-ecs) repository.


## How do I authenticate kubectl to the EKS cluster?

The standard way to interact with a Kubernetes cluster is to use the
[`kubectl`](https://kubernetes.io/docs/reference/kubectl/overview/) commandline utility. However, in order to use
`kubectl` to access your EKS cluster, you need to first authenticate it to the cluster. EKS manages authentication to
Kubernetes based on AWS IAM roles. The IAM roles automatically translate to the corresponding role in Kubernetes via the
[Role Based Access Control (RBAC)](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) system that Kubernetes
uses to handle authorization of Kubernetes resources. By default the AWS IAM role used to provision the EKS cluster is
granted admin level permissions (`system:master` role) that allow you to perform almost anything on the cluster via
`kubectl`. You can add additional role mappings or modify the default one by using the [eks-k8s-role-mapping
module](./modules/eks-k8s-role-mapping/README.md). See the [module documentation](./modules/eks-k8s-role-mapping/README.md) for more
information.

To support all this, EKS requires `kubectl` to authenticate to an AWS IAM role. However, `kubectl` does not have a
native way to do this. There are a couple of ways to configure `kubectl` for authentication with IAM:

1. Beginning with AWS CLI version 1.16.156, you can use the `aws eks get-token` command.
1. Rely on the [AWS IAM Authenticator for Kubernetes](https://github.com/kubernetes-sigs/aws-iam-authenticator) utility embedded into
[`kubergrunt`](https://github.com/gruntwork-io/kubergrunt).

Both options use the AWS API to generate an authentication token that contains a signed request to fetch the information about the
assumed AWS IAM role. This token is forwarded to the Kubernetes API server by `kubectl`, which is then used by EKS to authenticate the
request to the assumed IAM role, and then inherit permissions for the mapped RBAC role.

You can learn more about the details of `aws eks get-token` in [the AWS CLI
docs](https://docs.aws.amazon.com/cli/latest/reference/eks/get-token.html).
Under the hood, EKS uses the AWS IAM Authenticator to manage authentication to the API. You can learn more about it in [the official
documentation](https://github.com/kubernetes-sigs/aws-iam-authenticator#how-does-it-work).

This Module provides several ways to help you setup `kubectl` to authenticate to the created EKS cluster. Note that
all of these methods assume you have a working `kubectl` and one of `kubergrunt` or AWS IAM authenticator installed.

You can follow the [Kubernetes client installation
instructions](https://kubernetes.io/docs/tasks/tools/install-kubectl/) to install `kubectl`.

You can install `kubergrunt` from the [Releases Page](https://github.com/gruntwork-io/kubergrunt/releases). You can
learn more about `kubergrunt` code from [the project
README](https://github.com/gruntwork-io/kubergrunt/blob/master/README.md).

The AWS IAM Authenticator requires a working go environment to install. You can follow the [project
README](https://github.com/kubernetes-sigs/aws-iam-authenticator) for installation instructions. Alternatively, you can
install one of the prebuilt binaries of the AWS IAM Authenticator provided by AWS. The download URL for each platform is
available in [the official documentation of AWS
EKS](https://docs.aws.amazon.com/eks/latest/userguide/configure-kubectl.html).

**Important Note**: On a new EKS cluster, the EKS worker nodes also rely on mapping their IAM role into a Kubernetes
RBAC role that provides access to the cluster. This is what allows the worker nodes to register themselves to the
control plane. Therefore, before you can schedule anything on the cluster, you must apply the [eks-k8s-role-mapping
module](./modules/eks-k8s-role-mapping/README.md) with the `eks_worker_iam_role_arn` output variable from this module. See the
[eks-cluster example](./examples/eks-cluster-with-iam-role-mappings/README.md) for an example of this in action.

### Automatic setup

The `eks-cluster-control-plane` module can configure `kubectl` to be able to authenticate with EKS as part of
provisioning the cluster. This Module uses the `kubergrunt` binary to create or update the `kubectl` config file with a
new context that can be used to interact with the newly provisioned EKS cluster. Set the `configure_kubectl` input
variable to `true` to turn on this behavior.

**Note**: This will only configure `kubectl` for the machine that provisions it. Other machines will need to be
separately configured.

You can call the `kubergrunt` binary outside of the Module. The binary expects the region where the EKS
cluster resides, as well as the name of the EKS cluster:

```bash
kubergrunt eks configure --eks-cluster-arn $EKS_CLUSTER_ARN
```

Alternatively, you can use [the AWS Command Line Interface
(CLI)](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html) built in EKS configure command:

```bash
aws --region $AWS_REGION eks update-kubeconfig --name $EKS_CLUSTER_NAME
```

### Manual setup

You can also setup `kubectl` manually using the provided outputs from this Module. This module will output a complete
`kubectl` config file under the output variable `eks_kubeconfig` that can be placed where you store your `kubectl` config
files. You must store the config file output and reference it when you run `kubectl` to authenticate against the
Kuberentes control plane managed by EKS. This option may be best if you have multiple Kubernetes cluster that you are
managing and need to distinguish the authentication config between the different clusters.
