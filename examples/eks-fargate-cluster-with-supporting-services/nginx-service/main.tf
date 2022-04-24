# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY A DOCKERIZED APP USING HELM
# These templates show an example of how to deploy a dockerized app using helm. This example also shows you how you can
# setup your client to use a Gruntwork Helm Chart.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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
    token                  = data.aws_eks_cluster_auth.kubernetes_token.token
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY NGINX USING k8s-service HELM CHART
# ---------------------------------------------------------------------------------------------------------------------

resource "helm_release" "nginx" {
  name       = var.application_name
  repository = "https://helmcharts.gruntwork.io"
  chart      = "k8s-service"
  version    = "v0.2.12"
  namespace  = "kube-system"

  values = [local.chart_values]

  depends_on = [
    # We want the ingress cull wait destroy provisioner to run after the nginx release is destroyed, so we link it here
    # such that terraform will destroy the release before destroying the null resource.
    null_resource.nginx_ingress_cull_wait,
  ]
}

resource "null_resource" "nginx_ingress_cull_wait" {
  # external-dns and AWS ALB Ingress controller will turn the Ingress resources from the chart into AWS resources. These
  # are properly destroyed when the Ingress resource is destroyed. However, because of the asynchronous nature of
  # Kubernetes operations, there is a delay before the respective controllers delete the AWS resources. This can cause
  # problems when you are destroying related resources in quick succession (e.g the Route 53 Hosted Zone), so we add a
  # delay here to give Kubernetes some time to cull the resources before marking the resource as deleted in Terraform.
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Sleeping for 90 seconds to allow Kubernetes time to remove associated AWS resources'; sleep 90"
  }
}

locals {
  nginx_domain  = "nginx${var.subdomain_suffix}.${local.hostname_base}"
  hostname_base = replace(data.aws_route53_zone.for_ingress.name, "/\\.$/", "")

  chart_values = templatefile(
    "${path.module}/templates/values.yaml",
    {
      # Can't use jsonencode here because it sets the values as strings, not ints
      listen_ports = "[{\"HTTP\": 80},{\"HTTPS\": 443}]"
      app_name     = var.application_name
      # We are able to pass a jsonencoded list into YAML because YAML is a superset of JSON.
      # See section 1.3 "Relation to JSON" of the YAML spec: https://yaml.org/spec/1.2/spec.html
      hosts = jsonencode([local.nginx_domain])
    },
  )
}

data "aws_route53_zone" "for_ingress" {
  name = var.route53_hosted_zone_name
  tags = var.route53_hosted_zone_tags
}
