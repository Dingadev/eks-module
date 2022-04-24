# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DATA SOURCES
# These resources must already exist.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Grab the current region as a data source so the operator only needs to set it on the provider
data "aws_region" "current" {}

module "install_kubergrunt" {
  source = "git::https://github.com/gruntwork-io/terraform-aws-utilities.git//modules/executable-dependency?ref=v0.3.1"

  enabled = local.require_kubergrunt && var.auto_install_kubergrunt

  executable     = "kubergrunt"
  download_url   = var.kubergrunt_download_url
  append_os_arch = true

  # `install_dir` is hard-coded so that we have a known location for it during later operations.
  install_dir = "${path.module}/kubergrunt-installation"
}

module "require_kubergrunt" {
  source = "git::https://github.com/gruntwork-io/terraform-aws-utilities.git//modules/require-executable?ref=v0.3.1"

  # If configure_openid_connect_provider, use_kubergrunt_verification or configure_kubectl is true, then we need
  # kubergrunt installed.
  required_executables = [local.require_kubergrunt ? module.install_kubergrunt.executable_path : ""]
  error_message        = "You have enabled ${local.kubergrunt_option}, but the __EXECUTABLE_NAME__ binary is not available in your PATH. Either install the binary, automatically by setting auto_install_kubergrunt to true or manually by following the instructions at https://github.com/gruntwork-io/package-k8s/tree/master/modules/kubergrunt, or disable the option by setting ${local.kubergrunt_option_variable} to false."
}

locals {
  require_kubergrunt = var.use_kubergrunt_verification || var.configure_kubectl || var.schedule_control_plane_services_on_fargate

  # Assume kubergrunt verification or kubectl configuration even if both are false since this is only used in the data
  # source above, and is only checked when either of these settings are set to true.
  kubergrunt_option          = var.use_kubergrunt_verification ? "kubergrunt verification" : "kubectl configuration"
  kubergrunt_option_variable = var.use_kubergrunt_verification ? "use_kubergrunt_verification" : "configure_kubectl"

  kubergrunt_path = local.require_kubergrunt ? module.require_kubergrunt.executables[module.install_kubergrunt.executable_path] : ""
}
