#!/bin/bash
#
# This script is meant to be run in the User Data of each EKS worker instance that hosts core services. It registers the
# instance with the proper EKS cluster based on data provided by Terraform. Note that this script assumes it is running
# from an AMI that is derived from the EKS optimized AMIs that AWS provides.
#
# By default, we taint the node so that only Pods with the core toleration will be scheduled.
# TODO: how to restrict it so that only the kiam server pod can access the instance metadata?

set -e

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Here we call the bootstrap script to register the EKS worker node to the control plane.
function register_eks_worker {
  local -r node_labels="$(map-ec2-tags-to-node-labels)"
  /etc/eks/bootstrap.sh \
    --apiserver-endpoint "${eks_endpoint}" \
    --b64-cluster-ca "${eks_certificate_authority}" \
    --kubelet-extra-args "--node-labels=\"$node_labels\" --register-with-taints=dedicated=core:NoSchedule" \
    "${eks_cluster_name}"
}

function run {
  register_eks_worker
}

run
