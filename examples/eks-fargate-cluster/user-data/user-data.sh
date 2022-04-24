#!/bin/bash
#
# This script is meant to be run in the User Data of each EKS worker instance. It registers the instance with the proper
# EKS cluster based on data provided by Terraform. Note that this script assumes it is running from an AMI that is
# derived from the EKS optimized AMIs that AWS provides.

set -e

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# This is purely here for testing purposes. We modify the user_data_text variable at test time to make sure updates to
# the EKS cluster instances can be rolled out without downtime.
echo "User data text: ${user_data_text}" | tee /var/log/server_text.txt

# Here we call the bootstrap script to register the EKS worker node to the control plane.
function register_eks_worker {
  /etc/eks/bootstrap.sh --apiserver-endpoint "${eks_endpoint}" --b64-cluster-ca "${eks_certificate_authority}" "${eks_cluster_name}"
}

function run {
  register_eks_worker
}

run
