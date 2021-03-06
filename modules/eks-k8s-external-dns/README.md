# K8S External DNS Module

This Terraform Module installs and configures [the external-dns
application](https://github.com/kubernetes-incubator/external-dns) on an EKS cluster, so that you can configure Route 53
Hosted Zones to point DNS records to [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
endpoints.

This module uses the community helm chart, with a set of best practices input.


## How does this work?

This module solves the problem of linking a known domain name to an `Ingress` endpoint managed with Kubernetes. It is
common to setup [name based virtual
hosting](https://kubernetes.io/docs/concepts/services-networking/ingress/#name-based-virtual-hosting) with `Ingress`
resources, allowing multiple domain names to route to different services on a single `Ingress` resource. For this to
work, you need to map the domain name to the `Ingress` endpoint, so that requests to that domain name end up at the
`Ingress` endpoint. Normally, you will need to manually create the DNS records yourself after the `Ingress` resource has
been created and provisioned. However, this can be cumbersome due to the asynchronous nature of Kubernetes operations.

For example, if you are using an `Ingress` controller that maps to actual physical loadbalancers in the cloud (e.g the
[ALB Ingress Controller deployed using the eks-alb-ingress-controller module](/modules/eks-alb-ingress-controller)), the
endpoint may take several minutes before it is available. You will have to wait for that time, continuously polling the
`Ingress` resource until the underlying resource is provisioned and the endpoint is available before you can configure the
DNS setting.

The `external-dns` application automates this process by watching the `Ingress` resource for the endpoint to be
provisioned, and when it is, updating the hosted zone of the mapped hostnames with record sets that map to the `Ingress`
endpoint.

This is automatically handled when:

- You set a hostname for any rule on the `Ingress` resource.
- There exists a corresponding Hosted Zone that maps to the hostname set on the `Ingress` resource.

Note that the second condition implies that the Hosted Zones must already exist. This will not automatically register
public domains, or create private hosted zones for you.


## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See the [eks-cluster-with-supporting-services example](/examples/eks-cluster-with-supporting-services) for example
  usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* This module uses [the `kubernetes` provider](https://www.terraform.io/docs/providers/kubernetes/index.html).
* This module uses [the `helm` provider](https://www.terraform.io/docs/providers/helm/index.html).


## Prerequisites

### Helm setup

This module uses [`helm` v3](https://helm.sh/docs/) to deploy the controller to the Kubernetes cluster.

### IAM permissions

The container deployed in this module requires IAM permissions to manage Route 53 Hosted Zones. See [the
eks-k8s-external-dns-iam-policy module](../eks-k8s-external-dns-iam-policy) for more information.


## How do I restrict which Hosted Zones the app should manage?

If you have certain hosted zones that are considered protected and require more control over the DNS records, you can
restrict the application to only manage the Hosted Zones that you explicitly want it to. To specify the zones that the
app should manage, use the `route53_hosted_zone_id_filters` and `route53_hosted_zone_domain_filters` input variables.
The former specifies zones by ID, while the latter specifies zones by name.

For example, if you want the app to only manage hosted zones that end with the name `k8s.local`, you can set
`route53_hosted_zone_domain_filters = ["k8s.local"]` in your input variables. This means that the app will only create
records for any hostnames on `Ingress` resources that end with the domain `k8s.local`, and ignore all others, even if
there exists corresponding Route 53 Hosted Zones.


## How do I deploy the Pods to Fargate?

To deploy the Pods to Fargate, you can use the `create_fargate_profile` variable to `true` and specify the subnet IDs
for Fargate using `vpc_worker_subnet_ids`. Note that if you are using Fargate, you must rely on the IAM Roles for
Service Accounts (IRSA) feature to grant the necessary AWS IAM permissions to the Pod. This is configured using the
`use_iam_role_for_service_accounts`, `eks_openid_connect_provider_arn`, and `eks_openid_connect_provider_url` input
variables.
