# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A EKS CLUSTER WITH FARGATE AS WORKERS
# These templates show an example of how to provision an EKS cluster set up to support Fargate to run workloads.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.52"
    }
  }
}

# ------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# ------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------------------------
# CONFIGURE OUR KUBERNETES CONNECTIONS
# Note that we can't configure our Kubernetes connection until EKS is up and running, so we try to depend on the
# resource being created.
# ------------------------------------------------------------------------------

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
    command     = "kubergrunt"
    args        = ["eks", "token", "--cluster-id", module.eks_cluster.eks_cluster_name]
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

  cluster_name              = var.eks_cluster_name
  kubernetes_version        = var.kubernetes_version
  configure_kubectl         = var.configure_kubectl
  kubectl_config_path       = var.kubectl_config_path
  enabled_cluster_log_types = ["api"]

  vpc_id                       = module.vpc_app.vpc_id
  vpc_control_plane_subnet_ids = local.usable_subnet_ids

  # The following settings are used to manage the private API endpoint, including the ACL rules to control access to the
  # private API endpoint.
  endpoint_public_access                     = var.endpoint_public_access
  endpoint_public_access_cidrs               = null
  endpoint_private_access_security_group_ids = { bastion = aws_security_group.bastion.id }

  # We can't use any kubergrunt scripts if there is no public endpoint access in this example
  use_kubergrunt_verification  = var.endpoint_public_access
  use_upgrade_cluster_script   = var.endpoint_public_access
  use_vpc_cni_customize_script = var.endpoint_public_access

  # Make sure the control plane services can operate without worker nodes
  schedule_control_plane_services_on_fargate = true
  vpc_worker_subnet_ids                      = local.usable_subnet_ids
}

module "eks_k8s_role_mapping" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-k8s-role-mapping?ref=v0.9.6"
  source = "../../modules/eks-k8s-role-mapping"

  eks_worker_iam_role_arns                   = []
  eks_fargate_profile_executor_iam_role_arns = [module.eks_cluster.eks_default_fargate_execution_role_arn_without_dependency]

  iam_role_to_rbac_group_mappings = {
    (aws_iam_role.bastion.arn) = ["system:masters"]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE BASTION HOST TO ACCESS PRIVATE ENDPOINT
# In Private API only mode, we can only access the Kubernetes API endpoint from within the VPC so we need an instance
# that we can connect to within the VPC to access the private API endpoint.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.nano"
  key_name                    = var.keypair_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  subnet_id                   = module.vpc_app.public_subnet_ids[0]
  associate_public_ip_address = true
  user_data = templatefile(
    "${path.module}/user-data/user-data.sh",
    {
      kubernetes_version = var.kubernetes_version
      eks_cluster_arn    = module.eks_cluster.eks_cluster_arn
    },
  )

  tags = {
    Name = "${var.eks_cluster_name}-endpoint-bastion"
  }
}

# Create an IAM role and instance profile that will allow the EC2 instance to retrieve EKS tokens.
resource "aws_iam_role" "bastion" {
  name               = "${var.eks_cluster_name}-endpoint-bastion"
  assume_role_policy = data.aws_iam_policy_document.allow_ec2_instances_to_assume_role.json
}

resource "aws_iam_instance_profile" "bastion" {
  role       = aws_iam_role.bastion.name
  name       = "${var.eks_cluster_name}-endpoint-bastion"
  depends_on = [aws_iam_role_policy.allow_eks_metadata]
}

# This policy allows the instance to read the EKS cluster metadata.
resource "aws_iam_role_policy" "allow_eks_metadata" {
  name   = "allow-eks-metadata"
  role   = aws_iam_role.bastion.name
  policy = data.aws_iam_policy_document.allow_eks_metadata.json
}

data "aws_iam_policy_document" "allow_eks_metadata" {
  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "allow_ec2_instances_to_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
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
    Name = "${var.eks_cluster_name}-endpoint-bastion"
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
