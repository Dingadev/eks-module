# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CREATE AN ELASTIC CONTAINER SERVICE FOR KUBERNETES (EKS) CLUSTER
# These templates launch an EKS cluster resource that manages the EKS control plane. This includes:
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
    # Encryption config was added in 2.52.0
    aws = ">= 2.52, < 4.0"
    # tls_certificate data source was added in 2.2.0
    tls = ">= 2.2.0"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE EKS CLUSTER ENTITY
# Amazon's EKS Service requires that we create an entity called a "cluster". The cluster runs the Kubernetes control
# plane, which manages the resources on the Kubernetes cluster. We will then register EC2 Instances with that cluster
# that act as Kubernetes worker nodes to run our applications on.
# You can use the `eks-cluster-workers` module to manage the EC2 instances.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_eks_cluster" "eks" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks.arn
  version  = var.kubernetes_version
  tags     = var.custom_tags_eks_cluster

  enabled_cluster_log_types = var.enabled_cluster_log_types

  vpc_config {
    security_group_ids     = concat(compact(var.additional_security_groups), [aws_security_group.eks.id])
    subnet_ids             = var.vpc_control_plane_subnet_ids
    endpoint_public_access = var.endpoint_public_access
    public_access_cidrs    = var.endpoint_public_access_cidrs

    # Always enable private API access, since nodes still need to access the API.
    endpoint_private_access = true
  }

  dynamic "encryption_config" {
    for_each = var.secret_envelope_encryption_kms_key_arn != null ? [var.secret_envelope_encryption_kms_key_arn] : []
    content {
      provider {
        key_arn = encryption_config.value
      }
      resources = ["secrets"]
    }
  }

  # We need to wait for the IAM role to be properly configured before we start creating the cluster
  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSServicePolicy,
    aws_iam_role_policy.cluster_manage_secret_via_cmk,

    # Make sure the CloudWatch Log Group is created before creating the EKS Cluster so that EKS doesn't create a basic
    # one.
    aws_cloudwatch_log_group.control_plane_logs,
  ]

  # In some regions, it is common for EKS to take longer than 30 minutes to provision, so we override the default
  # timeouts to be 60 minutes.
  timeouts {
    create = "1h"
    delete = "1h"
  }

  # Clean up hook for residual EKS resources that may be left behind, polluting the VPC.
  # E.g., see https://github.com/terraform-providers/terraform-provider-aws/issues/11473: When the EKS cluster is deleted,
  # the EKS control plane leaves behind a security group that it manages. This is not recognized by Hashicorp as a bug, so
  # we delete the security group via a destroy provisioner.
  provisioner "local-exec" {
    when = destroy
    command = join(
      " ",
      [
        "python",
        "${path.module}/scripts/find_and_run_kubergrunt.py",
        "--",
        "eks", "cleanup-security-group",
        "--eks-cluster-arn", self.arn,
        "--security-group-id", self.vpc_config[0].cluster_security_group_id,
        "--vpc-id", self.vpc_config[0].vpc_id,
      ],
    )
  }
}

# The Kubernetes API takes a few more seconds to come up after the EKS cluster finishes provisioning in Terraform.
# This delay can be problematic when chaining calls to the Kubernetes cluster in the same Terraform plan (e.g linking
# to eks-k8s-role-mapping module as in the eks-cluster example), as the Kubernetes call will fail to connect to the
# EKS cluster. Although you could retry the plan to finish provisioning, it is a better experience to give the cluster
# a moment to let the API start and have the plan exit cleanly.
# Therefore, this module uses a local-exec provisioner here to wait for the API server to come up, relying on the
# kubergrunt eks verify command.
# If `use_kubergrunt_verification` is set to off, this will instead wait 30 seconds.
resource "null_resource" "wait_for_api" {
  triggers = {
    # The endpoint is what changes when the cluster is redeployed
    eks_cluster_endpoint = aws_eks_cluster.eks.endpoint

    # Everytime the Kubernetes version changes, we should check for endpoint access
    k8s_version = aws_eks_cluster.eks.version

    # Everytime the endpoint type changes, we should check for endpoint access
    endpoint_access = aws_eks_cluster.eks.vpc_config[0].endpoint_public_access
  }

  provisioner "local-exec" {
    command = (
      var.use_kubergrunt_verification
      ? "${local.kubergrunt_path} eks verify --eks-cluster-arn ${aws_eks_cluster.eks.arn} --wait"
      : "echo 'Sleeping for 30 seconds to wait for Kubernetes API to initialize after creation'; sleep 30"
    )
  }
}

