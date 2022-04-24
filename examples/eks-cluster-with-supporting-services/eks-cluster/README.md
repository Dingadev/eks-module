# EKS Cluster

This Terraform example deploys an EKS cluster with two worker groups:

1. A `core` worker group that is dedicated for running supporting services like `kiam` that may require more lockdown.
   The nodes in this group are tainted with `NoSchedule` so that `Pods` are not scheduled there by default.
1. An `application` worker group that is dedicated for running application services.

NOTE: This example will deploy a VPC to house the cluster.


## How do you run the example?

To run this example, apply the Terraform templates:

1. Install [Terraform](https://www.terraform.io/), minimum version: `0.9.7`.
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables
   that don't have a default.
1. Run terraform init.
1. Run terraform apply.
