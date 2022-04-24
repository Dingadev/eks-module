# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A EKS CLUSTER WITH EC2 INSTANCES AS WORKERS AND CONFIGURE IAM BINDINGS
# These templates show an example of how to:
# - Deploy an EKS cluster
# - Deploy a self managed Autoscaling Group (ASG) with EC2 instances acting as workers
# - Bind IAM Roles to Kubernetes RBAC Groups for cluster access, using test IAM roles as an example
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

  # We add a NAT gateway so that Fargate pods can make outbound network calls.
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

  cluster_name                 = var.eks_cluster_name
  enabled_cluster_log_types    = ["api"]
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  vpc_id                       = module.vpc_app.vpc_id
  vpc_control_plane_subnet_ids = local.usable_private_subnet_ids

  kubernetes_version                      = var.kubernetes_version
  configure_kubectl                       = var.configure_kubectl
  kubectl_config_path                     = var.kubectl_config_path
  upgrade_cluster_script_wait_for_rollout = var.wait_for_component_upgrade_rollout

  # Fargate settings
  schedule_control_plane_services_on_fargate = var.schedule_control_plane_services_on_fargate
  vpc_worker_subnet_ids                      = local.usable_private_subnet_ids

  # We make sure the Fargate Profile for control plane services depend on the aws-auth ConfigMap with user IAM role
  # mappings so that we don't accidentally revoke access to the Kubernetes cluster before we make all the necessary
  # operations against the Kubernetes API to reschedule the control plane pods.
  fargate_profile_dependencies = [module.users_eks_k8s_role_mapping.aws_auth_config_map_name]
}

module "eks_workers" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-workers?ref=v0.9.6"
  source = "../../modules/eks-cluster-workers"

  cluster_name               = module.eks_cluster.eks_cluster_name
  use_cluster_security_group = true

  autoscaling_group_configurations = merge(
    (
      var.deploy_spot_workers
      ? {
        asg = {
          # Make the max size twice the min size to allow for rolling out updates to the cluster without downtime
          min_size                      = 2
          max_size                      = 4
          asg_instance_type             = module.instance_types.recommended_instance_type
          tags                          = []
          asg_instance_root_volume_size = 500

          # Here we use public subnets to make it easier to test SSH access, but in production you should use private
          # subnets
          subnet_ids                 = local.usable_public_subnet_ids
          use_multi_instances_policy = true
          spot_allocation_strategy   = "capacity-optimized"
          multi_instance_overrides = [
            {
              instance_type     = "t3.medium"
              weighted_capacity = 1
            },
            {
              instance_type     = module.instance_types.recommended_instance_type
              weighted_capacity = 1
            },
          ]
        }
      }
      : {}
    ),
    {
      for key, config in var.additional_autoscaling_group_configurations :
      key => merge(
        { subnet_ids = local.usable_public_subnet_ids },
        config,
      )
    },
  )

  asg_default_instance_ami                     = data.aws_ami.eks_worker.id
  cluster_instance_keypair_name                = var.eks_worker_keypair_name
  asg_default_instance_user_data_base64        = data.cloudinit_config.cloud_init.rendered
  cluster_instance_associate_public_ip_address = true
}

# Pick instance type that is most available in the region.
module "instance_types" {
  source = "git::git@github.com:gruntwork-io/terraform-aws-utilities.git//modules/instance-type?ref=v0.6.0"

  instance_types = ["t2.micro", "t3.micro"]
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

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CONFIGURE EKS IAM ROLE MAPPINGS
# This shows an example of how to use the two modules (eks-aws-auth-merger and eks-k8s-role-mapping) we offer to map AWS
# IAM roles to RBAC groups in Kubernetes. The official way to do this in EKS is to add values to a single, central
# ConfigMap. This centralized ConfigMap can be updated not only from the Terraform code here, but also other places
# (e.g., EKS sometimes add its own entries), so to ensure none of those updates are lost, we create separate ConfigMaps
# in the Terraform code, and allow `aws-auth-merger`, which runs as a Pod in the background, to merge all the values
# together into the final, central ConfigMap.
# For this example, we will deploy the aws-auth-merger utility into EKS Fargate.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

module "eks_aws_auth_merger" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-aws-auth-merger?ref=v0.9.6"
  source = "../../modules/eks-aws-auth-merger"