# When upgrading the Kubernetes version of an EKS cluster, administrative services running on the EKS cluster needs to
# be updated as well. We use kubergrunt to modify the kubernetes manifests to roll out the versions of these services
# that is compatible with the current configured EKS Kubernetes versions.
resource "null_resource" "sync_core_components" {
  count = var.use_upgrade_cluster_script && !var.enable_eks_addons ? 1 : 0

  triggers = {
    # The endpoint is what changes when the cluster is redeployed
    eks_cluster_endpoint = aws_eks_cluster.eks.endpoint

    k8s_version = aws_eks_cluster.eks.version

    # We add an artificial dependency to the eks_cluster verification null_resource
    wait_for_api_action_id = null_resource.wait_for_api.id
  }

  provisioner "local-exec" {
    command = "${local.kubergrunt_path} eks sync-core-components --eks-cluster-arn ${aws_eks_cluster.eks.arn} ${var.upgrade_cluster_script_wait_for_rollout ? "--wait" : ""} ${var.upgrade_cluster_script_skip_coredns ? "--skip-coredns" : ""} ${var.upgrade_cluster_script_skip_kube_proxy ? "--skip-kube-proxy" : ""} ${var.upgrade_cluster_script_skip_vpc_cni ? "--skip-aws-vpc-cni" : ""}"
  }
}

