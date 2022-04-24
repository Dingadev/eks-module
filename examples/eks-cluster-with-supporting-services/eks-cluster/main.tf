# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A EKS CLUSTER WITH EC2 INSTANCES AS WORKERS
# These templates show an example of how to provision an EKS cluster with EC2 instances acting as workers with an
# Autoscaling Group (ASG) to scale the cluster up and down.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      # NOTE: 2.6.0 has a regression bug that prevents usage of the exec block with data source references, so we lock
      # to a version less than that. See https://github.com/hashicorp/terraform-provider-kubernetes/issues/1464 for more
      # details.
      version = "~> 2.0, < 2.6.0"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE OUR KUBERNETES CONNECTIONS
# Note that we can't configure our Kubernetes connection until EKS is up and running, so we try to depend on the
# resource being created.
# ---------------------------------------------------------------------------------------------------------------------

# The provider needs to depend on the cluster being setup.
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
# CREATE A VPC
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

  # To make it easier to test, we will deploy all EKS resources in the public subnet with public IPs, which means we
  # don't need a NAT to communicate. THIS IS NOT RECOMMENDED IN PRODUCTION! In production, you should use private
  # subnets for all EKS resources, and you will need a NAT to make outbound connections.
  num_nat_gateways = 0
}

module "vpc_tags" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-vpc-tags?ref=v0.9.6"
  source = "../../../modules/eks-vpc-tags"

  eks_cluster_names = [var.eks_cluster_name]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE EKS CLUSTER IN TO THE VPC
# ---------------------------------------------------------------------------------------------------------------------

module "eks_cluster" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-control-plane?ref=v0.9.6"
  source = "../../../modules/eks-cluster-control-plane"

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
}

# ---------------------------------------------------------------------------------------------------------------------
# SETUP EKS WORKER POOLS
# For this example, we will setup two node pools:
# - eks_workers node pool for running application pods
# - eks_core_workers node pool for running supporting services
# In this model, the idea is to lock down the core worker nodes so that only trusted entities can access it (e.g SSH),
# given that it will be running sensitive Pods:
# - Main Tiller Server with access to kube-system
# - kiam server with role assuming capabilities
# ---------------------------------------------------------------------------------------------------------------------

module "eks_workers" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-workers?ref=v0.9.6"
  source = "../../../modules/eks-cluster-workers"

  name_prefix                = "app-"
  cluster_name               = module.eks_cluster.eks_cluster_name
  use_cluster_security_group = true

  autoscaling_group_configurations = {
    asg = {
      # Make the max size twice the min size to allow for rolling out updates to the cluster without downtime
      min_size = 2
      max_size = 4
      # We use a t3.medium so that we have enough container slots to run the supporting services
      asg_instance_type = "t3.medium"
      subnet_ids        = local.usable_subnet_ids
      tags = [
        {
          key                 = "type"
          value               = "application"
          propagate_at_launch = true
        }
      ]
    }
  }

  include_autoscaler_discovery_tags = true

  asg_default_instance_ami                     = var.eks_worker_ami
  asg_default_instance_user_data_base64        = base64encode(local.app_workers_user_data)
  cluster_instance_keypair_name                = var.eks_worker_keypair_name
  cluster_instance_associate_public_ip_address = true
}

module "eks_core_workers" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-workers?ref=v0.9.6"
  source = "../../../modules/eks-cluster-workers"

  name_prefix  = "core-"
  cluster_name = module.eks_cluster.eks_cluster_name

  # We avoid the cluster security group for the core workers to have better network isolation and control.
  use_cluster_security_group = false

  autoscaling_group_configurations = {
    asg = {
      # Make the max size twice the min size to allow for rolling out updates to the cluster without downtime
      min_size = 1
      max_size = 2
      # We use a t3.medium so that we have enough container slots to run the supporting services
      asg_instance_type = "t3.medium"
      subnet_ids        = local.usable_subnet_ids
      tags = [
        {
          key                 = "type"
          value               = "core"
          propagate_at_launch = true
        },
      ]
    }
  }

  asg_default_instance_ami                     = var.eks_worker_ami
  cluster_instance_keypair_name                = var.eks_worker_keypair_name
  asg_default_instance_user_data_base64        = base64encode(local.core_workers_user_data)
  cluster_instance_associate_public_ip_address = true
}

# The two worker pools need to be able to communicate with each other on the DNS port in case the coredns Pod lands on
# either pool.
module "allow_dns_access_between_worker_pools" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-workers-cross-access?ref=v0.9.6"
  source = "../../../modules/eks-cluster-workers-cross-access"

  num_eks_worker_security_group_ids = 2

  eks_worker_security_group_ids = [
    module.eks_core_workers.eks_worker_security_group_id,
    module.eks_workers.eks_worker_security_group_id,
  ]

  ports = [
    {
      protocol  = "udp"
      from_port = 53
      to_port   = 53
    },
    {
      protocol  = "tcp"
      from_port = 53
      to_port   = 53
    },
  ]
}

# Allowing SSH from anywhere to the worker nodes for test purposes only.
# THIS SHOULD NOT BE DONE IN PROD
resource "aws_security_group_rule" "allow_inbound_ssh_from_anywhere" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks_workers.eks_worker_security_group_id
}

resource "aws_security_group_rule" "allow_inbound_ssh_from_anywhere_for_core" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks_core_workers.eks_worker_security_group_id
}

# Allowing access to node ports on the worker nodes for test purposes only.
# THIS SHOULD NOT BE DONE IN PROD. INSTEAD USE LOAD BALANCERS.
resource "aws_security_group_rule" "allow_inbound_node_port_from_anywhere" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks_workers.eks_worker_security_group_id
}

# We allow inbound access for core workers too to test the services deployed there.
resource "aws_security_group_rule" "allow_inbound_node_port_from_anywhere_for_core" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks_core_workers.eks_worker_security_group_id
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE EKS IAM ROLE MAPPINGS
# We will map AWS IAM roles to RBAC roles in Kubernetes. By doing so, we:
# - allow access to the EKS cluster when assuming mapped IAM role
# - manage authorization for those roles using RBAC role resources in Kubernetes
# At a minimum, we need to provide cluster node level permissions to the IAM role assumed by EKS workers.
# ---------------------------------------------------------------------------------------------------------------------

module "eks_k8s_role_mapping" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-k8s-role-mapping?ref=v0.9.6"
  source = "../../../modules/eks-k8s-role-mapping"

  eks_worker_iam_role_arns = [
    module.eks_workers.eks_worker_iam_role_arn,
    module.eks_core_workers.eks_worker_iam_role_arn,
  ]

  iam_role_to_rbac_group_mappings = {
    (local.caller_real_arn) = ["system:masters"]
  }

  config_map_labels = {
    "eks-cluster" = module.eks_cluster.eks_cluster_name
  }
}
