# Core Services

This Terraform example deploys core services on to an EKS cluster. Core services are system level services that provide
services that support the management of the cluster. The following services are deployed:

- ALB Ingress Controller
- external-dns


## Prerequisites

This example assumes the [`eks-cluster`](../eks-cluster) example has been deployed.

## How do you run the example?

To run this example, apply the Terraform templates:

1. Install [Terraform](https://www.terraform.io/), minimum version `1.0.0`.
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables
   that don't have a default.
1. Run terraform init.
1. Run terraform apply.