# Apply custom configuration settings to the aws-vpc-cni if requested.
resource "null_resource" "customize_aws_vpc_cni" {
  count = var.use_vpc_cni_customize_script ? 1 : 0

  triggers = {
    # The endpoint is what changes when the cluster is redeployed
    eks_cluster_endpoint = aws_eks_cluster.eks.endpoint

    # Link to the configuration inputs so that this is done each time the configuration changes.
    enable_prefix_delegation = var.vpc_cni_enable_prefix_delegation
    warm_ip_target           = var.vpc_cni_warm_ip_target
    minimum_ip_target        = var.vpc_cni_minimum_ip_target

    # We add an artificial dependency to the eks_cluster sync-core-components step. This step will need to run everytime
    # a new version of the VPC CNI is deployed.
    sync_core_components_action_id = (
      length(null_resource.sync_core_components) > 0
      ? null_resource.sync_core_components[0].id
      : ""
    )
  }

  provisioner "local-exec" {
    command = join(
      " ",
      concat(
        [
          "python", "'${path.module}/scripts/find_and_run_kubergrunt.py'",
          "--",
          "k8s",
          "kubectl",
          "--kubectl-eks-cluster-arn",
          aws_eks_cluster.eks.arn,
          "--",
          "set", "env", "daemonset", "aws-node",
          "-n", "kube-system",
        ],
        (
          var.vpc_cni_enable_prefix_delegation
          ? ["ENABLE_PREFIX_DELEGATION=1"]
          : ["ENABLE_PREFIX_DELEGATION-"] # Kubectl syntax for deleting the env var
        ),
        (
          var.vpc_cni_warm_ip_target == null
          ? ["WARM_IP_TARGET-"] # Kubectl syntax for deleting the env var
          : ["WARM_IP_TARGET=${var.vpc_cni_warm_ip_target}"]
        ),
        (
          var.vpc_cni_minimum_ip_target == null
          ? ["MINIMUM_IP_TARGET-"] # Kubectl syntax for deleting the env var
          : ["MINIMUM_IP_TARGET=${var.vpc_cni_minimum_ip_target}"]
        ),
      )
    )
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE CLOUDWATCH LOG GROUP FOR CONTROL PLANE LOGGING
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "control_plane_logs" {
  count             = var.should_create_cloudwatch_log_group ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cloudwatch_log_group_retention_in_days
  kms_key_id        = var.cloudwatch_log_group_kms_key_id
  tags              = var.cloudwatch_log_group_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE FARGATE PROFILE FOR CONTROL PLANE SERVICES
# If the control plane services are requested to be scheduled on Fargate, we need to create Fargate profiles so that
# the cluster will automatically schedule those pods on Fargate. This is necessary to provision at this stage so that the
# administrative pods (e.g coredns) can be scheduled on Fargate.
# Note that some of the administrative services require further processing to properly schedule on Fargate.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_eks_fargate_profile" "control_plane_services" {
  count = var.schedule_control_plane_services_on_fargate ? 1 : 0
  depends_on = [
    null_resource.sync_core_components,
    null_resource.customize_aws_vpc_cni,
    null_resource.fargate_profile_dependencies,
  ]

  cluster_name           = aws_eks_cluster.eks.name
  fargate_profile_name   = "control-plane-services"
  pod_execution_role_arn = aws_iam_role.default_fargate_role[count.index].arn
  subnet_ids             = var.vpc_worker_subnet_ids

  selector {
    namespace = "kube-system"
    labels = {
      k8s-app = "kube-dns"
    }
  }

  # Fargate Profiles can take a long time to delete if there are Pods, since the nodes need to deprovision.
  timeouts {
    delete = "1h"
  }

  # Use kubectl to remove the ec2 compute-type annotation from the coredns Deployment resource.
  provisioner "local-exec" {
    command = join(
      " ",
      [
        "python",
        "'${path.module}/scripts/find_and_run_kubergrunt.py'",
        "--",
        "eks", "schedule-coredns", "fargate",
        "--eks-cluster-name", self.cluster_name,
        "--fargate-profile-arn", self.arn,
      ],
    )
  }

  # Patch core DaemonSets to avoid fargate nodes
  provisioner "local-exec" {
    command = join(
      " ",
      [
        local.kubergrunt_path,
        "k8s",
        "kubectl",
        "--kubectl-eks-cluster-arn",
        aws_eks_cluster.eks.arn,
        "--",
        "patch", "daemonset", "aws-node",
        "-n", "kube-system",
        "--type", "json",
        "--patch", "'${jsonencode(local.patch_aws_node_daemonset)}'",
      ],
    )
  }

  # On destroy, undo the fargate transition so that the fargate profile can be destroyed
  # If coredns add-on is enabled, this command would always fail on destroy, because removing the add-on destroy the
  # coredns deployment and kubergrunt never finds it. This is why we let the command fail silently with `|| true`
  provisioner "local-exec" {
    when = destroy
    command = join(
      " ",
      [
        "python",
        "'${path.module}/scripts/find_and_run_kubergrunt.py'",
        "--",
        "eks", "schedule-coredns", "ec2",
        "--eks-cluster-name", self.cluster_name,
        "--fargate-profile-arn", self.arn,
        "||", "true",
      ],
    )
  }
}

resource "aws_iam_role" "default_fargate_role" {
  count = var.create_default_fargate_iam_role ? 1 : 0
  name = (
    var.custom_fargate_iam_role_name != null
    ? var.custom_fargate_iam_role_name
    : "${var.cluster_name}-fargate-role"
  )
  assume_role_policy   = data.aws_iam_policy_document.allow_fargate_to_assume_role.json
  permissions_boundary = var.cluster_iam_role_permissions_boundary
}

resource "aws_iam_role_policy_attachment" "default_fargate_role" {
  count      = var.create_default_fargate_iam_role ? 1 : 0
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.default_fargate_role[count.index].name
}

data "aws_iam_policy_document" "allow_fargate_to_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
  }
}

# Create a dependency relation between the Fargate Profile, and user provided values. This is important because the
# control plane Fargate Profile has provisioners that require access to the Kubernetes cluster to reschedule the control
# plane pods. When destroying the cluster, Terraform could destroy the aws-auth ConfigMap prior to destroying the
# Control Plane, which will revoke access to the Kubernetes cluster. Therefore, it is important that the Fargate Profile
# depends on the ConfigMap being created.
resource "null_resource" "fargate_profile_dependencies" {
  triggers = {
    dependencies = join(",", var.fargate_profile_dependencies)
  }
}

locals {
  patch_aws_node_daemonset = [{
    op   = "replace"
    path = "/spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms"
    value = [{
      matchExpressions = [
        {
          key      = "beta.kubernetes.io/os"
          operator = "In"
          values   = ["linux"]
        },
        {
          key      = "beta.kubernetes.io/arch"
          operator = "In"
          values   = ["amd64"]
        },
        {
          key      = "eks.amazonaws.com/compute-type"
          operator = "NotIn"
          values   = ["fargate"]
        },
      ],
    }]
  }]
}


