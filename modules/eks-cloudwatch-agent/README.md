# EKS CloudWatch Agent Module

This Terraform Module installs and configures
[Amazon CloudWatch Agent](https://github.com/aws/amazon-cloudwatch-agent/) on an EKS cluster, so that
each node runs the agent to collect more system-level metrics from Amazon EC2 instances and ship them to Amazon CloudWatch.
This extra metric data allows using [CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
for a single pane of glass for application, performance, host, control plane, data plane insights.

This module uses the [community helm chart](https://github.com/aws/eks-charts/tree/master/stable/aws-cloudwatch-metrics), 
with a set of best practices inputs.

**This module is for setting up CloudWatch Agent for EKS clusters with worker nodes (self-managed or managed node groups) that
have support for [`DaemonSets`](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/). CloudWatch Container
Insights is [not supported for EKS Fargate](https://github.com/aws/containers-roadmap/issues/920).**


## How does this work?

CloudWatch automatically collects metrics for many resources, such as CPU, memory, disk, and network. 
Container Insights also provides diagnostic information, such as container restart failures, 
to help you isolate issues and resolve them quickly. 

In Amazon EKS and Kubernetes, using Container Insights requires using a containerized version of the CloudWatch agent 
to discover all of the running containers in a cluster. It collects performance data at every layer of the performance 
stack as log events using embedded metric format. From this data, CloudWatch creates aggregated metrics at the cluster, 
node, pod, task, and service level as CloudWatch metrics. [The metrics that Container Insights collects](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-EKS.html) 
are available in CloudWatch automatic dashboards, and also viewable in the Metrics section of the CloudWatch console.

`cloudwatch-agent` is installed as a Kubernetes
[`DaemonSet`](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/), which ensures that there is one
`cloudwatch-agent` `Pod` running per node. In this way, we are able to ensure that all workers in the cluster are running the
`cloudwatch-agent` service for shipping the metric data into CloudWatch.

Note that metrics collected by CloudWatch Agent are charged as custom metrics. For more information about CloudWatch pricing, 
see [Amazon CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/).

You can read more about `cloudwatch-agent` in the [GitHub repository](https://github.com/aws/amazon-cloudwatch-agent/). 
You can also learn more about Container Insights in the [official AWS
docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html).



## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See the [eks-cluster-with-supporting-services example](/examples/eks-cluster-with-supporting-services) for example
  usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See [outputs.tf](./outputs.tf) for all the variables that are outputed by this module.
* This module uses [the `helm` provider](https://www.terraform.io/docs/providers/helm/index.html).
