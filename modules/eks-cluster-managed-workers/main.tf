# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE MANAGED WORKER NODES FOR AN ELASTIC CONTAINER SERVICE FOR KUBERNETES (EKS) CLUSTER
# These templates launch worker nodes for an EKS cluster that you can use for running Docker containers. This includes:
# - Managed node groups
# - Security group
# - IAM roles and policies
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM REQUIREMENTS FOR RUNNING THIS MODULE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"
  required_providers {
    # Launch templates with working capacity types were launched in 3.20.0
    aws = ">= 3.20.0, < 4.0"
  }
}


# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE EKS CLUSTER MANAGED NODE GROUP
# ---------------------------------------------------------------------------------------------------------------------

# Merge with default values so that all the keys are defined. This simplifies the logic for defaults in the resource
# when we lookup the properties.
locals {
  combined_node_group_configurations = {
    for name, config in var.node_group_configurations :
    name => {
      subnet_ids           = lookup(config, "subnet_ids", var.node_group_default_subnet_ids)
      min_size             = lookup(config, "min_size", var.node_group_default_min_size)
      max_size             = lookup(config, "max_size", var.node_group_default_max_size)
      desired_size         = lookup(config, "desired_size", var.node_group_default_desired_size)
      instance_types       = lookup(config, "instance_types", var.node_group_default_instance_types)
      capacity_type        = lookup(config, "capacity_type", var.node_group_default_capacity_type)
      force_update_version = lookup(config, "force_update_version", var.node_group_default_force_update_version)
      launch_template      = lookup(config, "launch_template", var.node_group_default_launch_template)
      disk_size            = lookup(config, "disk_size", var.node_group_default_disk_size)
      ami_type             = lookup(config, "ami_type", var.node_group_default_ami_type)
      ami_version          = lookup(config, "ami_version", var.node_group_default_ami_version)
      tags                 = lookup(config, "tags", var.node_group_default_tags)
      labels               = lookup(config, "labels", var.node_group_default_labels)
      taints               = lookup(config, "taints", var.node_group_default_taints)
    }
  }

  node_group_for_each = (
    var.node_group_names == null
    ? {
      for name, config in local.combined_node_group_configurations : name => name
    }
    : {
      for name in var.node_group_names : name => name
    }
  )
}