# ---------------------------------------------------------------------------------------------------------------------
# CREATE IAM ROLES AND POLICIES FOR THE CLUSTER
# IAM Roles allow us to grant the cluster instances access to AWS Resources. Here we attach a few core IAM policies that
# are necessary for the Kubernetes workers to function. We export the IAM role id so users of this module can add their
# own custom IAM policies.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "eks" {
  name                 = "${var.cluster_name}-cluster"
  assume_role_policy   = data.aws_iam_policy_document.allow_eks_to_assume_role.json
  permissions_boundary = var.cluster_iam_role_permissions_boundary

  # IAM objects take time to propagate. This leads to subtle eventual consistency bugs where the EKS cluster cannot be
  # created because the IAM role does not exist. We add a 30 second wait here to give the IAM role a chance to propagate
  # within AWS.
  provisioner "local-exec" {
    command = "echo 'Sleeping for 30 seconds to wait for IAM role to be created'; sleep 30"
  }
}

# EKS requires the following IAM policies to function.
# These policies provide EKS and Kubernetes the ability to manage resources on your behalf, such as:
# - Creating and listing tags on EC2
# - Allocating a Load Balancer
# - Using KMS keys for encryption/decryption
# See https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html for more info.

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks.name

  # IAM objects take time to propagate. This leads to subtle eventual consistency bugs where the EKS cluster cannot be
  # created because the IAM role does not exist. We add a 30 second wait here to give the IAM role a chance to propagate
  # within AWS.
  provisioner "local-exec" {
    command = "echo 'Sleeping for 30 seconds to wait for IAM role to be created'; sleep 30"
  }
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSServicePolicy" {
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks.name

  # IAM objects take time to propagate. This leads to subtle eventual consistency bugs where the EKS cluster cannot be
  # created because the IAM role does not exist. We add a 30 second wait here to give the IAM role a chance to propagate
  # within AWS.
  provisioner "local-exec" {
    command = "echo 'Sleeping for 30 seconds to wait for IAM role to be created'; sleep 30"
  }
}

resource "aws_iam_role_policy" "cluster_manage_secret_via_cmk" {
  count = var.secret_envelope_encryption_kms_key_arn != null && local.use_inline_policies ? 1 : 0
  name  = "${var.cluster_name}-allow-kms-for-secret-encryption"
  role  = aws_iam_role.eks.name
  policy = (
    var.secret_envelope_encryption_kms_key_arn != null
    ? data.aws_iam_policy_document.allow_eks_to_use_kms_cmk[0].json
    : null
  )
}

resource "aws_iam_policy" "cluster_manage_secret_via_cmk" {
  count       = var.secret_envelope_encryption_kms_key_arn != null && var.use_managed_iam_policies ? 1 : 0
  name_prefix = "${var.cluster_name}-allow-kms-for-secret-encryption"
  policy = (
    var.secret_envelope_encryption_kms_key_arn != null
    ? data.aws_iam_policy_document.allow_eks_to_use_kms_cmk[0].json
    : null
  )
}

resource "aws_iam_role_policy_attachment" "cluster_manage_secret_via_cmk" {
  count      = var.secret_envelope_encryption_kms_key_arn != null && var.use_managed_iam_policies ? 1 : 0
  role       = aws_iam_role.eks.name
  policy_arn = aws_iam_policy.cluster_manage_secret_via_cmk[0].arn
}

data "aws_iam_policy_document" "allow_eks_to_use_kms_cmk" {
  count = var.secret_envelope_encryption_kms_key_arn != null ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ListGrants",
      "kms:DescribeKey"
    ]
    resources = [var.secret_envelope_encryption_kms_key_arn]
  }
}

# Only allow EKS control plane to assume this role
data "aws_iam_policy_document" "allow_eks_to_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE EKS CLUSTER SECURITY GROUP
# Limits which ports are allowed inbound and outbound on the control plane nodes.
# We export the security group id as an output so users of this module can add their own custom rules.
# This security group also controls access to the Private VPC Endpoint that is used for accessing the Kubernetes API
# from within the VPC. Note that inbound rules from workers will be added by the `eks-cluster-workers` module.
# These are configured based on the recommendations by AWS:
# https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "eks" {
  name        = var.cluster_name
  description = "Allow Kubernetes Control Plane of ${var.cluster_name} to communicate with worker nodes"
  vpc_id      = var.vpc_id
  tags        = var.custom_tags_security_group
}

