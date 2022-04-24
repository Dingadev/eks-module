# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A EKS CLUSTER WITH MANAGED EC2 INSTANCES AS WORKERS
# These templates show an example of how to provision an EKS cluster with Managed Node Groups. Managed Node Groups are
# special Autoscaling Groups (ASGs) managed by EKS to be optimized for use as EKS workers. You can scale the cluster up
# and down by configuring the parameters on the Managed Node groups.
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

  kubernetes_version  = var.kubernetes_version
  configure_kubectl   = var.configure_kubectl
  kubectl_config_path = var.kubectl_config_path

  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  enabled_cluster_log_types    = ["api"]

  vpc_cni_enable_prefix_delegation = var.vpc_cni_enable_prefix_delegation
  vpc_cni_warm_ip_target           = var.vpc_cni_warm_ip_target
  vpc_cni_minimum_ip_target        = var.vpc_cni_minimum_ip_target

  # We can't use kubergrunt based verification or the plugin upgrade script if there is no public endpoint access in
  # this example
  use_kubergrunt_verification = var.endpoint_public_access
  use_upgrade_cluster_script  = var.endpoint_public_access

  # Configure EKS add-ons
  # Even if there is no public endpoint access, core services can be updated with AWS managed add-ons
  enable_eks_addons = var.enable_eks_addons
  eks_addons        = var.eks_addons

  # Disable waiting for rollout, since the dependency ordering of worker pools causes terraform to deploy the script
  # before the workers. As such, rollout will always fail. Note that this should be set to true after the first deploy
  # to ensure that terraform waits until rollout of the upgraded components completes before completing the apply.
  upgrade_cluster_script_wait_for_rollout = false
}

module "eks_workers" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cluster-managed-workers?ref=v0.9.6"
  source = "../../modules/eks-cluster-managed-workers"

  cluster_name = module.eks_cluster.eks_cluster_name

  # To support cluster autoscaler, we need to create a node group per availability zone.
  node_group_configurations = {
    group1 = {
      desired_size = 2
      min_size     = 2
      max_size     = 4
      instance_types = (
        var.use_launch_template
        ? null
        : ["t3.micro"]
      )
      subnet_ids = [local.usable_subnet_ids[0]]
      launch_template = (
        var.use_launch_template
        ? {
          id      = aws_launch_template.template[0].id
          version = aws_launch_template.template[0].latest_version
        }
        : null
      )
    }
    group2 = {
      desired_size = 2
      min_size     = 2
      max_size     = 4
      instance_types = (
        var.use_launch_template
        ? null
        : ["t3.micro"]
      )
      subnet_ids = [local.usable_subnet_ids[1]]
      launch_template = (
        var.use_launch_template
        ? {
          id      = aws_launch_template.template[0].id
          version = aws_launch_template.template[0].latest_version
        }
        : null
      )
    }
  }

  cluster_instance_keypair_name = var.cluster_instance_keypair_name

  # To make this example easy to test, we allow SSH access from any IP. In real-world usage, you should only allow SSH
  # access from known, trusted servers (e.g., a bastion host).
  allow_ssh_from_security_groups = null
}

resource "aws_launch_template" "template" {
  count         = var.use_launch_template ? 1 : 0
  name_prefix   = var.eks_cluster_name
  image_id      = var.launch_template_ami_id
  instance_type = "t3.micro"
  user_data = base64encode(templatefile(
    "${path.module}/user-data/user_data.sh",
    {
      eks_cluster_name          = var.eks_cluster_name
      eks_endpoint              = module.eks_cluster.eks_cluster_endpoint
      eks_certificate_authority = module.eks_cluster.eks_cluster_certificate_authority
    },
  ))

  network_interfaces {
    # To simplify testing, we associate a public IP for the workers, but you will want to set this to false for
    # production usage.
    associate_public_ip_address = true
  }
}


# ---------------------------------------------------------------------------------------------------------------------
# SETUP K8S CLUSTER AUTOSCALER IAM PERMISSIONS
# ---------------------------------------------------------------------------------------------------------------------

data "aws_autoscaling_groups" "autoscaling_workers" {
  // This tag is automatically applied to all ASGs created by Managed Node Groups
  filter {
    name   = "key"
    values = ["k8s.io/cluster-autoscaler/${module.eks_cluster.eks_cluster_name}"]
  }

  depends_on = [module.eks_workers]
}

module "k8s_cluster_autoscaler_iam_policy" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-k8s-cluster-autoscaler-iam-policy?ref=v0.12.0"
  source = "../../modules/eks-k8s-cluster-autoscaler-iam-policy"

  name_prefix         = module.eks_cluster.eks_cluster_name
  eks_worker_asg_arns = data.aws_autoscaling_groups.autoscaling_workers.arns
}

resource "aws_iam_role_policy_attachment" "worker_k8s_cluster_autoscaler_policy_attachment" {
  role       = module.eks_workers.eks_worker_iam_role_name
  policy_arn = module.k8s_cluster_autoscaler_iam_policy.k8s_cluster_autoscaler_policy_arn
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE BASTION HOST TO ACCESS WORKER NODES
# Managed workers must be deployed in the private network, so we create a bastion host to allow SSH access into the
# workers.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.nano"
  key_name                    = var.cluster_instance_keypair_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  subnet_id                   = module.vpc_app.public_subnet_ids[0]
  associate_public_ip_address = true
  tags = {
    Name = "${var.eks_cluster_name}-worker-bastion"
  }
}

# Create a security group allowing SSH access.
resource "aws_security_group" "bastion" {
  vpc_id = module.vpc_app.vpc_id

  # Outbound Everything
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound SSH from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.eks_cluster_name}-worker-bastion"
  }
}

# Look up the latest ubuntu AMI.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "image-type"
    values = ["machine"]
  }

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}
