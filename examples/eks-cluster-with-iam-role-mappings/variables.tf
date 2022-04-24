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

variable "aws_auth_merger_image" {
  description = "Location of the container image to use for the aws-auth-merger app."
  type = object({
    # Container image repository where the aws-auth-merger app container image lives
    repo = string
    # Tag of the aws-auth-merger container to deploy
    tag = string
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These variables have defaults and may be overwritten
# ---------------------------------------------------------------------------------------------------------------------

variable "aws_auth_merger_namespace" {
  description = "Namespace to deploy the aws-auth-merger into. The app will watch for ConfigMaps in this Namespace to merge into the aws-auth ConfigMap."
  type        = string
  default     = "aws-auth-merger"
}

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

variable "eks_worker_keypair_name" {
  description = "The public SSH key to be installed on the worker nodes for testing purposes."
  type        = string
  default     = null
}

variable "user_data_text" {
  description = "This is purely here for testing purposes. We modify the user_data_text variable at test time to make sure updates to the EKS cluster instances can be rolled out without downtime."
  type        = string
  default     = "Hello World"
}

variable "unique_identifier" {
  description = "A unique identifier that can be used to index the test IAM resources"
  type        = string
  default     = ""
}

variable "example_iam_role_name_prefix" {
  description = "Prefix of the name for the IAM role to create as an example. The final name is this prefix with the unique_identifier appended to it."
  type        = string
  default     = ""
}

variable "example_iam_role_kubernetes_group_name" {
  description = "Name of the group to map the example IAM role to."
  type        = string
  default     = "system:authenticated"
}

variable "schedule_control_plane_services_on_fargate" {
  description = "When true, configures control plane services to run on Fargate so that the cluster can run without worker nodes. When true, requires kubergrunt to be available on the system."
  type        = bool
  default     = false
}

variable "wait_for_component_upgrade_rollout" {
  description = "Whether or not to wait for component upgrades to roll out to the cluster."
  type        = bool
  # Disable waiting for rollout by default, since the dependency ordering of worker pools causes terraform to deploy the
  # script before the workers. As such, rollout will always fail. Note that this should be set to true after the first
  # deploy to ensure that terraform waits until rollout of the upgraded components completes before completing the
  # apply.
  default = false
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

variable "use_kubergrunt_to_fetch_token" {
  description = "EKS clusters use short-lived authentication tokens that can expire in the middle of an 'apply' or 'destroy'. To avoid this issue, we use an exec-based plugin to fetch an up-to-date token. If this variable is set to true, we'll use kubergrunt to fetch the token (in which case, kubergrunt must be installed and on PATH); if this variable is set to false, we'll use the aws CLI to fetch the token (in which case, aws must be installed and on PATH)."
  type        = bool
  default     = true
}

variable "additional_autoscaling_group_configurations" {
  description = "Configure one or more additional Auto Scaling Groups (ASGs) in addition to the default one baked into the module to manage the EC2 instances in this cluster. Note that this module already includes a default self managed worker pool. Each entry in the map represents another ASG to provision. Refer to the `autoscaling_group_configurations` variable description in `eks-cluster-workers` module for supported attributes."
  type        = any
  default     = {}
}

variable "deploy_spot_workers" {
  description = "Whether to deploy the spot workers example in this module. If this is set to false, then var.additional_autoscaling_group_configurations must be provided."
  type        = bool
  default     = true
}