  create_namespace = true
  namespace = (
    # We use the following tautology to ensure the Namespace resource depends on the EKS cluster being created.
    module.eks_cluster.eks_cluster_name == null
    ? var.aws_auth_merger_namespace
    : var.aws_auth_merger_namespace
  )
  aws_auth_merger_image = var.aws_auth_merger_image

  # Since we will manage the IAM role mapping for the workers using the merger, we need to schedule the deployment onto
  # Fargate. Otherwise, there is a chicken and egg problem where the workers won't be able to auth until the
  # aws-auth-merger is deployed, but the aws-auth-merger can't be deployed until the workers are setup. Fargate IAM
  # auth is automatically configured by AWS when we create the Fargate Profile, so we can break the cycle if we use
  # Fargate.
  create_fargate_profile = true
  fargate_profile = {
    name                   = var.aws_auth_merger_namespace
    eks_cluster_name       = module.eks_cluster.eks_cluster_name
    worker_subnet_ids      = local.usable_private_subnet_ids
    pod_execution_role_arn = module.eks_cluster.eks_default_fargate_execution_role_arn
  }
}


# To demonstrate the aws-auth-merger functionality, we split our aws-auth configuration into two ConfigMaps: one for
# nodes and one for user IAM roles.
module "nodes_eks_k8s_role_mapping" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-k8s-role-mapping?ref=v0.9.6"
  source = "../../modules/eks-k8s-role-mapping"

  name      = "aws-auth-nodes"
  namespace = module.eks_aws_auth_merger.namespace

  eks_worker_iam_role_arns        = [module.eks_workers.eks_worker_iam_role_arn]
  iam_role_to_rbac_group_mappings = {}

  # AWS will automatically create an aws-auth ConfigMap that allows the Fargate nodes, so we won't configure it here.
  # The aws-auth-merger will automatically include that configuration if it sees the ConfigMap as it is booting up.
  # This works because we are creating a Fargate Profile BEFORE the aws-auth-merger is deployed
  # (`create_fargate_profile = true` in the `eks-aws-auth-merger` module call), which will cause EKS to create the
  # aws-auth ConfigMap to allow the Fargate workers to access the control plane. So the flow is:
  # 1. AWS creates central ConfigMap with the Fargate execution role.
  # 2. aws-auth-merger is deployed and starts up.
  # 3. aws-auth-merger sees the automatically created ConfigMap, detects that it is not managed by itself, and snapshots
  #    the ConfigMap to preserve the Fargate role mappings during future merges.
  # 4. aws-auth-merger looks up the other ConfigMaps in the namespace and merges them together to replace the existing
  #    central ConfigMap.
  eks_fargate_profile_executor_iam_role_arns = []

  config_map_labels = {
    eks-cluster = module.eks_cluster.eks_cluster_name
  }
}

module "users_eks_k8s_role_mapping" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-k8s-role-mapping?ref=v0.9.6"
  source = "../../modules/eks-k8s-role-mapping"

  name      = "aws-auth-users"
  namespace = module.eks_aws_auth_merger.namespace

  eks_worker_iam_role_arns                   = []
  eks_fargate_profile_executor_iam_role_arns = []

  iam_role_to_rbac_group_mappings = {
    (aws_iam_role.example.arn) = [var.example_iam_role_kubernetes_group_name]
    (local.caller_real_arn)    = ["system:masters"]
  }

  config_map_labels = {
    eks-cluster = module.eks_cluster.eks_cluster_name
  }
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE EXAMPLE IAM ROLES AND USERS
# We create example IAM roles that can be used to test and experiment with mapping different IAM roles/users to groups
# in Kubernetes with different permissions.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

resource "aws_iam_role" "example" {
  name               = "${var.example_iam_role_name_prefix}${var.unique_identifier}"
  assume_role_policy = data.aws_iam_policy_document.allow_access_from_self.json
}

resource "aws_iam_role_policy" "example" {
  name   = "${var.example_iam_role_name_prefix}${var.unique_identifier}-policy"
  role   = aws_iam_role.example.id
  policy = data.aws_iam_policy_document.example.json
}

# Minimal permission to be able to authenticate to the cluster
data "aws_iam_policy_document" "example" {
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks_cluster.eks_cluster_arn]
  }
}
