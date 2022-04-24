# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator when calling this terraform module.
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_partition" {
  description = "The AWS partition used for default AWS Resources."
  type        = string
  default     = "aws"
}

# General EKS Cluster properties

variable "cluster_name" {
  description = "The name of the EKS cluster (e.g. eks-prod). This is also used to namespace all the resources created by these templates."
  type        = string
}

# Properties of the EKS Cluster's EC2 Instances.

variable "autoscaling_group_configurations" {
  description = "Configure one or more Auto Scaling Groups (ASGs) to manage the EC2 instances in this cluster. If any of the values are not provided, the specified default variable will be used to lookup a default value."
  # Ideally, we will use a more strict type here but since we want to support required and optional values, and since
  # Terraform's type system only supports maps that have the same type for all values, we have to use the less useful
  # `any` type.
  type = any

  # Each configuration must be keyed by a unique string that will be used as a suffix for the ASG name. The values
  # support the following attributes:
  #
  # REQUIRED (must be provided for every entry):
  # - subnet_ids  list(string)  : A list of the subnets into which the EKS Cluster's worker nodes will be launched.
  #                               These should usually be all private subnets and include one in each AWS Availability
  #                               Zone. NOTE: If using a cluster autoscaler, each ASG may only belong to a single
  #                               availability zone.
  #
  # OPTIONAL (defaults to value of corresponding module input):
  # - min_size            number             : (Defaults to value from var.asg_default_min_size) The minimum number of
  #                                            EC2 Instances representing workers launchable for this EKS Cluster.
  #                                            Useful for auto-scaling limits.
  # - max_size            number             : (Defaults to value from var.asg_default_max_size) The maximum number of
  #                                            EC2 Instances representing workers that must be running for this EKS
  #                                            Cluster. We recommend making this at least twice the min_size, even if
  #                                            you don't plan on scaling the cluster up and down, as the extra capacity
  #                                            will be used to deploy updates to the cluster.
  # - asg_instance_type   string             : (Defaults to value from var.asg_default_instance_type) The type of
  #                                            instances to use for the ASG (e.g., t2.medium).
  # - asg_instance_ami   string              : (Defaults to value from var.asg_default_instance_ami) The ami that
  #                                            instances should use for the ASG .
  # - asg_instance_user_data_base64   string : (Defaults to value from var.asg_default_instance_user_data_base64) The base64 user-data content of
  #                                            instances to use for the ASG.
  # - asg_instance_root_volume_size   number : (Defaults to value from var.asg_default_instance_root_volume_size) The root volume size of
  #                                            instances to use for the ASG in GB (e.g., 40).
  # - asg_instance_root_volume_type   string : (Defaults to value from var.asg_default_instance_root_volume_type) The root volume type of
  #                                            instances to use for the ASG (e.g., "standard").
  # - asg_instance_root_volume_iops   number : (Defaults to value from var.asg_default_instance_root_volume_iops) The root volume iops of
  #                                            instances to use for the ASG (e.g., 200).
  # - asg_instance_root_volume_throughput   number : (Defaults to value from var.asg_default_instance_root_volume_throughput) The root volume throughput in MiBPS of
  #                                            instances to use for the ASG (e.g., 125).
  # - asg_instance_root_volume_encryption   bool  : (Defaults to value from var.asg_default_instance_root_volume_encryption)
  #                                             Whether or not to enable root volume encryption for instances of the ASG.
  # - tags                list(object[Tag])  : (Defaults to value from var.asg_default_tags) Custom tags to apply to the
  #                                            EC2 Instances in this ASG. Refer to structure definition below for the
  #                                            object type of each entry in the list.
  # - enable_detailed_monitoring   bool      : (Defaults to value from
  #                                            var.asg_default_enable_detailed_monitoring) Whether to enable
  #                                            detailed monitoring on the EC2 instances that comprise the ASG.
  # - use_multi_instances_policy   bool       : (Defaults to value from var.asg_default_use_multi_instances_policy)
  #                                             Whether or not to use a multi_instances_policy for the ASG.
  # - multi_instance_overrides     list(MultiInstanceOverride) : (Defaults to value from var.asg_default_multi_instance_overrides)
  #                                             List of multi instance overrides to apply. Each element in the list is
  #                                             an object that specifies the instance_type to use for the override, and
  #                                             the weighted_capacity.
  # - on_demand_allocation_strategy   string  : (Defaults to value from var.asg_default_on_demand_allocation_strategy)
  #                                             When using a multi_instances_policy the strategy to use when launching on-demand instances. Valid values: prioritized.
  # - on_demand_base_capacity   number        : (Defaults to value from var.asg_default_on_demand_base_capacity)
  #                                             When using a multi_instances_policy the absolute minimum amount of desired capacity that must be fulfilled by on-demand instances.
  # - on_demand_percentage_above_base_capacity   number : (Defaults to value from var.asg_default_on_demand_percentage_above_base_capacity)
  #                                             When using a multi_instances_policy the percentage split between on-demand and Spot instances above the base on-demand capacity.
  # - spot_allocation_strategy   string       : (Defaults to value from var.asg_default_spot_allocation_strategy)
  #                                             When using a multi_instances_policy how to allocate capacity across the Spot pools. Valid values: lowest-price, capacity-optimized.
  # - spot_instance_pools   number            : (Defaults to value from var.asg_default_spot_instance_pools)
  #                                             When using a multi_instances_policy the Number of Spot pools per availability zone to allocate capacity.
  #                                             EC2 Auto Scaling selects the cheapest Spot pools and evenly allocates Spot capacity across the number of Spot pools that you specify.
  # - spot_max_price   string                 : (Defaults to value from var.asg_default_spot_max_price, an empty string which means the on-demand price.)
  #                                             When using a multi_instances_policy the maximum price per unit hour that the user is willing to pay for the Spot instances.
  #
  # Structure of Tag object:
  # - key                  string  : The key for the tag to apply to the instance.
  # - value                string  : The value for the tag to apply to the instance.
  # - propagate_at_launch  bool    : Whether or not the tags should be propagated to the instance at launch time.
  #
  #
  # Example:
  # autoscaling_group_configurations = {
  #   "asg1" = {
  #     asg_instance_type = "t2.medium"
  #     subnet_ids        = [data.terraform_remote_state.vpc.outputs.private_app_subnet_ids[0]]
  #   },
  #   "asg2" = {
  #     max_size          = 3
  #     asg_instance_type = "t2.large"
  #     subnet_ids        = [data.terraform_remote_state.vpc.outputs.private_app_subnet_ids[1]]
  #
  #     tags = [{
  #       key                 = "size"
  #       value               = "large"
  #       propagate_at_launch = true
  #     }]
  #   }
  # }
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL MODULE PARAMETERS
# These variables have defaults, but may be overridden by the operator.
# ---------------------------------------------------------------------------------------------------------------------

variable "iam_role_already_exists" {
  description = "Whether or not the IAM role used for the workers already exists. When false, this module will create a new IAM role."
  type        = bool
  default     = false
}

variable "iam_role_name" {
  description = "Custom name for the IAM role. When null, a default name based on cluster_name will be used. One of iam_role_name and iam_role_arn is required (must be non-null) if iam_role_already_exists is true."
  type        = string
  default     = null
}

variable "iam_role_arn" {
  description = "ARN of the IAM role to use if iam_role_already_exists = true. When null, uses iam_role_name to lookup the ARN. One of iam_role_name and iam_role_arn is required (must be non-null) if iam_role_already_exists is true."
  type        = string
  default     = null
}

variable "iam_instance_profile_name" {
  description = "Custom name for the IAM instance profile. When null, the IAM role name will be used. If var.use_resource_name_prefix is true, this will be used as a name prefix."
  type        = string
  default     = null
}

variable "use_existing_cluster_config" {
  description = "When true, this module will retrieve vpc config and security group ids from the existing cluster with the provided cluster_name. When false, you must provide var.vpc_id and var.eks_control_plane_security_group_id."
  type        = bool
  default     = true
}

# Network configurations

variable "use_cluster_security_group" {
  description = "Whether or not to attach the EKS managed cluster security group to the worker nodes for control plane and cross worker network management. Avoiding the cluster security group allows you to better isolate worker nodes at the network level (E.g., disallowing free flowing traffic between Fargate Pods and self managed workers). It is recommended to use the cluster security group for most use cases. Refer to the module README for more information. If use_existing_cluster_config is false and this is set to true, it is assumed that the cluster security group is provided in var.additional_security_group_ids."
  type        = bool
  default     = true
}

variable "allow_all_outbound_network_calls" {
  description = "When true, this module will attach a security group rule to the instances that will allow all outbound network access. Only used if `use_cluster_security_group` is `false`."
  type        = bool
  default     = true
}

variable "eks_control_plane_security_group_id" {
  description = "Security group ID of the EKS Control Plane nodes to enhance to allow access to the control plane from the workers. Only used if `use_cluster_security_group` is `false`. Set to null to use the first security group assigned to the cluster."
  type        = string
  default     = null
}

# Customizations for the worker nodes

variable "name_prefix" {
  description = "Prefix resource names with this string. When you have multiple worker groups for the cluster, you can use this to namespace the resources."
  type        = string
  default     = ""
}

variable "name_suffix" {
  description = "Suffix resource names with this string. When you have multiple worker groups for the cluster, you can use this to namespace the resources."
  type        = string
  default     = ""
}

# Properties of the EKS Cluster's EC2 Instances

variable "asg_default_min_size" {
  description = "Default value for the min_size field of autoscaling_group_configurations. Any map entry that does not specify min_size will use this value."
  type        = number
  default     = 1
}

variable "asg_default_max_size" {
  description = "Default value for the max_size field of autoscaling_group_configurations. Any map entry that does not specify max_size will use this value."
  type        = number
  default     = 2
}

variable "asg_default_instance_type" {
  description = "Default value for the asg_instance_type field of autoscaling_group_configurations. Any map entry that does not specify asg_instance_type will use this value."
  type        = string
  default     = "t3.medium"
}

variable "asg_default_instance_ami" {
  description = "Default value for the asg_instance_ami field of autoscaling_group_configurations. Any map entry that does not specify asg_instance_ami will use this value."
  type        = string
  default     = null
}

variable "asg_default_instance_user_data_base64" {
  description = "Default value for the asg_instance_user_data_base64 field of autoscaling_group_configurations. Any map entry that does not specify asg_instance_user_data_base64 will use this value."
  type        = string
  default     = null
}

variable "asg_default_instance_root_volume_size" {
  description = "Default value for the asg_instance_root_volume_size field of autoscaling_group_configurations. Any map entry that does not specify asg_instance_root_volume_size will use this value."
  type        = number
  default     = 40
}

variable "asg_default_instance_root_volume_type" {
  description = "Default value for the asg_instance_root_volume_type field of autoscaling_group_configurations. Any map entry that does not specify asg_instance_root_volume_type will use this value."
  type        = string
  default     = "standard"
}

variable "asg_default_instance_root_volume_iops" {
  description = "Default value for the asg_instance_root_volume_iops field of autoscaling_group_configurations. Any map entry that does not specify asg_instance_root_volume_iops will use this value."
  type        = number
  default     = null
}

variable "asg_default_instance_root_volume_throughput" {
  description = "Default value for the asg_instance_root_volume_throughput field of autoscaling_group_configurations. Any map entry that does not specify asg_instance_root_volume_throughput will use this value."
  type        = number
  default     = null
}

variable "asg_default_instance_root_volume_encryption" {
  description = "Default value for the asg_instance_root_volume_encryption field of autoscaling_group_configurations. Any map entry that does not specify asg_instance_root_volume_encryption will use this value."
  type        = bool
  default     = true
}

variable "asg_default_tags" {
  description = "Default value for the tags field of autoscaling_group_configurations. Any map entry that does not specify tags will use this value."
  type = list(object({
    key                 = string
    value               = string
    propagate_at_launch = bool
  }))
  default = []
}

variable "asg_default_use_multi_instances_policy" {
  description = "Default value for the use_multi_instances_policy field of autoscaling_group_configurations. Any map entry that does not specify use_multi_instances_policy will use this value."
  type        = bool
  default     = false
}

variable "asg_default_on_demand_allocation_strategy" {
  description = "Default value for the on_demand_allocation_strategy field of autoscaling_group_configurations. Any map entry that does not specify on_demand_allocation_strategy will use this value."
  type        = string
  default     = null
}

variable "asg_default_on_demand_base_capacity" {
  description = "Default value for the on_demand_base_capacity field of autoscaling_group_configurations. Any map entry that does not specify on_demand_base_capacity will use this value."
  type        = number
  default     = null
}

variable "asg_default_on_demand_percentage_above_base_capacity" {
  description = "Default value for the on_demand_percentage_above_base_capacity field of autoscaling_group_configurations. Any map entry that does not specify on_demand_percentage_above_base_capacity will use this value."
  type        = number
  default     = null
}

variable "asg_default_spot_allocation_strategy" {
  description = "Default value for the spot_allocation_strategy field of autoscaling_group_configurations. Any map entry that does not specify spot_allocation_strategy will use this value."
  type        = string
  default     = null
}

variable "asg_default_spot_instance_pools" {
  description = "Default value for the spot_instance_pools field of autoscaling_group_configurations. Any map entry that does not specify spot_instance_pools will use this value."
  type        = number
  default     = null
}

variable "asg_default_spot_max_price" {
  description = "Default value for the spot_max_price field of autoscaling_group_configurations. Any map entry that does not specify spot_max_price will use this value. Set to empty string (default) to mean on-demand price."
  type        = string
  default     = null
}

variable "asg_default_multi_instance_overrides" {
  description = "Default value for the multi_instance_overrides field of autoscaling_group_configurations. Any map entry that does not specify multi_instance_overrides will use this value."
  default     = []

  # Ideally, we would use a concrete type here, but terraform doesn't support optional attributes yet, so we have to
  # resort to the untyped any.
  type = any

  # Example:
  # [
  #   {
  #     instance_type = "t3.micro"
  #     weighted_capacity = 2
  #   },
  #   {
  #     instance_type = "t3.medium"
  #     weighted_capacity = 1
  #   },
  # ]
}

variable "asg_default_enable_detailed_monitoring" {
  description = "Default value for the enable_detailed_monitoring field of autoscaling_group_configurations."
  type        = bool
  default     = true
}

variable "cluster_instance_keypair_name" {
  description = "The EC2 Keypair name used to SSH into the EKS Cluster's EC2 Instances. To disable keypairs, pass in blank."
  type        = string
  default     = null
}

variable "tenancy" {
  description = "The tenancy of the servers in this cluster. Must be one of: default, dedicated, or host."
  type        = string
  default     = "default"
}

variable "cluster_instance_associate_public_ip_address" {
  description = "Whether or not to associate a public IP address to the instances of the cluster. Will only work if the instances are launched in a public subnet."
  type        = bool
  default     = false
}

variable "include_autoscaler_discovery_tags" {
  description = "Adds additional tags to each ASG that allow a cluster autoscaler to auto-discover them."
  type        = bool
  default     = false
}

variable "custom_tags_security_group" {
  description = "A map of custom tags to apply to the Security Group for this EKS Cluster. The key is the tag name and the value is the tag value."
  type        = map(string)
  default     = {}

  # Example:
  #   {
  #     key1 = "value1"
  #     key2 = "value2"
  #   }
}

variable "additional_security_group_ids" {
  description = "A list of additional Security Groups IDs to be attached on the EKS Worker."
  type        = list(string)
  default     = []
}

variable "load_balancers" {
  description = "A list of elastic load balancer names to add to the autoscaling group names. Use with ELB classic and NLBs."
  type        = list(string)
  default     = []
}

variable "target_group_arns" {
  description = "A list of aws_alb_target_group ARNs, for use with Application Load Balancing."
  type        = list(string)
  default     = []
}

variable "enabled_metrics" {
  description = "A list of metrics to collect from the ASG. For a list of allowed values, see https://www.terraform.io/docs/providers/aws/r/autoscaling_group.html#enabled_metrics."
  type        = list(string)
  default     = []
}

variable "create_resources" {
  description = "If you set this variable to false, this module will not create any resources. This is used as a workaround because Terraform does not allow you to use the 'count' parameter on modules. By using this parameter, you can optionally create or not create the resources within this module."
  type        = bool
  default     = true
}

variable "max_instance_lifetime" {
  description = "The maximum amount of time, in seconds, that an instance inside an ASG can be in service, values must be either equal to 0 or between 604800 and 31536000 seconds. Note that this will be a disruptive shutdown: the ASG will not automatically drain the node prior to shutting it down."
  type        = number
  default     = null
}

variable "vpc_id" {
  description = "VPC id for the EKS cluster deployment."
  type        = string
  default     = null
}

variable "force_detach_policies" {
  description = "Whether to force detaching any policies the role has before destroying it. If policies are attached to the role via the aws_iam_policy_attachment resource and you are modifying the role name or path, the force_detach_policies argument must be set to true and applied before attempting the operation otherwise you will encounter a DeleteConflict error. The aws_iam_role_policy_attachment resource (recommended) does not have this requirement."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------------------------------------------------
# BACKWARD COMPATIBILITY FEATURE FLAGS
# The following variables are feature flags to enable and disable certain features in the module. These are primarily
# introduced to maintain backward compatibility by avoiding unnecessary resource creation.
# ---------------------------------------------------------------------------------------------------------------------

variable "use_resource_name_prefix" {
  description = "When true, all the relevant resources will be set to use the name_prefix attribute so that unique names are generated for them. This allows those resources to support recreation through create_before_destroy lifecycle rules. Set to false if you were using any version before 0.45.0 and wish to avoid recreating the entire worker pool on your cluster."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# BACKWARD COMPATIBILITY FEATURE FLAGS
# The following variables are feature flags to enable and disable certain features in the module. These are primarily
# introduced to maintain backward compatibility by avoiding unnecessary resource creation.
# ---------------------------------------------------------------------------------------------------------------------

variable "use_managed_iam_policies" {
  description = "When true, all IAM policies will be managed as dedicated policies rather than inline policies attached to the IAM roles. Dedicated managed policies are friendlier to automated policy checkers, which may scan a single resource for findings. As such, it is important to avoid inline policies when targeting compliance with various security standards."
  type        = bool
  default     = true
}

locals {
  use_inline_policies = var.use_managed_iam_policies == false
}
