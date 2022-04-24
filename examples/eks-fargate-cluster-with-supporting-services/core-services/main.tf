# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM RUNTIME REQUIREMENTS
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      # NOTE: 2.6.0 has a regression bug that prevents usage of the exec block with data source references, so we lock
      # to a version less than that. See https://github.com/hashicorp/terraform-provider-kubernetes/issues/1464 for more
      # details.
      version = "~> 2.0, < 2.6.0"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE OUR AWS CONNECTION
# ---------------------------------------------------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE OUR HELM AND KUBERNETES CONNECTION
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

provider "kubernetes" {
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

# ---------------------------------------------------------------------------------------------------------------------
# SETUP CLOUDWATCH LOGGING FOR FARGATE CONTAINERS
# The following sets up and configures fluent-bit to export the container logs on Fargate to Cloudwatch.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name = "${var.eks_cluster_name}-container-logs"
}

module "fargate_fluent_bit" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-fargate-container-logs?ref=v0.9.6"
  source = "../../../modules/eks-fargate-container-logs"

  fargate_execution_iam_role_arns = [var.pod_execution_iam_role_arn]
  cloudwatch_configuration = {
    region            = var.aws_region
    log_group_name    = aws_cloudwatch_log_group.eks_cluster.name
    log_stream_prefix = "fargate"
  }
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
  source     = "../../../modules/eks-alb-ingress-controller"
  depends_on = [module.fargate_fluent_bit]

  eks_cluster_name = var.eks_cluster_name
  vpc_id           = var.eks_vpc_id
  aws_region       = var.aws_region

  iam_role_for_service_accounts_config = {
    openid_connect_provider_arn = var.eks_openid_connect_provider_arn
    openid_connect_provider_url = var.eks_openid_connect_provider_url
  }
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
  source     = "../../../modules/eks-k8s-external-dns"
  depends_on = [module.fargate_fluent_bit]

  aws_region       = var.aws_region
  eks_cluster_name = var.eks_cluster_name
  txt_owner_id     = var.eks_cluster_name

  iam_role_for_service_accounts_config = {
    openid_connect_provider_arn = var.eks_openid_connect_provider_arn
    openid_connect_provider_url = var.eks_openid_connect_provider_url
  }

  # Ensure records created by external-dns are culled when the underlying resources are deleted.
  route53_record_update_policy = "sync"

  route53_hosted_zone_id_filters     = var.external_dns_route53_hosted_zone_id_filters
  route53_hosted_zone_tag_filters    = var.external_dns_route53_hosted_zone_tag_filters
  route53_hosted_zone_domain_filters = var.external_dns_route53_hosted_zone_domain_filters
}

# ---------------------------------------------------------------------------------------------------------------------
# SETUP EKS CLUSTER AUTOSCALER
# The following sets up the cluster-autoscaler, which can be used to autoscale self managed and managed node workers.
# This will not do anything for a fargate only cluster, but is useful if you plan on expanding your worker pool with
# other flavors.
# ---------------------------------------------------------------------------------------------------------------------

module "k8s_cluster_autoscaler" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:gruntwork-io/terraform-aws-eks.git//modules/eks-k8s-cluster-autoscaler?ref=v0.6.0"
  source     = "../../../modules/eks-k8s-cluster-autoscaler"
  depends_on = [module.fargate_fluent_bit]

  aws_region       = var.aws_region
  eks_cluster_name = var.eks_cluster_name
  iam_role_for_service_accounts_config = {
    openid_connect_provider_arn = var.eks_openid_connect_provider_arn
    openid_connect_provider_url = var.eks_openid_connect_provider_url
  }
}
