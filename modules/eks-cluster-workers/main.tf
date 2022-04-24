# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE WORKER NODES FOR AN ELASTIC CONTAINER SERVICE FOR KUBERNETES (EKS) CLUSTER
# These templates launch worker nodes for an EKS cluster that you can use for running Docker containers. This includes:
# - Auto Scaling Group (ASG)
# - Launch template
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
    aws = {
      source = "hashicorp/aws"
      # Versions between 3.68 and 3.71 had a bug where launch template versions were not being updated correctly, causing
      # Terraform to continue to use the old version with the associated ASG across updates to the launch template.
      version = "!= 3.68.0, != 3.69.0, != 3.70.0, < 4.0"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE EKS CLUSTER AUTO SCALING GROUP (ASG)
# The EKS Cluster's EC2 Worker Nodes exist in an Auto Scaling Group so that failed instances will automatically be
# replaced, and we can easily scale the cluster's resources.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  autoscaling_group_names = {
    for name, config in var.autoscaling_group_configurations :
    name => name
  }

  combined_autoscaling_group_configurations = {
    for name, config in var.autoscaling_group_configurations :
    name => merge(local.asg_default_configuration, config)
  }

  default_tags = [
    {
      key                 = "Name"
      value               = local.resource_name
      propagate_at_launch = true
    },
    {
      # This is necessary for the EKS control plane to find out which EC2 instances are a part of the cluster
      key                 = "kubernetes.io/cluster/${var.cluster_name}"
      value               = "owned"
      propagate_at_launch = true
    },
  ]

  # The autoscaler only checks for the tags existence, the value doesn't actually matter
  autoscaler_discovery_tags = var.include_autoscaler_discovery_tags ? [
    {
      key                 = "k8s.io/cluster-autoscaler/enabled"
      value               = "true"
      propagate_at_launch = true
    },
    {
      key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
      value               = "true"
      propagate_at_launch = true
    },
  ] : []

  asg_default_configuration = {
    min_size                                 = var.asg_default_min_size
    max_size                                 = var.asg_default_max_size
    asg_instance_type                        = var.asg_default_instance_type
    asg_instance_ami                         = var.asg_default_instance_ami
    asg_instance_user_data_base64            = var.asg_default_instance_user_data_base64
    asg_instance_root_volume_size            = var.asg_default_instance_root_volume_size
    asg_instance_root_volume_type            = var.asg_default_instance_root_volume_type
    asg_instance_root_volume_iops            = var.asg_default_instance_root_volume_iops
    asg_instance_root_volume_throughput      = var.asg_default_instance_root_volume_throughput
    asg_instance_root_volume_encryption      = var.asg_default_instance_root_volume_encryption
    tags                                     = var.asg_default_tags
    enable_detailed_monitoring               = var.asg_default_enable_detailed_monitoring
    use_multi_instances_policy               = var.asg_default_use_multi_instances_policy
    multi_instance_overrides                 = var.asg_default_multi_instance_overrides
    on_demand_allocation_strategy            = var.asg_default_on_demand_allocation_strategy
    on_demand_base_capacity                  = var.asg_default_on_demand_base_capacity
    on_demand_percentage_above_base_capacity = var.asg_default_on_demand_percentage_above_base_capacity
    spot_allocation_strategy                 = var.asg_default_spot_allocation_strategy
    spot_instance_pools                      = var.asg_default_spot_instance_pools
    spot_max_price                           = var.asg_default_spot_max_price
  }
}

