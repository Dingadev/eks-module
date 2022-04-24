# EKS Cluster with Supporting Services

This example provisions an EKS cluster that:

- Has two dedicated worker node groups managed by separate ASGs for different functions:
    - `core` nodes: Worker nodes intended to run core services, such as `kiam`. These services require additional
      permissions to function, and therefore require a more locked down EC2 instance configuration.
    - `application` nodes: Worker nodes intended to run application services.
- Nodes are tagged with labels inherited from the EC2 instance tags, using the `map-ec2-tags-to-node-labels` script in
  [the eks-scripts module](/modules/eks-scripts).
- Deploys core admin services that provide various features:
    - FluentD for shipping Kubernetes logs (including container logs) to CloudWatch.
    - ALB Ingress Controller for exposing services using ALBs.
    - external-dns for tying Route 53 domains to exposed services.


## Prerequisites

This example depends on `Terraform`, `Packer`, and `kubergrunt`. You can also optionally install `kubectl` if
you would like explore the newly provisioned cluster. You can find instructions on how to install each tool below:

- [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html), minimum version: `1.0.0`
- [Packer](https://www.packer.io/intro/getting-started/install.html)
- [kubergrunt](https://github.com/gruntwork-io/kubergrunt#installation), minimum version: `0.6.2`
- (Optional) [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

Finally, before you begin, be sure to set up your AWS credentials as environment variables so that all the commands
below can authenticate to the AWS account where you wish to deploy this example. You can refer to our blog post series
on AWS authentication ([A Comprehensive Guide to Authenticating to AWS on the Command
Line](https://blog.gruntwork.io/a-comprehensive-guide-to-authenticating-to-aws-on-the-command-line-63656a686799)) for
more information.


## Overview

Unlike the other examples, this example is spread across multiple terraform submodules. Refer to [Why are there
multiple Terraform submodules in this example?](#why-are-there-multiple-terraform-submodules-in-this-example) for more
information on why the example is structured this way.

As such, you will be deploying the example through a multi step process involving the following steps:

1. [Create a new AMI with the helper scripts installed using `packer`](#create-a-new-ami-with-the-helper-scripts-installed)
1. [Apply Terraform Templates](#apply-terraform-templates)
  1. [Deploy EKS cluster](#deploy-eks-cluster)
  1. [Deploy Core Services](#deploy-core-services)
  1. [(Optional) Deploy Nginx](#optional-deploy-nginx)

Once the cluster is deployed, take a look at [Where to go from here](#where-to-go-from-here) for ideas on what to do
next.


## Create a New AMI with the Helper Scripts Installed

This example depends on the `map-ec2-tags-to-node-labels` script to assist with mapping [the EC2 instance
tags](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html) into Node
[Labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/). We will use `packer` to build a
customized AMI on based on [the EKS optimized
AMI](https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html) that includes the script.

To build the AMI, you need to provide `packer` the build template and required variables. Since we will be installing a
Gruntwork module, we will need to setup Github access. This can be done by defining the `GITHUB_OAUTH_TOKEN` environment
variable with a personal access token. See https://github.com/gruntwork-io/gruntwork-installer#authentication for more
information on how to set this up.

Once the environment variable is set, you can run `packer build` to build the AMI:

```bash
packer build packer/build.json
```

This will spin up an EC2 instance, run the shell scripts to provision the machine, burn a new AMI, spin down the
instance, and then output the newly built AMI.

Note: By default, the provided `packer` template will build a new AMI in the `us-east-1` region. If you would like to
change the region to build in, you can pass in `-var "region=us-east-2"` to override the default region.


## Apply Terraform Templates

Once the AMI is built, we are ready to use it to deploy our EKS cluster. Unlike the other examples in this repo, this
example breaks up the code into multiple submodules. Refer to [Why are there multiple Terraform submodules in this
example?](#why-are-there-multiple-terraform-submodules-in-this-example) for more information on why the example is
structured this way.

To deploy our cluster, we will apply the templates in the following order:

1. [eks-cluster: Deploy the EKS cluster with workers](#deploy-eks-cluster)
1. [core-services: Deploy Core Services (e.g Helm Server) on to EKS cluster](#deploy-core-services)
1. [(Optional) nginx-service: Deploy nginx on to EKS cluster](#optional-deploy-nginx-service)

### Deploy EKS cluster

The code for deploying an EKS cluster with its worker groups is defined in [the `eks-cluster` submodule](./eks-cluster).
This Terraform example, when applied, will deploy a VPC, launch an EKS control plane in there, and then provision two
worker groups to run workloads. The two groups provided by the example are:

1. A `core` worker group that is dedicated for running supporting services like `kiam` that may require more lockdown.
   The nodes in this group are tainted with `NoSchedule` so that `Pods` are not scheduled there by default.
1. An `application` worker group that is dedicated for running application services.

To deploy the example, we need to first define the required variables. To define variables to use, create a new file in
the example directory called terraform.tfvars:

```bash
touch ./eks-cluster/terraform.tfvars
```

Then, create a new entry for each required variable (and any optional variables you would like to override). See the
`variables.tf` file for a list of available variables. Below is a sample `terraform.tfvars` file:

```hcl
aws_region = "us-west-2"
eks_cluster_name = "test-eks-cluster-with-supporting-services"
vpc_name = "test-eks-cluster-with-supporting-services-vpc"
eks_worker_ami = "ami-00000000000000000"
```

**NOTE**: If you attempt to deploy into the `us-east-1` region, note that the availability zone `us-east-1e` does not
support EKS. To work around this, use the `allowed_availability_zones` to control which zones are used to deploy EKS by
adding the following to the tfvars file:
`allowed_availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]`.

Once the variables are filled out, we are ready to apply the templates to provision our cluster. To do this, we need to
run `terraform init` followed by `terraform apply`:

```bash
cd eks-cluster
terraform init
terraform apply
cd ..  # go back to eks-cluster-with-supporting-services example folder
```

At the end of this, you will have an EKS cluster with 2 ASG node worker pools. We will use `kubectl` to verify this.

In order to use `kubectl`, we need to first set it up so that it can authenticate with our new EKS cluster. You can
learn more about how authentication works with EKS in our guide [How do I authenticate kubectl to the EKS
cluster?](/core-concepts.md#how-do-i-authenticate-kubectl-to-the-eks-cluster). For now, you can run the `kubergrunt eks
configure` command:

```bash
EKS_CLUSTER_ARN=$(cd eks-cluster && terraform output eks_cluster_arn | tr -d \")
kubergrunt eks configure --eks-cluster-arn $EKS_CLUSTER_ARN
```

At the end of this command, your default kubeconfig file (located at `~/.kube/config`) will have a new context that
authenticates with EKS. This context will be set as the default so that subsequent `kubectl` calls will target your
deployed eks cluster.

You can now use `kubectl` to verify the two worker groups. Run `kubectl get nodes` and `kubectl describe nodes` to see
the associated labels of the nodes and verify there are two distinct labels.

This will output information about the deployed cluster. Record the entries for `vpc_id`,
`eks_openid_connect_provider_arn`, and `eks_openid_connect_provider_url`, as we will be using those in the next step.

### Deploy Core Services

Once our EKS cluster is deployed, we can deploy core services on to it. The code for core services is defined in [the
`core-services` submodule](./core-services). This Terraform example, when applied, deploys administrative services:

- fluentd-cloudwatch: Used to ship Kubernetes logs (including container logs) to CloudWatch.
- aws-alb-ingress-controller: Used to map `Ingress` resources into AWS ALBs.
- `external-dns`: Used for tieing Route 53 domains to exposed services.

Like the previous step, create a `terraform.tfvars` file and fill it in. Below is a sample entry:

```hcl
aws_region = "us-west-2"
eks_cluster_name = "test-eks-cluster-with-supporting-services"
iam_role_for_service_accounts_config = {
    openid_connect_provider_arn = "arn"
    openid_connect_provider_url = "url"
}
eks_vpc_id = "VPC ID"
```

The `eks_vpc_id`, `openid_connect_provider_arn`, and `openid_connect_provider_url` input variables should be
the outputs that you recorded in the previous step.

Once the tfvars file is created, you can init and apply the templates:

```bash
touch ./core-services/terraform.tfvars
# Fill in the tfvars file with the variable inputs
cd core-services
terraform init
terraform apply
cd ..  # go back to eks-cluster-with-supporting-services example folder
```

Additionally, the cluster should be shipping logs to CloudWatch. You can load the CloudWatch logs in the UI by
navigating to CloudWatch in the AWS console and looking for the log group with the same name as the EKS cluster.

### (Optional) Deploy Nginx Service

The [`nginx-service` submodule](./nginx-service) shows an example of how to use Helm to deploy an application on to your
EKS cluster. This example will:

- Setup [the Gruntwork Helm Chart Repository](https://github.com/gruntwork-io/helmcharts)
- Install Nginx using the [`k8s-service` helm chart](https://github.com/gruntwork-io/helm-kubernetes-services/tree/master/charts/k8s-service)
- As part of the install, an ALB will be provisioned that routes to the nginx Pods.

Like the previous step, create a `terraform.tfvars` file and fill it in. Below is a sample entry:

```hcl
aws_region = "us-west-2"
eks_cluster_name = "test-eks-cluster-with-supporting-services"
```

Once the tfvars file is created, you can init and apply the templates:

```bash
touch ./nginx-service/terraform.tfvars
# Fill in the tfvars file with the variable inputs
cd nginx-service
terraform init
terraform apply
cd ..  # go back to eks-cluster-with-supporting-services example folder
```

Once Terraform finishes, the nginx service should be available. To get the endpoint, you can query Kubernetes using
`kubectl` for the Service information:

```bash
# Prerequisite: Setup environment variables to auth to AWS
# Use kubectl to get Service endpoint
kubectl \
  get ingresses \
  --namespace kube-system \
  --selector app.kubernetes.io/instance=nginx,app.kubernetes.io/name=nginx \
  -o jsonpath \
  --template '{.items[0].status.loadBalancer.ingress[0].hostname}'
```

This will output the ALB endpoint to the console. When you hit the endpoint, you should be able to see the welcome page
for nginx. If the service isn't available or you don't get the endpoint, wait a few minutes to give Kubernetes a chance
provision the ALB.


## Where to go from here

Now that you have your cluster, you can do a few things to explore the cluster:

- If you setup an SSH key with the `eks_worker_keypair_name` variable, try SSH-ing to the nodes to see the running
  processes.


## Why are there multiple Terraform submodules in this example?

Breaking up your code not only improves readability, but it also helps with maintainability by keeping the surface area
small. Typically you would want to structure your code so that resources that are deployed more frequently are isolated
from critical resources that might bring down the cluster. For example, you might upgrade the supporting services
regularly, but you might not touch your VPC once it is set up. Therefore, you do not want to manage your Helm resources
with the VPC, as everytime you update the services, you would be putting the cluster at risk.

Additionally, breaking up the code into modules helps introduce dependency ordering. Terraform is notorious for having
bugs and subtle issues that make it difficult to reliably introduce a dependency chain, especially when you have
modules. For example, you can't easily define dependencies such that the resources in a module depend on other resources
or modules external to the module (see https://github.com/hashicorp/terraform/issues/1178).

The dependency logic between launching the EKS cluster, setting up Helm, and deploying services using Helm is tricky to
encode in terraform such that it works reliably. For example, while it is fairly easy to get the resources to deploy in
order such that they are available, it is tricky to destroy the resources in the right order. For example, it is ok to
deploy services in parallel with the worker nodes, such that the worker nodes are coming up while the deployment script
is executing. The same thing can't be done for destruction, because the script needs to undeploy the services before
undeploying the worker nodes.

In summary, this example breaks up the Terraform code as an example of how one might modularize their EKS cluster code,
in addition to making the dependency management more explicit.


## Troubleshooting

**When destroying `eks-cluster`, I get an error with destroying VPC related resources.**

- EKS relies on the [`amazon-vpc-cni-k8s`](https://github.com/aws/amazon-vpc-cni-k8s) plugin to allocate IP addresses to
  the pods in the Kubernetes cluster. This plugin works by allocating secondary ENI devices to the underlying worker
  instances. Depending on timing, this plugin could interfere with destroying the cluster in this example. Specifically,
  terraform could shutdown the instances before the VPC CNI pod had a chance to cull the ENI devices. These devices are
  managed outside of terraform, so if they linger, it could interfere with destroying the VPC.
    - To workaround this limitation, you have to go into the console and delete the ENI associated with the VPC. Then,
      retry the destroy call.
