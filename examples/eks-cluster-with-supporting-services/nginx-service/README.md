# Nginx Service

This Terraform example shows you how you can use Terraform and Helm to deploy a dockerized service on to EKS. Under the
hood this uses [the `k8s-service` Helm
Chart](https://github.com/gruntwork-io/helm-kubernetes-services/tree/master/charts/k8s-service) to package the nginx
docker container for deployment on to Kubernetes.

At the end of this, you should be able to query Kubernetes for the associated `Service`, retrieve the ELB endpoint, and
access nginx via the endpoint.

## Prerequisites

This example assumes that you have run the [`eks-cluster`](../eks-cluster) and [`core-services`](../core-services)
examples first.

## How do you run the example?

To run this example, apply the Terraform templates:

1. Install [Terraform](https://www.terraform.io/), minimum version `1.0.0`.
1. Open `variables.tf`, set the environment variables specified at the top of the file, and fill in any other variables
   that don't have a default.
1. Run terraform init.
1. Run terraform apply.
