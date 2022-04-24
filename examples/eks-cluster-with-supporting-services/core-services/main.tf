# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM RUNTIME REQUIREMENTS
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE OUR HELM CONNECTION
# ---------------------------------------------------------------------------------------------------------------------

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)

    # EKS clusters use short-lived authentication tokens that can expire in the middle of an 'apply' or 'destroy'. To
    # avoid this issue, we use an exec-based plugin here to fetch an up-to-date token. Note that this code requires a
    # binary—either kubergrunt or aws—to be installed and on your PATH.
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      command     = var.use_kubergrunt_to_fetch_token ? "kubergrunt" : "aws"
      args = (
        var.use_kubergrunt_to_fetch_token
        ? ["eks", "token", "--cluster-id", var.eks_cluster_name]
        : ["eks", "get-token", "--cluster-name", var.eks_cluster_name]
      )
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# SETUP CLOUDWATCH LOGGING
# The following sets up and deploys fluentd and fluent-bit to export the container logs to Cloudwatch. You only need one
# of the two for a typical deployment (not both).
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name = "${var.eks_cluster_name}-container-logs"
}

module "aws_for_fluent_bit" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-container-logs?ref=v0.9.6"
  source = "../../../modules/eks-container-logs"

  iam_role_for_service_accounts_config = var.iam_role_for_service_accounts_config
  iam_role_name_prefix                 = var.eks_cluster_name
  cloudwatch_configuration = {
    region            = var.aws_region
    log_group_name    = aws_cloudwatch_log_group.eks_cluster.name
    log_stream_prefix = null
  }
  extra_outputs = <<-EOT
    [OUTPUT]
        Name              datadog
        Match             *
        Host              http-intake.logs.datadoghq.com
        TLS               on
        compress          gzip
        apikey            abc-123
        dd_service        my-service
        dd_message_key    log
        dd_tags           env:dev,another:key

    [OUTPUT]
        Name            splunk
        Match           *
        Host            127.0.0.1
        Port            8088
        TLS             On
        splunk_token    xyz999
  EOT

  # Allow scheduling the log shipper onto the core workers
  pod_tolerations = [
    {
      "key"      = "dedicated"
      "operator" = "Equal"
      "value"    = "core"
      "effect"   = "NoSchedule"
    },
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# SETUP CLOUDWATCH AGENT
# The following sets up and deploys CloudWatch Agent to export metrics to CloudWatch. This is required
# for EKS container insights.
# ---------------------------------------------------------------------------------------------------------------------

module "cloudwatch_agent" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-cloudwatch-agent?ref=v0.9.6"
  source = "../../../modules/eks-cloudwatch-agent"

  eks_cluster_name                     = var.eks_cluster_name
  iam_role_for_service_accounts_config = var.iam_role_for_service_accounts_config
  iam_role_name_prefix                 = var.eks_cluster_name

  # Allow scheduling the agent onto the core workers
  pod_tolerations = [
    {
      "key"      = "dedicated"
      "operator" = "Equal"
      "value"    = "core"
      "effect"   = "NoSchedule"
    },
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# SETUP AWS ALB INGRESS CONTROLLER
# The following sets up and deploys the AWS ALB Ingress Controller, which will translate Ingress resources into ALBs.
# Here, we will use the core service tier to house the controller.
# ---------------------------------------------------------------------------------------------------------------------

module "alb_ingress_controller" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-alb-ingress-controller?ref=v0.9.6"
  source = "../../../modules/eks-alb-ingress-controller"

  eks_cluster_name                     = var.eks_cluster_name
  vpc_id                               = var.eks_vpc_id
  aws_region                           = var.aws_region
  iam_role_for_service_accounts_config = var.iam_role_for_service_accounts_config

  # Schedule the controller onto the core workers
  pod_tolerations = [
    {
      "key"      = "dedicated"
      "operator" = "Equal"
      "value"    = "core"
      "effect"   = "NoSchedule"
    },
  ]

  pod_node_affinity = [
    {
      key      = "ec2.amazonaws.com/type"
      operator = "In"
      values   = ["core"]
    },
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# SETUP K8S EXTERNAL DNS
# The following sets up and deploys the external-dns Kubernetes app, which will create the necessary DNS records in
# Route 53 for the host paths specified on Ingress resources.
# Here, we will use the core service tier to house the app.
# ---------------------------------------------------------------------------------------------------------------------

module "k8s_external_dns" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-k8s-external-dns?ref=v0.9.6"
  source = "../../../modules/eks-k8s-external-dns"

  aws_region                           = var.aws_region
  eks_cluster_name                     = var.eks_cluster_name
  txt_owner_id                         = var.eks_cluster_name
  iam_role_for_service_accounts_config = var.iam_role_for_service_accounts_config

  # Ensure records created by external-dns are culled when the underlying resources are deleted.
  route53_record_update_policy = "sync"

  route53_hosted_zone_id_filters     = var.external_dns_route53_hosted_zone_id_filters
  route53_hosted_zone_tag_filters    = var.external_dns_route53_hosted_zone_tag_filters
  route53_hosted_zone_domain_filters = var.external_dns_route53_hosted_zone_domain_filters

  # Schedule the controller onto the core workers
  pod_tolerations = [
    {
      "key"      = "dedicated"
      "operator" = "Equal"
      "value"    = "core"
      "effect"   = "NoSchedule"
    },
  ]

  pod_node_affinity = [
    {
      key      = "ec2.amazonaws.com/type"
      operator = "In"
      values   = ["core"]
    },
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# SETUP K8S CLUSTER AUTOSCALER
# This deploys a cluster-autoscaler to the Kubernetes cluster which will monitor pod deployments and scale up
# worker nodes if pods ever fail to deploy due to resource constraints. The cluster-autoscaler is deployed in
# the core worker nodes (kube-system) but manages the Auto Scaling Groups for the application worker nodes.
# ---------------------------------------------------------------------------------------------------------------------

module "k8s_cluster_autoscaler" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-k8s-cluster-autoscaler?ref=v0.6.0"
  source = "../../../modules/eks-k8s-cluster-autoscaler"

  aws_region                           = var.aws_region
  eks_cluster_name                     = var.eks_cluster_name
  iam_role_for_service_accounts_config = var.iam_role_for_service_accounts_config
  cluster_autoscaler_version           = var.cluster_autoscaler_version

  # For testing purposes, we adjust the scale down thresholds so that we can see it happen more quickly but in
  # production, you should tweak this to avoid thrashing. See
  # https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#i-have-a-couple-of-nodes-with-low-utilization-but-they-are-not-scaled-down-why
  # for more info.
  container_extra_args = {
    scale-down-unneeded-time   = "2m"
    scale-down-delay-after-add = "2m"
  }

  # Schedule the controller onto the core workers
  pod_tolerations = [
    {
      key      = "dedicated"
      operator = "Equal"
      value    = "core"
      effect   = "NoSchedule"
    },
  ]

  pod_node_affinity = [
    {
      key      = "ec2.amazonaws.com/type"
      operator = "In"
      values   = ["core"]
    },
  ]
}
