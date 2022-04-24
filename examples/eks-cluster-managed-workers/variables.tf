# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# ---------------------------------------------------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These variables are expected to be passed in by the operator
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_region" {
  description = "The AWS region in which all resources will be created. You must use a region with EKS available."
  type        = string
}

variable "vpc_name" {
  description = "The name of the VPC that will be created to house the EKS cluster."
  type        = string
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster."
  type        = string
}

# NOTE: Setting this to a CIDR block that you do not own will prevent your ability to reach the API server. You will
# also be unable to configure the EKS IAM role mapping remotely through this terraform code.
variable "endpoint_public_access_cidrs" {
  description = "A list of CIDR blocks that should be allowed network access to the Kubernetes public API endpoint. When null or empty, allow access from the whole world (0.0.0.0/0). Note that this only restricts network reachability to the API, and does not account for authentication to the API."
  type        = list(string)
}


# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These variables have defaults and may be overwritten
# ---------------------------------------------------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Version of Kubernetes to use. Refer to EKS docs for list of available versions (https://docs.aws.amazon.com/eks/latest/userguide/platform-versions.html)."
  type        = string
  default     = "1.22"
}

variable "allowed_availability_zones" {
  description = "A list of availability zones in the region that we can use to deploy the cluster. You can use this to avoid availability zones that may not be able to provision the resources (e.g ran out of capacity). If empty, will allow all availability zones."
  type        = list(string)
  default     = []
}

variable "unique_identifier" {
  description = "A unique identifier that can be used to index the test IAM resources"
  type        = string
  default     = ""
}

variable "use_launch_template" {
  description = "When true, use launch templates to configure node group. Must provide var.launch_template_ami_id."
  type        = bool
  default     = false
}

variable "launch_template_ami_id" {
  description = "The ID of the AMI to use when configuring the launch template for the node group. Only used if var.use_launch_template is true."
  type        = string
  default     = null
}

variable "cluster_instance_keypair_name" {
  description = "The EC2 Keypair name used to SSH into the EKS Cluster's EC2 Instances. To disable keypairs, pass in blank."
  type        = string
  default     = null
}

variable "enable_eks_addons" {
  description = "When set to true, the module configures EKS add-ons (https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html) specified with `eks_addons`"
  type        = bool
  default     = false
}

variable "eks_addons" {
  description = "Map of EKS add-ons, where key is name of the add-on and value is a map of add-on properties."
  type        = any
  default = {
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {
      resolve_conflicts = "OVERWRITE"
    }
    vpc-cni = {
      resolve_conflicts = "OVERWRITE"
    }
  }
}

# Kubectl configuration options

variable "configure_kubectl" {
  description = "Configure the kubeconfig file so that kubectl can be used to access the deployed EKS cluster."
  type        = bool
  default     = false
}

variable "kubectl_config_path" {
  description = "The path to the configuration file to use for kubectl, if var.configure_kubectl is true. Defaults to ~/.kube/config."
  type        = string

  # The underlying command will use the default path when empty
  default = ""
}

# VPC CNI Pod networking configurations for self-managed and managed node groups.

variable "vpc_cni_enable_prefix_delegation" {
  description = "When true, enable prefix delegation mode for the AWS VPC CNI component of the EKS cluster. In prefix delegation mode, each ENI will be allocated 16 IP addresses (/28) instead of 1, allowing you to pack more Pods per node. Note that by default, AWS VPC CNI will always preallocate 1 full prefix - this means that you can potentially take up 32 IP addresses from the VPC network space even if you only have 1 Pod on the node. You can tweak this behavior by configuring the var.vpc_cni_warm_ip_target input variable."
  type        = bool
  default     = false
}

variable "vpc_cni_warm_ip_target" {
  description = "The number of free IP addresses each node should maintain. When null, defaults to the aws-vpc-cni application setting (currently 16 as of version 1.9.0). In prefix delegation mode, determines whether the node will preallocate another full prefix. For example, if this is set to 5 and a node is currently has 9 Pods scheduled, then the node will NOT preallocate a new prefix block of 16 IP addresses. On the other hand, if this was set to the default value, then the node will allocate a new block when the first pod is scheduled."
  type        = number
  default     = null
}

variable "vpc_cni_minimum_ip_target" {
  description = "The minimum number of IP addresses (free and used) each node should start with. When null, defaults to the aws-vpc-cni application setting (currently 16 as of version 1.9.0). For example, if this is set to 25, every node will allocate 2 prefixes (32 IP addresses). On the other hand, if this was set to the default value, then each node will allocate only 1 prefix (16 IP addresses)."
  type        = number
  default     = null
}

# These variables are only used for testing purposes and should not be touched in normal operations, unless you know
# what you are doing.

# NOTE: Setting this to false will prevent your ability to deploy from outside the VPC, requiring VPN to use tools like
# kubectl and helm remotely. You will also be unable to configure the EKS IAM role mapping remotely through this
# terraform code.
variable "endpoint_public_access" {
  description = "Whether or not to enable public API endpoints which allow access to the Kubernetes API from outside of the VPC. Note that private access within the VPC is always enabled."
  type        = bool
  default     = true
}

variable "use_kubergrunt_to_fetch_token" {
  description = "EKS clusters use short-lived authentication tokens that can expire in the middle of an 'apply' or 'destroy'. To avoid this issue, we use an exec-based plugin to fetch an up-to-date token. If this variable is set to true, we'll use kubergrunt to fetch the token (in which case, kubergrunt must be installed and on PATH); if this variable is set to false, we'll use the aws CLI to fetch the token (in which case, aws must be installed and on PATH)."
  type        = bool
  default     = true
}