resource "aws_autoscaling_group" "eks_worker" {
  for_each              = var.create_resources ? local.autoscaling_group_names : {}
  name_prefix           = "${local.resource_name}-${each.key}-"
  min_size              = local.combined_autoscaling_group_configurations[each.key].min_size
  max_size              = local.combined_autoscaling_group_configurations[each.key].max_size
  vpc_zone_identifier   = local.combined_autoscaling_group_configurations[each.key].subnet_ids
  load_balancers        = var.load_balancers
  target_group_arns     = var.target_group_arns
  enabled_metrics       = var.enabled_metrics
  max_instance_lifetime = var.max_instance_lifetime

  dynamic "launch_template" {
    # The contents of the list is irrelevant, as it is only used to determine if we should include this block or not.
    for_each = local.combined_autoscaling_group_configurations[each.key].use_multi_instances_policy ? [] : ["Use Launch Template"]
    content {
      id      = var.create_resources ? aws_launch_template.eks_worker[each.key].id : null
      version = aws_launch_template.eks_worker[each.key].latest_version
    }
  }

  dynamic "mixed_instances_policy" {
    # The contents of the list is irrelevant, as it is only used to determine if we should include this block or not.
    for_each = local.combined_autoscaling_group_configurations[each.key].use_multi_instances_policy ? ["Use Multi Instances Policy"] : []
    content {
      instances_distribution {
        on_demand_allocation_strategy            = local.combined_autoscaling_group_configurations[each.key].on_demand_allocation_strategy
        on_demand_base_capacity                  = local.combined_autoscaling_group_configurations[each.key].on_demand_base_capacity
        on_demand_percentage_above_base_capacity = local.combined_autoscaling_group_configurations[each.key].on_demand_percentage_above_base_capacity
        spot_allocation_strategy                 = local.combined_autoscaling_group_configurations[each.key].spot_allocation_strategy
        spot_instance_pools                      = local.combined_autoscaling_group_configurations[each.key].spot_instance_pools
        spot_max_price                           = local.combined_autoscaling_group_configurations[each.key].spot_max_price
      }
      launch_template {
        launch_template_specification {
          launch_template_id = var.create_resources ? aws_launch_template.eks_worker[each.key].id : null
          version            = aws_launch_template.eks_worker[each.key].latest_version
        }

        dynamic "override" {
          for_each = local.combined_autoscaling_group_configurations[each.key].multi_instance_overrides
          content {
            instance_type     = lookup(override.value, "instance_type", null)
            weighted_capacity = lookup(override.value, "weighted_capacity", null)
          }
        }

      }
    }
  }

  dynamic "tag" {
    for_each = concat(local.default_tags, local.autoscaler_discovery_tags, local.combined_autoscaling_group_configurations[each.key].tags)
    content {
      key                 = tag.value.key
      value               = tag.value.value
      propagate_at_launch = tag.value.propagate_at_launch
    }
  }

  # We need a create before destroy here such that we deploy a new ASG pool first prior to spinning down the old one.
  # This allows for a more graceful transition when changes that require regenerating the ASG are made.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "eks_worker" {
  for_each      = var.create_resources ? local.autoscaling_group_names : {}
  name_prefix   = "${local.resource_name}-${each.key}-"
  image_id      = local.combined_autoscaling_group_configurations[each.key].asg_instance_ami
  instance_type = local.combined_autoscaling_group_configurations[each.key].asg_instance_type
  key_name      = var.cluster_instance_keypair_name
  user_data     = local.combined_autoscaling_group_configurations[each.key].asg_instance_user_data_base64

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      encrypted   = local.combined_autoscaling_group_configurations[each.key].asg_instance_root_volume_encryption
      volume_size = local.combined_autoscaling_group_configurations[each.key].asg_instance_root_volume_size
      volume_type = local.combined_autoscaling_group_configurations[each.key].asg_instance_root_volume_type
      iops        = local.combined_autoscaling_group_configurations[each.key].asg_instance_root_volume_iops
      throughput  = local.combined_autoscaling_group_configurations[each.key].asg_instance_root_volume_throughput
    }
  }

  iam_instance_profile {
    name = var.create_resources ? aws_iam_instance_profile.eks_worker[0].name : null
  }

  network_interfaces {
    associate_public_ip_address = var.cluster_instance_associate_public_ip_address
    security_groups = concat(
      (
        # NOTE: It is assumed that the cluster security group is provided via additional_security_group_ids when
        # eks_cluster_vpc_config is null.
        var.use_cluster_security_group && local.eks_cluster_vpc_config != null
        ? [local.eks_cluster_vpc_config.cluster_security_group_id]
        : []
      ),
      aws_security_group.eks_worker[*].id,
      var.additional_security_group_ids,
    )
  }

  # Enable detailed monitoring for EC2 instances in the autoscaling group
  dynamic "monitoring" {
    for_each = local.combined_autoscaling_group_configurations[each.key].enable_detailed_monitoring ? ["once"] : []
    content {
      enabled = true
    }
  }

  placement {
    tenancy = var.tenancy
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE IAM ROLES AND POLICIES FOR THE WORKERS
# IAM Roles allow us to grant the cluster instances access to AWS Resources. Here we attach a few core IAM policies that
# are necessary for the Kubernetes workers to function. We export the IAM role id so users of this module can add their
# own custom IAM policies.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "eks_worker" {
  count                 = var.iam_role_already_exists == false && var.create_resources ? 1 : 0
  assume_role_policy    = data.aws_iam_policy_document.allow_ec2_instances_to_assume_role.json
  force_detach_policies = var.force_detach_policies

  # Choose name or name_prefix dependent on the feature flag
  name        = var.use_resource_name_prefix ? null : local.iam_role_name
  name_prefix = var.use_resource_name_prefix ? local.iam_role_name : null
}

