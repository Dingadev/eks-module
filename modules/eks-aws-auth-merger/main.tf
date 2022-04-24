# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# AWS AUTH MERGER
# These templates deploy the aws-auth-merger controller into Kubernetes which can be used to create the `aws-auth`
# ConfigMap from multiple independent ConfigMaps in a specific Namespace.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM REQUIREMENTS FOR RUNNING THIS MODULE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  # This module is now only being tested with Terraform 1.1.x. However, to make upgrading easier, we are setting 1.0.0 as the minimum version.
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "< 4.0"
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE NAMESPACE IF REQUESTED
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # We use a local here to bind a name to the Namespace name that is tied to the kubernetes_namespace if
  # create_namespace is true, and otherwise straight pass the variable.
  namespace_name = (
    length(kubernetes_namespace.aws_auth_merger) > 0
    ? kubernetes_namespace.aws_auth_merger[0].metadata[0].name
    : var.namespace
  )
}

resource "kubernetes_namespace" "aws_auth_merger" {
  count = var.create_resources && var.create_namespace ? 1 : 0
  metadata {
    name = var.namespace
  }
}

resource "aws_eks_fargate_profile" "aws_auth_merger" {
  count                  = var.create_resources && var.create_fargate_profile ? 1 : 0
  fargate_profile_name   = var.fargate_profile.name
  cluster_name           = var.fargate_profile.eks_cluster_name
  pod_execution_role_arn = var.fargate_profile.pod_execution_role_arn
  subnet_ids             = var.fargate_profile.worker_subnet_ids

  selector {
    namespace = local.namespace_name
    labels = {
      app = "aws-auth-merger"
    }
  }

  # Fargate Profiles can take a long time to delete if there are Pods, since the nodes need to deprovision.
  timeouts {
    delete = "1h"
  }
}


# ---------------------------------------------------------------------------------------------------------------------
# CREATE aws-auth-merger DEPLOYMENT
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_deployment" "aws_auth_merger" {
  count      = var.create_resources ? 1 : 0
  depends_on = [aws_eks_fargate_profile.aws_auth_merger]

  metadata {
    name        = var.deployment_name
    namespace   = local.namespace_name
    labels      = var.deployment_labels
    annotations = var.deployment_annotations
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "aws-auth-merger"
      }
    }

    template {
      metadata {
        labels = merge(
          {
            app = "aws-auth-merger"
          },
          var.pod_labels,
        )
        annotations = var.pod_annotations
      }

      spec {
        service_account_name            = kubernetes_service_account.aws_auth_merger[0].metadata[0].name
        automount_service_account_token = true
        container {
          name  = "aws-auth-merger"
          image = "${var.aws_auth_merger_image.repo}:${var.aws_auth_merger_image.tag}"
          args = concat(
            [
              "--loglevel", var.log_level,
              "--watch-namespace", local.namespace_name,
              "--watch-label-selector", var.configmap_label_selector,
              "--refresh-interval", var.refresh_interval,
            ],
            flatten([
              for key, val in var.autocreate_labels :
              ["--autocreate-labels", "${key}=${val}"]
            ]),
          )
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE SERVICE ACCOUNT
# Create a ServiceAccount in the specified Namespace and bind the required permissions needed by the aws-auth-merger
# app.
# The permissions are:
# - get, list, watch, create ConfigMaps in the aws-auth-merger namespace
# - get, create, update in the kube-system namespace for the aws-auth ConfigMap
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_service_account" "aws_auth_merger" {
  count = var.create_resources ? 1 : 0
  metadata {
    name        = var.service_account_name
    namespace   = local.namespace_name
    labels      = var.service_account_labels
    annotations = var.service_account_annotations
  }
  automount_service_account_token = true
}

resource "kubernetes_role" "aws_auth_merger_namespace" {
  count = var.create_resources ? 1 : 0
  metadata {
    name        = var.service_account_role_name
    namespace   = local.namespace_name
    labels      = var.service_account_role_labels
    annotations = var.service_account_role_annotations
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch", "create"]
  }
}

resource "kubernetes_role" "kube_system_namespace" {
  count = var.create_resources ? 1 : 0
  metadata {
    name        = var.service_account_role_name
    namespace   = "kube-system"
    labels      = var.service_account_role_labels
    annotations = var.service_account_role_annotations
  }

  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    verbs          = ["get", "update"]
    resource_names = ["aws-auth"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["create"]
  }

}

resource "kubernetes_role_binding" "aws_auth_merger_namespace" {
  count = var.create_resources ? 1 : 0
  metadata {
    name        = var.service_account_role_binding_name
    namespace   = local.namespace_name
    labels      = var.service_account_role_binding_labels
    annotations = var.service_account_role_binding_annotations
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.aws_auth_merger_namespace[0].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.aws_auth_merger[0].metadata[0].name
    namespace = local.namespace_name
  }
}

resource "kubernetes_role_binding" "kube_system_namespace" {
  count = var.create_resources ? 1 : 0
  metadata {
    name        = var.service_account_role_binding_name
    namespace   = "kube-system"
    labels      = var.service_account_role_binding_labels
    annotations = var.service_account_role_binding_annotations
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.kube_system_namespace[0].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.aws_auth_merger[0].metadata[0].name
    namespace = local.namespace_name
  }
}
