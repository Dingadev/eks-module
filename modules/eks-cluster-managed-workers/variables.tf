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
  description = "The name of the EKS cluster (e.g. eks-prod). This is used to namespace all the resources created by these templates."
  type        = string
}

# Properties of the EKS Managed EC2 Instances

variable "node_group_configurations" {
  description = "Configure one or more Node Groups to manage the EC2 instances in this cluster."
  # Ideally, this would be a map of (string, object), with all the supported properties, but object does not support
  # optional properties. We can't use a map(any) either as that would require the values to all have the same type.
  type = any

  # Each configuration must be keyed by a unique string that will be used as a suffix for the node group name. The
  # values support the following attributes:
  #
  #
  # OPTIONAL (defaults to value of corresponding module input):
  # - subnet_ids          list(string)       : (Defaults to value from var.node_group_default_subnet_ids) A list of the
  #                                            subnets into which the EKS Cluster's managed nodes will be launched.
  #                                            These should usually be all private subnets and include one in each AWS
  #                                            Availability Zone. NOTE: If using a cluster autoscaler with EBS volumes,
  #                                            each ASG may only belong to a single availability zone.
  # - min_size            number             : (Defaults to value from var.node_group_default_min_size) The minimum
  #                                            number of EC2 Instances representing workers launchable for this EKS
  #                                            Cluster. Useful for auto-scaling limits.
  # - max_size            number             : (Defaults to value from var.node_group_default_max_size) The maximum
  #                                            number of EC2 Instances representing workers that must be running for
  #                                            this EKS Cluster. We recommend making this at least twice the min_size,
  #                                            even if you don't plan on scaling the cluster up and down, as the extra
  #                                            capacity will be used to deploy updates to the cluster.
  # - desired_size        number             : (Defaults to value from var.node_group_default_desired_size) The current
  #                                            desired number of EC2 Instances representing workers that must be running
  #                                            for this EKS Cluster.
  # - instance_types      list(string)       : (Defaults to value from var.node_group_default_instance_types) A list of
  #                                            instance types (e.g., t2.medium) to use for the EKS Cluster's worker
  #                                            nodes. EKS will choose from this list of instance types when launching
  #                                            new instances. When using launch templates, this setting will override
  #                                            the configured instance type of the launch template.
  # - capacity_type       string             : (Defaults to value from var.node_group_default_capacity_type) Type of capacity
  #                                            associated with the EKS Node Group. Valid values: ON_DEMAND, SPOT.
  # - force_update_version bool              : (Defaults to value from var.node_group_default_force_update_version)
  #                                            Whether to force the roll out of release versions to the EKS workers.
  #                                            When true, this will forcefully delete any pods after 15 minutes if it is
  #                                            not able to safely drain the nodes.
  # - launch_template     LaunchTemplate     : (Defaults to value from var.node_group_default_launch_template)
  #                                            Launch template to use for the node. Specify either Name or ID of launch
  #                                            template. Must include version. Although the API supports using the
  #                                            values "$Latest" and "$Default" to configure the version, this can lead
  #                                            to a perpetual diff. Use the `latest_version` or `default_version` output
  #                                            of the aws_launch_template data source or resource instead. See
  #                                            https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group#launch_template-configuration-block
  #                                            for more information.
  # - disk_size           number             : (Defaults to value from var.node_group_default_disk_size) Root disk size
  #                                            in GiB for the worker nodes.
  #                                            Ignored if launch_template is configured.
  # - ami_type            string             : (Defaults to value from var.node_group_default_ami_type) Type of Amazon
  #                                            Machine Image (e.g. AL2_x86_64, AL2_x86_64_GPU) associated with the EKS
  #                                            Node Group.
  #                                            Ignored if launch_template is configured.
  # - ami_version         string             : (Defaults to value from var.node_group_default_ami_version) Version of
  #                                            the AMI to use for the EKS node groups. If null, the latest version for
  #                                            the given Kubernetes version will be used.
  #                                            Ignored if launch_template is configured.
  # - tags                map(string)        : (Defaults to value from var.node_group_default_tags) Custom tags to apply
  #                                            to the EC2 Instances in this node group. This should be a key value pair,
  #                                            where the keys are tag keys and values are the tag values. Merged with
  #                                            var.common_tags.
  # - labels              map(string)        : (Defaults to value from var.node_group_default_labels) Custom Kubernetes
  #                                            Labels to apply to the EC2 Instances in this node group. This should be a
  #                                            key value pair, where the keys are label keys and values are the label
  #                                            values. Merged with var.common_labels.
  # - taints              list(map(string))  : (Defaults to value from var.node_group_default_taints) Custom Kubernetes
  #                                            taint to apply to the EC2 Instances in this node group. See below for
  #                                            structure of taints.
  #
  # Structure of LaunchTemplate object:
  # - name     string  : The Name of the Launch Template to use. One of ID or Name should be provided.
  # - id       string  : The ID of the Launch Template to use. One of ID or Name should be provided.
  # - version  string  : The version of the Launch Template to use.
  #
  # Structure of Taints Object: [{},{}]
  # - key     string  : The key of the taint. Maximum length of 63.
  # - value   string  : The value of the taint. Maximum length of 63.
  # - effect  string  : The effect of the taint. Valid values: NO_SCHEDULE, NO_EXECUTE, PREFER_NO_SCHEDULE.
  #
  # Example:
  # node_group_configurations = {
  #   ngroup1 = {
  #     desired_size = 1
  #     min_size     = 1
  #     max_size     = 3
  #     subnet_ids  = [data.terraform_remote_state.vpc.outputs.private_app_subnet_ids[0]]
  #   }
  #   asg2 = {
  #     desired_size   = 1
  #     min_size       = 1
  #     max_size       = 3
  #     subnet_ids     = [data.terraform_remote_state.vpc.outputs.private_app_subnet_ids[0]]
  #     disk_size      = 50
  #   }
  #   ngroup2 = {}  # Only defaults
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

# Ideally we don't need this variable, but for_each breaks when the values of the node_group_configurations map depends
# on resources. To work around this, we allow the user to pass in the keys of the node_group_configurations map
# separately.
variable "node_group_names" {
  description = "The names of the node groups. When null, this value is automatically calculated from the node_group_configurations map. This variable must be set if any of the values of the node_group_configurations map depends on a resource that is not available at plan time to work around terraform limitations with for_each."
  type        = list(string)
  default     = null
}

# Defaults for the Node Group configurations passed in through var.node_group_configurations. These values are used when
# the corresponding setting is omitted from the underlying map. Refer to the documentation under
# var.node_group_configurations for more on info on what each of these settings do.

variable "node_group_default_subnet_ids" {
  description = "Default value for subnet_ids field of node_group_configurations."
  type        = list(string)
  default     = null
}

variable "node_group_default_min_size" {
  description = "Default value for min_size field of node_group_configurations."
  type        = number
  default     = 1
}

variable "node_group_default_max_size" {
  description = "Default value for max_size field of node_group_configurations."
  type        = number
  default     = 1
}

variable "node_group_default_desired_size" {
  description = "Default value for desired_size field of node_group_configurations."
  type        = number
  default     = 1
}

variable "node_group_default_instance_types" {
  description = "Default value for instance_types field of node_group_configurations."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_default_capacity_type" {
  description = "Default value for capacity_type field of node_group_configurations."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_group_default_force_update_version" {
  description = "Whether to force the roll out of release versions to the EKS workers. When true, this will forcefully delete any pods after 15 minutes if it is not able to safely drain the nodes. When null (default), this setting is false."
  type        = bool
  default     = null
}

variable "node_group_default_launch_template" {
  description = "Default value for launch_template field of node_group_configurations."
  type = object({
    name    = string
    id      = string
    version = string
  })
  default = null
}

variable "node_group_default_disk_size" {
  description = "Default value for disk_size field of node_group_configurations."
  type        = number
  default     = 30
}

variable "node_group_default_ami_type" {
  description = "Default value for ami_type field of node_group_configurations."
  type        = string
  default     = "AL2_x86_64"
}

variable "node_group_default_ami_version" {
  description = "Default value for ami_version field of node_group_configurations."
  type        = string
  default     = null
}

variable "node_group_default_tags" {
  description = "Default value for tags field of node_group_configurations. Unlike common_tags which will always be merged in, these tags are only used if the tags field is omitted from the configuration."
  type        = map(string)
  default     = {}
}

variable "node_group_default_labels" {
  description = "Default value for labels field of node_group_configurations. Unlike common_labels which will always be merged in, these labels are only used if the labels field is omitted from the configuration."
  type        = map(string)
  default     = {}
}

variable "node_group_default_taints" {
  description = "Default value for taint field of node_group_configurations. These taints are only used if the taint field is omitted from the configuration."
  type        = list(map(string))
  default     = []
}


# Customization options for Node Group name

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

variable "kubernetes_version" {
  description = "The version of Kubernetes to use for the AMI. Defaults to the Kubernetes version of the EKS cluster."
  type        = string
  default     = null
}

variable "cluster_instance_keypair_name" {
  description = "The EC2 Keypair name used to SSH into the EKS Cluster's EC2 Instances. To disable keypairs, pass in blank."
  type        = string
  default     = null
}

variable "allow_ssh_from_security_groups" {
  description = "List of Security Group IDs to allow SSH access from. Only used if var.cluster_instance_keypair_name is set. Set to null to allow access from all locations."
  type        = list(string)
  default     = []
}

variable "common_labels" {
  description = "A map of key-value pairs of Kubernetes labels to apply to all EC2 instances, across all Node Groups."
  type        = map(string)
  default     = {}
}

variable "common_tags" {
  description = "A map of key-value pairs of AWS tags to apply to all EC2 instances, across all Node Groups."
  type        = map(string)
  default     = {}
}

variable "create_resources" {
  description = "If you set this variable to false, this module will not create any resources. This is used as a workaround because Terraform does not allow you to use the 'count' parameter on modules. By using this parameter, you can optionally create or not create the resources within this module."
  type        = bool
  default     = true
}

variable "worker_iam_role_permissions_boundary" {
  description = "ARN of permissions boundary to apply to the worker IAM role - the IAM role created for the EKS worker nodes."
  type        = string
  default     = null
}