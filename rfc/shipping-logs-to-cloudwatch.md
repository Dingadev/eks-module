# Shipping Logs to Cloudwatch

This document captures all the different ways considered for shipping container logs to CloudWatch.

## Background

By default EKS clusters do not ship container logs (or any Kubernetes logs for that matter) to CloudWatch for log
aggregation. Using CloudWatch for log aggregation allows you to centralize all your logs in CloudWatch so that you can
search and view the logs in the [CloudWatch Logs Dashboard](https://console.aws.amazon.com/cloudwatch/home#logs:) in the
AWS console. To ensure an integrated experience, we like to provide first class support for CloudWatch Logs for EKS
clusters deployed using this module.

## Methods for shipping Kubernetes logs to CloudWatch

In the default configuration, all the container logs and Kubernetes process (e.g kubelet, kube-apiserver, etc) logs are
available on disk in the master and worker nodes. However, since we don't have access to the master nodes in EKS, this
document will focus on the worker nodes which we have more control over. In general, the goal of log aggregation
will be to stream the logs from disk to the target (which in this case will be CloudWatch).

There are two ways to achieve this:

- Install an agent (e.g the official [CloudWatch
  Agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/QuickStartEC2Instance.html)) on the host EC2 machine
  that watches the logs on disk and ships them to CloudWatch.
- Deploy a [Kubernetes `DaemonSet`](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) that will
  mount the host volume for logs into the container and do the watching and shipping.

Both approaches have pros and cons:

### Installing an agent

The CloudWatch Agent on EC2 is the most basic approach to using CloudWatch for log aggregation and is the officially
supported solution by AWS. However, the agent only supports directly forwarding the log stream to CloudWatch. This means
that if the logs are entered in a raw format that requires processing (which is often the case with Kubernetes logs),
the agent will not support it. To implement such processing, you will need to install a more powerful tool like
[`logstash`](https://www.elastic.co/products/logstash) or [`fluentd`](https://www.fluentd.org/), which supports
configuring log preprocessors.

Additionally, you have to resort to traditional mechanisms to upgrade and maintain the agent, rather than relying on
Kubernetes. In most cases, the safest bet will be to replace the whole instance to upgrade the agent, which may be
disruptive to your cluster.

In summary:

**Pros**:
- The agent is a simple daemon that runs on your EC2 instance, taking up minimal resources.
- The agent supports unified metrics gathering, for both logs and instance system metrics.
- We already have [battletested Gruntwork modules that support
  it.](https://github.com/gruntwork-io/terraform-aws-monitoring/tree/master/modules/logs)

**Cons**:
- The agent does not support any form of log preprocessing: have to install a more powerful log aggregation utility.
- Upgrades to the agent will most likely require instance replacement for the cleanest approach.

### Using a Kubernetes DaemonSet

Kubernetes [officially recommends running a log agent in the cluster as a
DaemonSet](https://kubernetes.io/docs/concepts/cluster-administration/logging/#cluster-level-logging-architectures).
This provides the benefit of being able to manage and configure the log agent using Kubernetes native features, such as
[`ConfigMaps`](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) and [rolling
deployments](https://kubernetes.io/docs/tasks/manage-daemon/update-daemon-set/). This approach also has the advantage of
having more controlled IAM management, when combined with [IAM roles for service accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html).

However, this will take up a slot in the Pod space, which means that it will eat an [ENI](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_ElasticNetworkInterfaces.html) in the default EKS
configuration, which is [a limited resource in the cluster](https://github.com/aws/amazon-vpc-cni-k8s#eni-allocation).
Additionally, this approach necessitates configuring and using some of the more heavy weight options for log shipping.
That said, there is first class support for both logstash and fluentd in the Kubernetes ecosystem.

In summary:

**Pros**:
- You can use Kubernetes to manage the agent, leveraging features such as rolling deployments to upgrade the agent in an
  immutable fashion.
- Supports more isolation at the process level for things like IAM roles.
- Provides flexibility: it is very easy to swap out agents (e.g switching from logstash to fluentd) on a live cluster.

**Cons**:
- Takes up Pod space, which includes IP addresses on the ENI (a scarce resource).
- Requires setting up `fluentd` or `logstash`. (NOTE: both have first class support)
    - Setting up logstash: https://www.elastic.co/blog/shipping-kubernetes-logs-to-elasticsearch-with-filebeat
    - Setting up fluentd: https://github.com/fluent/fluentd-kubernetes-daemonset


## Gruntwork Support

Initially we will support the easiest implementation, which is to use `fluentd-cloudwatch` as a `DaemonSet` in the
Kubernetes cluster. See [the eks-cloudwatch-container-logs module](/modules/eks-cloudwatch-container-logs) for more
info.

However, we would like to slowly expand out the implementation, including:

- Running the cloudwatch agent as a `DaemonSet`.
- Running file-beat as a `DaemonSet`.
- Other log aggregation targets (e.g ELK).