# This policy is necessary for the EKS worker nodes to pull enough information from AWS to be able to connect to EKS
# clusters
resource "aws_iam_role_policy_attachment" "worker_AmazonEKSWorkerNodePolicy" {
  count      = var.create_resources ? 1 : 0
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = local.iam_role_name_for_references
  depends_on = [aws_iam_role.eks_worker]
}

# This policy provides the Amazon VPC CNI Plugin (amazon-vpc-cni-k8s) the permissions it requires to modify the IP
# address configuration on your EKS worker nodes.
resource "aws_iam_role_policy_attachment" "worker_AmazonEKS_CNI_Policy" {
  count      = var.create_resources ? 1 : 0
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = local.iam_role_name_for_references
  depends_on = [aws_iam_role.eks_worker]
}

# This policy is necessary to allow the cluster to pull containers from ECR. At a minimum, the EKS workers needs to be
# able to access the container image for the Amazon VPC CNI Plugin.
resource "aws_iam_role_policy_attachment" "worker_AmazonEC2ContainerRegistryReadOnly" {
  count      = var.create_resources ? 1 : 0
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = local.iam_role_name_for_references
  depends_on = [aws_iam_role.eks_worker]
}

# This policy allows the instance to read the attached tags on instances.
resource "aws_iam_role_policy" "allow_describe_ec2_tags" {
  count      = var.create_resources && local.use_inline_policies ? 1 : 0
  name       = "${local.resource_name}-allow-describe-ec2-tags"
  role       = local.iam_role_name_for_references
  policy     = data.aws_iam_policy_document.allow_describe_ec2_tags.json
  depends_on = [aws_iam_role.eks_worker]
}

resource "aws_iam_policy" "allow_describe_ec2_tags" {
  count       = var.create_resources && var.use_managed_iam_policies ? 1 : 0
  name_prefix = "${local.resource_name}-allow-describe-ec2-tags"
  policy      = data.aws_iam_policy_document.allow_describe_ec2_tags.json
  depends_on  = [aws_iam_role.eks_worker]
}

resource "aws_iam_role_policy_attachment" "allow_describe_ec2_tags" {
  count      = var.create_resources && var.use_managed_iam_policies ? 1 : 0
  role       = local.iam_role_name_for_references
  policy_arn = aws_iam_policy.allow_describe_ec2_tags[0].arn
  depends_on = [aws_iam_role.eks_worker]
}

data "aws_iam_policy_document" "allow_describe_ec2_tags" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeTags"]
    resources = ["*"]
  }
}

