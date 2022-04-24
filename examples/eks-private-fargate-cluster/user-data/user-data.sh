#!/bin/bash
#
# This script is meant to be run in the User Data of the network bastion. This script will install kubergrunt and
# kubectl. This will also setup kubectl access using kubergrunt to access the deployed EKS cluster.

set -e

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

function install_kubectl {
  local -r k8s_version="$1"

  echo "Installing kubectl version $k8s_version"
  curl -sLo kubectl "https://dl.k8s.io/release/v$k8s_version.0/bin/linux/amd64/kubectl"
  chmod 755 kubectl
  sudo mv kubectl /usr/local/bin/
}

function install_kubergrunt {
  echo "Installing gruntwork-installer"
  curl -sL https://raw.githubusercontent.com/gruntwork-io/gruntwork-installer/master/bootstrap-gruntwork-installer.sh | bash /dev/stdin --version 'v0.0.36'

  echo "Installing kubergrunt version $kubergrunt_version"
  gruntwork-install \
    --binary-name kubergrunt \
    --repo https://github.com/gruntwork-io/kubergrunt \
    --tag "v0.8.0"
  chmod 755 /usr/local/bin/kubergrunt
}

function setup_kubeconfig {
  local -r eks_cluster_arn="$1"
  local -r kubeconfig_path='/home/ubuntu/.kube/config'

  echo "Setting up kubectl access for EKS cluster $eks_cluster_arn using kubergrunt"
  mkdir -p "$(dirname "$kubeconfig_path")"
  kubergrunt eks configure --eks-cluster-arn "$eks_cluster_arn" --kubeconfig "$kubeconfig_path"
}

install_kubectl '${kubernetes_version}'
install_kubergrunt
setup_kubeconfig '${eks_cluster_arn}'
