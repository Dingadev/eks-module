# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A EKS CLUSTER WITH FARGATE AND IAM ROLE FOR SERVICE ACCOUNTS (IRSA) IN default NAMESPACE
# These templates show an example of how to provision an EKS cluster with Fargate, and how to configure an IAM Role for
# use with Service Accounts in Kubernetes.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.49"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
      # NOTE: 2.6.0 has a regression bug that prevents usage of the exec block with data source references, so we lock
      # to a version less than that. See https://github.com/hashicorp/terraform-provider-kubernetes/issues/1464 for more
      # details.
      version = "~> 2.0, < 2.6.0"
    }
  }
}

# ------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# ------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CONFIGURE OUR KUBERNETES CONNECTIONS
# Note that we can't configure our Kubernetes connection until EKS is up and running, so we try to depend on the
# resource being created.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# The provider needs to depend on the cluster being setup. Here we dynamically pull in the information necessary as data
# sources.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)

  # EKS clusters use short-lived authentication tokens that can expire in the middle of an 'apply' or 'destroy'. To
  # avoid this issue, we use an exec-based plugin here to fetch an up-to-date token. Note that this code requires a
  # binary—either kubergrunt or aws—to be installed and on your PATH.
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    command     = var.use_kubergrunt_to_fetch_token ? "kubergrunt" : "aws"
    args = (
      var.use_kubergrunt_to_fetch_token
      ? ["eks", "token", "--cluster-id", module.eks_cluster.eks_cluster_name]
      : ["eks", "get-token", "--cluster-name", module.eks_cluster.eks_cluster_name]
    )
  }
}

# Workaround for Terraform limitation where you cannot directly set a depends on directive or interpolate from resources
# in the provider config.
# Specifically, Terraform requires all information for the Terraform provider config to be available at plan time,
# meaning there can be no computed resources. We work around this limitation by rereading the EKS cluster info using a
# data source.
# See https://github.com/hashicorp/terraform/issues/2430 for more details
data "aws_eks_cluster" "cluster" {
  name = module.eks_cluster.eks_cluster_name
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A VPC WITH NAT GATEWAY
# We will provision a new VPC because EKS requires a VPC that is tagged to denote that it is shared with Kubernetes.
# Specifically, both the VPC and the subnets that EKS resides in need to be tagged with:
# kubernetes.io/cluster/EKS_CLUSTER_NAME=shared
# This information is used by EKS to allocate ip addresses to the Kubernetes pods.
# ---------------------------------------------------------------------------------------------------------------------

module "vpc_app" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-vpc.git//modules/vpc-app?ref=v0.17.1"

  vpc_name   = var.vpc_name
  aws_region = var.aws_region

  # These tags (kubernetes.io/cluster/EKS_CLUSTERNAME=shared) are used by EKS to determine which AWS resources are
  # associated with the cluster. This information will ultimately be used by the [amazon-vpc-cni-k8s
  # plugin](https://github.com/aws/amazon-vpc-cni-k8s) to allocate ip addresses from the VPC to the Kubernetes pods.
  custom_tags = module.vpc_tags.vpc_eks_tags

  public_subnet_custom_tags              = module.vpc_tags.vpc_public_subnet_eks_tags
  private_app_subnet_custom_tags         = module.vpc_tags.vpc_private_app_subnet_eks_tags
  private_persistence_subnet_custom_tags = module.vpc_tags.vpc_private_persistence_subnet_eks_tags

  # The IP address range of the VPC in CIDR notation. A prefix of /18 is recommended. Do not use a prefix higher
  # than /27.
  cidr_block = "10.0.0.0/18"

  # The number of NAT Gateways to launch for this VPC. For production VPCs, a NAT Gateway should be placed in each
  # Availability Zone (so likely 3 total), whereas for non-prod VPCs, just one Availability Zone (and hence 1 NAT
  # Gateway) will suffice. Warning: You must have at least this number of Elastic IP's to spare.  The default AWS
  # limit is 5 per region, but you can request more.
  num_nat_gateways = 1
}

module "vpc_tags" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-vpc-tags?ref=v0.9.6"
  source = "../../modules/eks-vpc-tags"

  eks_cluster_names = [var.eks_cluster_name]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE EKS CLUSTER IN TO THE VPC
# ---------------------------------------------------------------------------------------------------------------------

module "eks_cluster" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-control-plane?ref=v0.9.6"
  source = "../../modules/eks-cluster-control-plane"

  cluster_name = var.eks_cluster_name

  vpc_id                       = module.vpc_app.vpc_id
  vpc_control_plane_subnet_ids = local.usable_subnet_ids
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  kubernetes_version  = var.kubernetes_version
  configure_kubectl   = var.configure_kubectl
  kubectl_config_path = var.kubectl_config_path

  # Disable waiting for rollout, since the dependency ordering of worker pools causes terraform to deploy the script
  # before the workers. As such, rollout will always fail. Note that this should be set to true after the first deploy
  # to ensure that terraform waits until rollout of the upgraded components completes before completing the apply.
  upgrade_cluster_script_wait_for_rollout = false

  # Make sure the control plane services can operate without worker nodes
  schedule_control_plane_services_on_fargate = true
  vpc_worker_subnet_ids                      = local.usable_subnet_ids
}

# Create Fargate Profile so that Pods in the default Namespace use Fargate for worker nodes
resource "aws_eks_fargate_profile" "default" {
  cluster_name           = module.eks_cluster.eks_cluster_name
  fargate_profile_name   = "default-namespace"
  pod_execution_role_arn = module.eks_cluster.eks_default_fargate_execution_role_arn
  subnet_ids             = local.usable_subnet_ids

  selector {
    namespace = "default"
  }

  # Fargate Profiles can take a long time to delete if there are Pods, since the nodes need to deprovision.
  timeouts {
    delete = "1h"
  }
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE EXAMPLE IAM ROLE WITH ABILITY TO READ EKS CLUSTERS FOR SERVICE ACCOUNTS IN default NAMESPACE
# This IAM Role will automatically be available for attachment to all Pods in the default Namespace. To attach the IAM
# role, you need to add the following annotation to the Service Account:
#
#   eks.amazonaws.com/role-arn: IAM_ROLE_ARN
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

module "assume_role_policy" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-iam-role-assume-role-policy-for-service-account?ref=v0.9.6"
  source = "../../modules/eks-iam-role-assume-role-policy-for-service-account"

  eks_openid_connect_provider_arn = module.eks_cluster.eks_iam_openid_connect_provider_arn
  eks_openid_connect_provider_url = module.eks_cluster.eks_iam_openid_connect_provider_url
  namespaces                      = var.allowed_namespaces_for_iam_role
  service_accounts                = var.allowed_service_accounts_for_iam_role
}

resource "aws_iam_role" "example" {
  name               = "${var.example_iam_role_name_prefix}${var.unique_identifier}"
  assume_role_policy = module.assume_role_policy.assume_role_policy_json
}

resource "aws_iam_role_policy" "example" {
  name   = "${var.example_iam_role_name_prefix}${var.unique_identifier}-policy"
  role   = aws_iam_role.example.id
  policy = data.aws_iam_policy_document.example.json
}

data "aws_iam_policy_document" "example" {
  statement {
    actions   = ["eks:ListClusters"]
    resources = ["*"]
  }
}