resource "aws_security_group_rule" "allow_outbound_all" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.eks.id
}

resource "aws_security_group_rule" "allow_inbound_api_cidr" {
  count             = length(var.endpoint_private_access_cidrs) > 0 ? 1 : 0
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.endpoint_private_access_cidrs
  security_group_id = aws_security_group.eks.id
}

resource "aws_security_group_rule" "allow_inbound_api_sg" {
  for_each                 = var.endpoint_private_access_security_group_ids
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.eks.id
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVISION OPENID CONNECT PROVIDER
# Enables IAM Role for Service Accounts on the cluster by provisioning an Open ID connect provider, if one is available.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "eks" {
  # We should only create this resource if it is available
  count = var.configure_openid_connect_provider ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  url             = local.maybe_issuer_url
  thumbprint_list = [local.thumbprint]
}

data "tls_certificate" "oidc_thumbprint" {
  # We should only attempt to query this if configure_openid_connect_provider is true and the thumbprint is not
  # hardcoded.
  count = (var.configure_openid_connect_provider && var.openid_connect_provider_thumbprint == null) ? 1 : 0
  url   = local.maybe_issuer_url
}

locals {
  maybe_issuer_url = length(aws_eks_cluster.eks.identity) > 0 ? aws_eks_cluster.eks.identity.0.oidc.0.issuer : null
  thumbprint = (
    var.openid_connect_provider_thumbprint != null
    ? var.openid_connect_provider_thumbprint
    : (
      length(data.tls_certificate.oidc_thumbprint) > 0
      # Must be the first certificate in the chain
      ? data.tls_certificate.oidc_thumbprint[0].certificates[0].sha1_fingerprint
      : null
    )
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE EKS ADD-ONS
# Amazon EKS add-ons provide installation and management of a curated set of add-ons for Amazon EKS clusters.
# Read more at: https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_eks_addon" "eks_addon" {
  for_each = { for k, v in var.eks_addons : k => v if var.enable_eks_addons }
  # If we're running only fargate nodes, the fargate profile must be initialized first to be able to schedule
  # the addons to nodes and avoid `DEGRADED` state.
  depends_on = [aws_eks_fargate_profile.control_plane_services]

  cluster_name = aws_eks_cluster.eks.name
  addon_name   = each.key

  addon_version            = lookup(each.value, "addon_version", null)
  resolve_conflicts        = lookup(each.value, "resolve_conflicts", null)
  service_account_role_arn = lookup(each.value, "service_account_role_arn", null)

  tags = var.custom_tags_eks_addons

  # Prevent unnecessary noise from Terraform
  lifecycle {
    ignore_changes = [
      modified_at
    ]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE KUBECTL
# Assumes kubergrunt is already installed.
# kubectl is the utility for interacting with a Kubernetes cluster. EKS requires additional setup to authenticate
# kubectl against the cluster. The following local provisioners are used to setup the operator machine to be able to use
# kubectl against the newly created EKS cluster.
# These scripts can be run manually outside of this module to setup other operator machines.
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "local_kubectl" {
  count = var.configure_kubectl ? 1 : 0

  triggers = {
    eks_cluster_endpoint              = aws_eks_cluster.eks.endpoint
    eks_cluster_certificate_authority = aws_eks_cluster.eks.certificate_authority[0].data
  }

  provisioner "local-exec" {
    # We use a single line here, because powershell doesn't like the multiline command
    command = "${local.kubergrunt_path} eks configure --eks-cluster-arn ${aws_eks_cluster.eks.arn} ${var.kubectl_config_context_name != "" ? "--kubectl-context-name ${var.kubectl_config_context_name}" : ""} ${var.kubectl_config_path != "" ? "--kubeconfig ${var.kubectl_config_path}" : ""}"
  }
}

# Raw config data for manual setup if the operator decides to turn off automatic configuration
locals {
  generated_kubeconfig = templatefile(
    "${path.module}/templates/kubectl_config.tpl",
    {
      cluster_name              = var.cluster_name
      eks_endpoint              = aws_eks_cluster.eks.endpoint
      eks_certificate_authority = aws_eks_cluster.eks.certificate_authority[0].data
    },
  )
}
