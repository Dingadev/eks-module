# Core Services

This Terraform example deploys core services on to an EKS cluster. Core services are system level services that provide
services that support the management of the cluster. The following services are deployed:

- FluentD for shipping Kubernetes logs (including container logs) to CloudWatch.
- CloudWatch agent for shipping metrics to CloudWatch, allowing use of CloudWatch Container Insights.
- ALB Ingress Controller for exposing services using ALBs.
- external-dns for tieing Route 53 domains to exposed services.


## Prerequisites

This example assumes the [`eks-cluster`](../eks-cluster) example has been deployed.

## How do you run the example?

To run this example, apply the Terraform templates:

1. Install [Terraform](https://www.terraform.io/), minimum version `1.0.0`.
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables
   that don't have a default.
1. Run terraform init.
1. Run terraform apply.
