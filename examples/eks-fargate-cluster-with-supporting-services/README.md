# EKS Fargate Cluster with Supporting Services

This example provisions an EKS cluster that:

- Uses Fargate to provision workloads
- Deploys system administration applications:
    - ALB Ingress Controller for exposing services publicly using AWS ALBs
    - external-dns for tying Route 53 domains to exposed services.


## Prerequisites

This example depends on `Terraform`, `kubectl`, and `kubergrunt`. You can find instructions on how to install
each tool below:

- [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html), minimum version: `1.0.0`
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [kubergrunt](https://github.com/gruntwork-io/kubergrunt#installation), minimum version: `0.6.2`

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

1. [eks-cluster: Deploy EKS Cluster](#deploy-eks-cluster)
1. [core-services: Deploy Core Administrative Services](#deploy-core-administrative-services)
1. [nginx-services: (Optional) Deploy Nginx Service](#optional-deploy-nginx-service)

Once the cluster is deployed, take a look at [Where to go from here](#where-to-go-from-here) for ideas on what to do
next.


## Deploy EKS cluster

The code for deploying an EKS cluster with Fargate support is defined in [the `eks-cluster` submodule](./eks-cluster).
This Terraform example, when applied, will deploy a VPC, launch an EKS control plane in there, and then update
administrative EKS services to run on Fargate.

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
```

**NOTE**: If you attempt to deploy into the `us-east-1` region, note that as of January, 2020, the availability zone `us-east-1e` does not
support EKS. To work around this, use the `allowed_availability_zones` to control which zones are used to deploy EKS by
adding the following to the tfvars file:
`allowed_availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]`.

Once the variables are filled out, we are ready to apply the templates to provision our cluster. To do this, we need to
run `terraform init` followed by `terraform apply`:

```bash
cd eks-cluster
terraform init
terraform apply
cd ..  # go back to eks-fargate-cluster example folder
```

At the end of `apply`, terraform will output information about the deployed cluster. Record the entries for `vpc_id`,
`eks_openid_connect_provider_arn`, and `eks_openid_connect_provider_url`, as we will be using those in the next step.

At the end of this, you will have an EKS cluster with its administrative workloads (namely, the [CoreDNS
service](https://kubernetes.io/docs/tasks/administer-cluster/coredns/)) running on Fargate. We will use `kubectl` to
verify this.

In order to use `kubectl`, we need to first set it up so that it can authenticate with our new EKS cluster. You can
learn more about how authentication works with EKS in our guide [How do I authenticate kubectl to the EKS
cluster?](/core-concepts.md#how-do-i-authenticate-kubectl-to-the-eks-cluster). For now, you can run the `kubergrunt eks configure` command:

```bash
EKS_CLUSTER_ARN=$(cd eks-cluster && terraform output eks_cluster_arn | tr -d \")
kubergrunt eks configure --eks-cluster-arn $EKS_CLUSTER_ARN
```

At the end of this command, your default kubeconfig file (located at `~/.kube/config`) will have a new context that
authenticates with EKS. This context will be set as the default so that subsequent `kubectl` calls will target your
deployed eks cluster.

You can now use `kubectl` to verify that the `coredns` pods are running on Fargate. If you run `kubectl get nodes` and
`kubectl describe nodes`, you should see two nodes with hostnames and labels that indicate they are Fargate nodes.

NOTE: when using Fargate, you will see a node for each Pod deployed.


## Deploy Core Administrative Services

Once our EKS cluster is deployed, we can deploy core services on to it. The code for core services is defined in [the
`core-services` submodule](./core-services). This Terraform example, when applied, will use Helm to deploy supporting
services:

- aws-alb-ingress-controller: Used to map `Ingress` resources into AWS ALBs.
- external-dns: Used to map hostnames in `Ingress` resources to Route 53 Hosted Zone Record Sets.

Like the previous step, create a `terraform.tfvars` file and fill it in. Below is a sample entry:

```hcl
aws_region = "us-west-2"
eks_cluster_name = "test-eks-fargate-cluster"
eks_vpc_id = "VPC ID"
eks_openid_connect_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
eks_openid_connect_provider_url = "oidc.eks.ap-northeast-1.amazonaws.com/id/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
```

The `eks_vpc_id`, `eks_openid_connect_provider_arn`, and `eks_openid_connect_provider_url` inputs are from the outputs
that you recorded in the previous step.

Once the tfvars file is created, you can init and apply the templates:

```bash
touch ./core-services/terraform.tfvars
# Fill in the tfvars file with the variable inputs
cd core-services
terraform init
terraform apply
cd ..  # go back to eks-fargate-cluster example folder
```

## (Optional) Deploy Nginx Service

The [`nginx-service` submodule](./nginx-service) shows an example of how to use Helm to deploy an application on to your
EKS cluster. This example will:

- Setup [the Gruntwork Helm Chart Repository](https://github.com/gruntwork-io/helmcharts)
- Install Nginx using the [`k8s-service` helm chart](https://github.com/gruntwork-io/helm-kubernetes-services/tree/master/charts/k8s-service)
- As part of the install, an ALB will be provisioned that routes to the nginx Pods.

Like the previous step, create a `terraform.tfvars` file and fill it in. Below is a sample entry:

```hcl
aws_region = "us-west-2"
eks_cluster_name = "test-eks-cluster-with-supporting-services"
eks_openid_connect_provider_arn = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
eks_openid_connect_provider_url = "oidc.eks.ap-northeast-1.amazonaws.com/id/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
route53_hosted_zone_name = "yourco.com"
```

The `eks_openid_connect_provider_arn` and `eks_openid_connect_provider_url` inputs are from the outputs
that you recorded in the previous step.

The `route53_hosted_zone_name` input should be a route 53 public domain that you own. The domain
`nginx.${var.route53_hosted_zone_name}` will be configured to route to the ALB.

Once the tfvars file is created, you can init and apply the templates:

```bash
touch ./nginx-service/terraform.tfvars
# Fill in the tfvars file with the variable inputs
cd nginx-service
terraform init
terraform apply
cd ..  # go back to eks-fargate-cluster example folder
```

Once Terraform finishes, the nginx service should be available. To get the endpoint, you can query Kubernetes using
`kubectl` for the Service information:

```bash
# Prerequisite: Setup environment variables to auth to AWS
# Use kubectl to get Service endpoint
kubectl \
  get ingresses \
  --namespace kube-system \
  --selector app.kubernetes.io/instance=nginx-test,app.kubernetes.io/name=nginx \
  -o jsonpath \
  --template '{.items[0].status.loadBalancer.ingress[0].hostname}'
```

This will output the ALB endpoint to the console. When you hit the endpoint, you should be able to see the welcome page
for nginx. If the service isn't available or you don't get the endpoint, wait a few minutes to give Kubernetes a chance
provision the ALB.


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
