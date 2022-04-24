# See https://www.packer.io/docs/templates/hcl_templates/blocks/packer for more info
packer {
  required_version = ">= 1.7.0"

  required_plugins {
    amazon = {
      version = ">=v1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# INPUT VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_auth_token" {
  type    = string
  default = env("GITHUB_OAUTH_TOKEN")
}

variable "gruntwork_installer_version" {
  type    = string
  default = "v0.0.24"
}

variable "kubernetes_version" {
  type    = string
  default = "1.22"
}

variable "terraform_aws_eks_branch" {
  type    = string
  default = ""
}

variable "terraform_aws_eks_version" {
  type    = string
  default = "~>0.20.0"
}

# ---------------------------------------------------------------------------------------------------------------------
# SOURCE IMAGE
# ---------------------------------------------------------------------------------------------------------------------

data "amazon-ami" "eks" {
  filters = {
    architecture        = "x86_64"
    name                = "amazon-eks-node-${var.kubernetes_version}-v*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["602401143452"]
  region      = var.aws_region
}

source "amazon-ebs" "eks" {
  ami_description = "An Amazon EKS-optimized AMI that is meant to be run as part of an EKS cluster."
  ami_name        = "gruntwork-amazon-eks-cluster-example-${uuidv4()}"
  instance_type   = "t2.micro"
  region          = var.aws_region
  source_ami      = data.amazon-ami.eks.id
  ssh_username    = "ec2-user"
}

# ---------------------------------------------------------------------------------------------------------------------
# BUILD STEPS
# ---------------------------------------------------------------------------------------------------------------------

build {
  sources = ["source.amazon-ebs.eks"]

  provisioner "shell" {
    environment_vars = ["GITHUB_OAUTH_TOKEN=${var.github_auth_token}"]
    inline           = ["curl -Ls https://raw.githubusercontent.com/gruntwork-io/gruntwork-installer/master/bootstrap-gruntwork-installer.sh | bash /dev/stdin --version '${var.gruntwork_installer_version}'", "gruntwork-install --module-name 'eks-scripts' --repo 'https://github.com/gruntwork-io/terraform-aws-eks' --tag '${var.terraform_aws_eks_version}' --branch '${var.terraform_aws_eks_branch}'"]
    pause_before     = "30s"
  }
}
