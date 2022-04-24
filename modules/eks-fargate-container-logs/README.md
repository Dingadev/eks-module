# EKS Fargate Container Logs Module

This module supports collecting logs from Fargate Pods and shipping them to CloudWatch Logs, Elasticsearch, Kinesis
Streams, or Kinesis Firehose.

This Terraform Module sets up the required Kubernetes `Namespace` and `ConfigMap` for configuring the [Fluent
Bit](https://fluentbit.io/) instance that runs on Fargate worker nodes. This allows you to instrument container log
aggregation on Fargate Pods in EKS without setting up a side car container.

**This module is for setting up log aggregation for EKS Fargate Pods. For other pods, take a look at the
[eks-container-logs](../eks-container-logs) module.**


## How does this work?

This module solves the problem of unifying the log streams from EKS Fargate Pods in your Kubernetes cluster to be
shipped to an aggregation service on AWS (CloudWatch Logs, Kinesis, or Firehose) so that you have a single interface to
search and monitor your logs. Since Fargate doesn't support `DaemonSets`, traditionally you had to rely on side car
containers to implement the log aggregation. This required writing logs to a location that was shared with the side
cars, requiring instrumentation to both the application and infrastructure.

This module leverages the built in `fluent-bit` service on Fargate worker nodes that run the EKS Pods. EKS supports
configuring `fluent-bit` on the Fargate workers to ship to arbitrary targets if it sees a special `ConfigMap` that
contains the `fluent-bit` configuration. The Fargate `fluent-bit` service expects to see the `fluent-bit` configuration
in a `ConfigMap` named `aws-logging` in the `aws-observability` Namespace. This module can be used to manage the
`Namespace` and the `ConfigMap`.


You can read more about `fluent-bit` in their [official home page](https://fluentbit.io/). You can also learn more about
Fargate Pod Logging in [the official AWS
documentation](https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html).


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
* See the [eks-fargate-cluster-with-supporting-services example](/examples/eks-fargate-cluster-with-supporting-services) for example
  usage.
* See [variables.tf](./variables.tf) for all the variables you can set on this module.
* See [outputs.tf](./outputs.tf) for all the variables that are outputed by this module.
* This module uses [the `kubernetes` provider](https://www.terraform.io/docs/providers/kubernetes/index.html).