# To assign an IAM Role to an EC2 instance, we need to create the intermediate concept of an "IAM Instance Profile".
resource "aws_iam_instance_profile" "eks_worker" {
  count      = var.create_resources ? 1 : 0
  role       = local.iam_role_name_for_references
  depends_on = [aws_iam_role.eks_worker]

  # Choose name or name_prefix dependent on the feature flag
  name        = var.use_resource_name_prefix ? null : local.iam_instance_profile_name
  name_prefix = var.use_resource_name_prefix ? local.iam_instance_profile_name : null

  # We need a create before destroy here such that when we replace the instance profile, it updates the launch template
  # with the new security group ID before destroying the old one.
  lifecycle {
    create_before_destroy = true
  }
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

# Look up IAM role if already exists
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
      local.iam_role_for_references != null
      ? local.iam_role_for_references.arn
      : null
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
      var.iam_role_name == null ? "${local.resource_name}" : var.iam_role_name
    )
  )

  # If the IAM instance profile name is not passed in, default to the iam role name.
  iam_instance_profile_name = var.iam_instance_profile_name == null ? local.iam_role_name : var.iam_instance_profile_name

  # The IAM Role Name to use when binding policies and instance profiles.
  iam_role_name_for_references = (
    local.iam_role_for_references != null
    ? local.iam_role_for_references.name
    : null
  )

  # Helper to return the IAM role data to use for references
  iam_role_for_references = (
    length(data.aws_iam_role.existing) > 0
    ? {
      name = data.aws_iam_role.existing[0].name
      arn  = data.aws_iam_role.existing[0].arn
    }
    : (
      length(aws_iam_role.eks_worker) > 0
      ? {
        name = aws_iam_role.eks_worker[0].name
        arn  = aws_iam_role.eks_worker[0].arn
      }
      : null
    )
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE EKS WORKER NODE SECURITY GROUP
# This will be an empty security group when the cluster security group is in use.
# Limits which ports are allowed inbound and outbound on the worker nodes. We export the security group id as an output
# so users of this module can add their own custom rules.
# These are configured based on the recommendations by AWS:
# https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html
# - Allowing all outbound ports and protocols
# - Allowing inbound ports between worker nodes
# - Allowing all inbound ports > 1025 from control plane
# Kubernetes will use a wide range of ports to communicate between kubelets, pods, and the control plane due to its
# handling of internal networking, so we need to allow liberal access between the workers and the control plane.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "eks_worker" {
  count       = var.create_resources ? 1 : 0
  description = "Security group for all nodes in the EKS cluster ${var.cluster_name}"
  vpc_id      = (var.vpc_id == null ? local.eks_cluster_vpc_config.vpc_id : var.vpc_id)

  # Choose name or name_prefix dependent on the feature flag
  name        = var.use_resource_name_prefix ? null : local.iam_role_name
  name_prefix = var.use_resource_name_prefix ? local.iam_role_name : null

  tags = merge(
    var.custom_tags_security_group,
    { "Name" = "${local.resource_name}" },
    # When using the cluster security group, we don't want to tag this security group as owned by the kubernetes cluster
    # since EKS only supports one security group with the tag per worker node.
    !var.use_cluster_security_group ? { "kubernetes.io/cluster/${var.cluster_name}" = "owned" } : {},
  )

  # We need a create before destroy here such that when we replace the security group, it updates the launch template
  # with the new security group ID before destroying the old one.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "eks_worker_allow_outbound_all" {
  count = (
    var.create_resources && (!var.use_cluster_security_group) && var.allow_all_outbound_network_calls
    ? 1 : 0
  )
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_worker[0].id
}

resource "aws_security_group_rule" "eks_worker_ingress_self" {
  count                    = var.create_resources && (!var.use_cluster_security_group) ? 1 : 0
  description              = "Allow worker nodes to communicate with each other"
  security_group_id        = aws_security_group.eks_worker[0].id
  source_security_group_id = aws_security_group.eks_worker[0].id
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
  type                     = "ingress"
}

resource "aws_security_group_rule" "eks_worker_ingress_cluster" {
  count = (var.create_resources && (!var.use_cluster_security_group)) ? 1 : 0

  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  security_group_id        = aws_security_group.eks_worker[0].id
  source_security_group_id = local.eks_control_plane_security_group_id
  protocol                 = "tcp"
  from_port                = 1025
  to_port                  = 65535
  type                     = "ingress"
}

# Modify the master node security group to allow the worker node to communicate with it
resource "aws_security_group_rule" "eks_ingress_node_https" {
  count = (var.create_resources && (!var.use_cluster_security_group)) ? 1 : 0

  description              = "Allow worker nodes to communicate with the cluster API Server"
  security_group_id        = local.eks_control_plane_security_group_id
  source_security_group_id = aws_security_group.eks_worker[0].id
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  type                     = "ingress"
}

# ---------------------------------------------------------------------------------------------------------------------
# Compute the name that should be used for the resources.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  resource_name = "${var.name_prefix}${var.cluster_name}${var.name_suffix}"
}