resource "aws_eks_node_group" "eks_worker" {
  for_each = var.create_resources ? local.node_group_for_each : {}
  depends_on = [
    aws_iam_role_policy_attachment.worker_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.worker_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.worker_AmazonEC2ContainerRegistryReadOnly,
  ]

  cluster_name    = var.cluster_name
  node_group_name = "${local.resource_name}-${each.key}"
  node_role_arn   = local.iam_role_arn
  version         = var.kubernetes_version

  subnet_ids           = local.combined_node_group_configurations[each.key].subnet_ids
  release_version      = local.combined_node_group_configurations[each.key].ami_version
  capacity_type        = local.combined_node_group_configurations[each.key].capacity_type
  force_update_version = local.combined_node_group_configurations[each.key].force_update_version

  # If the values are specified in the launch template, then we have to set them to null here else there are errors
  ami_type  = local.combined_node_group_configurations[each.key].launch_template == null ? local.combined_node_group_configurations[each.key].ami_type : null
  disk_size = local.combined_node_group_configurations[each.key].launch_template == null ? local.combined_node_group_configurations[each.key].disk_size : null

  # If launch template instance_type is needed pass null to the node group configuration instances_types
  instance_types = local.combined_node_group_configurations[each.key].instance_types

  dynamic "launch_template" {
    # If launch template block is passed to the module enable the configuration block
    for_each = local.combined_node_group_configurations[each.key].launch_template == null ? [] : ["Use Launch Template"]
    content {
      # As we need id OR name, we need to check for existence of the attribute before assinging the value
      name    = lookup(local.combined_node_group_configurations[each.key].launch_template, "name", null)
      id      = lookup(local.combined_node_group_configurations[each.key].launch_template, "id", null)
      version = local.combined_node_group_configurations[each.key].launch_template.version
    }
  }

  labels = merge(var.common_labels, local.combined_node_group_configurations[each.key].labels)
  tags   = merge(var.common_tags, local.combined_node_group_configurations[each.key].tags)

  dynamic "taint" {
    for_each = local.combined_node_group_configurations[each.key].taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  scaling_config {
    min_size     = local.combined_node_group_configurations[each.key].min_size
    max_size     = local.combined_node_group_configurations[each.key].max_size
    desired_size = local.combined_node_group_configurations[each.key].desired_size
  }

  # This lifecycle policy change is to prevent conflicts with the cluster-auto-scaler, by ignoring the desired size once it has been scaled
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  dynamic "remote_access" {
    # The contents of the list is irrelevant, as all we need to know if whether or not to enable this block
    for_each = (
      # We can't configure remote access settings when using launch templates.
      local.combined_node_group_configurations[each.key].launch_template == null && var.cluster_instance_keypair_name != null
      ? ["use_remote_access"]
      : []
    )

    content {
      ec2_ssh_key               = var.cluster_instance_keypair_name
      source_security_group_ids = var.allow_ssh_from_security_groups
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE IAM ROLES AND POLICIES FOR THE WORKERS
# IAM Roles allow us to grant the cluster instances access to AWS Resources. Here we attach a few core IAM policies that
# are necessary for the Kubernetes workers to function. We export the IAM role id so users of this module can add their
# own custom IAM policies.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "eks_worker" {
  count                = var.iam_role_already_exists == false && var.create_resources ? 1 : 0
  name                 = local.iam_role_name
  assume_role_policy   = data.aws_iam_policy_document.allow_ec2_instances_to_assume_role.json
  permissions_boundary = var.worker_iam_role_permissions_boundary
}

# This policy is necessary for the EKS worker nodes to pull enough information from AWS to be able to connect to EKS
# clusters
resource "aws_iam_role_policy_attachment" "worker_AmazonEKSWorkerNodePolicy" {
  count      = var.create_resources ? 1 : 0
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = local.iam_role_name
  depends_on = [aws_iam_role.eks_worker]
}

# This policy provides the Amazon VPC CNI Plugin (amazon-vpc-cni-k8s) the permissions it requires to modify the IP
# address configuration on your EKS worker nodes.
resource "aws_iam_role_policy_attachment" "worker_AmazonEKS_CNI_Policy" {
  count      = var.create_resources ? 1 : 0
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = local.iam_role_name
  depends_on = [aws_iam_role.eks_worker]

  # For an explanation of why this is here, see the aws_launch_configuration.eks_worker resource
  lifecycle {
    create_before_destroy = true
  }
}

# This policy is necessary to allow the cluster to pull containers from ECR. At a minimum, the EKS workers needs to be
# able to access the container image for the Amazon VPC CNI Plugin.
resource "aws_iam_role_policy_attachment" "worker_AmazonEC2ContainerRegistryReadOnly" {
  count      = var.create_resources ? 1 : 0
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = local.iam_role_name
  depends_on = [aws_iam_role.eks_worker]
}

# Only allow EC2 instances to assume this role
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

# Look up IAM role if it already exists
data "aws_iam_role" "existing" {
  count = var.iam_role_already_exists ? 1 : 0
  name  = local.iam_role_name
}

locals {
  # Lookup the IAM Role ARN based on the following:
  # - If the IAM role already exists and the IAM role ARN is directly passed in, use that.
  # - If the IAM role already exists and the IAM role ARN is NOT directly passed in, lookup using the IAM role name.
  # - Otherwise, create a new IAM role and use that.
  # - Finally, a base case is used to set to null. This case is when create_resources = false.
  iam_role_arn = (
    var.iam_role_already_exists && var.iam_role_arn != null
    ? var.iam_role_arn
    : (
      length(data.aws_iam_role.existing) > 0
      ? data.aws_iam_role.existing[0].arn
      : (
        length(aws_iam_role.eks_worker) > 0
        ? aws_iam_role.eks_worker[0].arn
        : null
      )
    )
  )

  # If the IAM role ARN is directly passed in, compute the name from the ARN by retrieving the last part of the ARN.
  iam_role_name = (
    var.iam_role_already_exists && var.iam_role_arn != null
    ? (
      # Compute the name from the ARN. The Role ARN is typically:
      # arn:aws:iam::ACCOUNT_ID:role/ROLE
      # so we use a regex to extract the last path part after role.
      replace(var.iam_role_arn, "/.*role/([^/]+).*/", "$1")
    )
    : (
      # If the IAM role name is not passed in, default to something based on the resource_name.
      var.iam_role_name == null ? "${local.resource_name}-worker" : var.iam_role_name
    )
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# Compute the name that should be used for the resources.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  resource_name = "${var.name_prefix}${var.cluster_name}${var.name_suffix}"
}
