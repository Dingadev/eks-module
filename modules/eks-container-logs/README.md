# EKS Container Logs Module

This Terraform Module installs and configures
[aws-for-fluent-bit](https://github.com/aws/aws-for-fluent-bit) on an EKS cluster, so that
each node runs [fluent-bit](https://fluentbit.io/) to collect the logs and ship to CloudWatch Logs, Kinesis Streams, or
Kinesis Firehose.

This module uses the community helm chart, with a set of best practices inputs.

**This module is for setting up log aggregation for EKS Pods on EC2 workers (self-managed or managed node groups). For
Fargate pods, take a look at the [eks-fargate-container-logs](../eks-fargate-container-logs) module.**


## How does this work?

This module solves the problem of unifying the log streams in your Kubernetes cluster to be shipped to an aggregation
service on AWS (CloudWatch Logs, Kinesis, or Firehose) so that you have a single interface to search and monitor your
logs. To achieve this, the module installs a service (`fluent-bit`) that monitors the log files on the filesystem,
parses custom log formats into a unified format, and ships the result to a centralized log aggregation service
(CloudWatch).

`fluent-bit` is installed as a Kubernetes
[`DaemonSet`](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/), which ensures that there is one
`fluent-bit` `Pod` running per node. In this way, we are able to ensure that all workers in the cluster are running the
`fluent-bit` service for shipping the logs into CloudWatch.

You can read more about `fluent-bit` in their [official home page](https://fluentbit.io/). You can also learn more about
CloudWatch logging in the [official AWS
docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/WhatIsCloudWatchLogs.html).


## What is the difference with fluentd?

[fluent-bit](https://fluentbit.io/) is an optimized version of [fluentd](https://www.fluentd.org/) that focuses on
streaming and aggregating log files.  `fluentd` has a larger ecosystem of plugins that enable various processing
capabilities on top of the logs prior to aggregating in the data store.

For most EKS deployments, it is recommended to use this `fluent-bit` module for container log aggregation. Unless you have a specific
need for a plugin only supported by `fluentd`, the superior performance and memory footprint of `fluent-bit` will
ensure resources are available on your EKS workers for your Pods.


## Log format

This module leverages native plugins for Kubernetes built into `fluent-bit` that extract additional
metadata for each Pod that is reporting. Each log is shipped to the respective outputs in the following structure:

```json
{
    "kubernetes": {
        "namespace_name": "NAMESPACE_WHERE_POD_LOCATED",
        "pod_name": "NAME_OF_POD_EMITTING_LOG",
        "pod_id": "ID_IN_KUBERNETES_OF_POD",
        "container_hash": "KUBERNETES_GENERATED_HASH_OF_CONTAINER_EMITTING_LOG",
        "container_name": "NAME_OF_CONTAINER_IN_POD_EMITTING_LOG",
        "docker_id": "ID_IN_DOCKER_OF_CONTAINER",
        "host": "NODE_NAME_OF_HOST_EMITTING_LOG",
        "labels": {
            "KEY": "VALUE",
        },
        "annotations": {
            "KEY": "VALUE"
        }
    },
    "log": "CONTENTS_OF_LOG_MESSAGE",
    "stream": "STDERR_OR_STDOUT",
    "time": "TIMESTAMP_OF_LOG"
}
```

This allows you to filter and search the logs by the respective attributes. For example, the following CloudWatch
Insights Query can be used to search for all logs from Pods in the `kube-system` Namespace:

```
fields @timestamp, @message
| filter kubernetes.namespace_name = "kube-system"
| sort @timestamp desc
| limit 20
```


## How do you use this module?

* See the [root README](/README.adoc) for instructions on using Terraform modules.
* See the [eks-cluster-with-supporting-services example](/examples/eks-cluster-with-supporting-services) for example
  usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See [outputs.tf](./outputs.tf) for all the variables that are outputed by this module.
* This module uses [the `helm` provider](https://www.terraform.io/docs/providers/helm/index.html).
