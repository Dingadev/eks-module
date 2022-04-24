# Example EKS Instance AMI

This folder contains a [Packer template](https://www.packer.io/) we use to create the [Amazon Machine Images
(AMIs)](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html) that run on each EC2 Instance in our EKS Cluster.
Each instance is based on the [EKS-Optimized Amazon Linux AMI](https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html),
which has the [specialized bootstrap script](https://github.com/awslabs/amazon-eks-ami/blob/master/files/bootstrap.sh)
installed that can register the instance to the EKS cluster.

On top of this, we install the scripts in the [eks-scripts module](/modules/eks-scripts) that allows us to map the tags
on the EC2 instance to Kubernetes node labels.

## Build the AMI

1. Install [Packer](https://www.packer.io/).
1. Set up your [AWS credentials as environment variables](https://www.packer.io/docs/builders/amazon.html).
1. Set the `GITHUB_OAUTH_TOKEN` environment variable to a valid GitHub auth token with "repo" access. You can generate
   one here: https://github.com/settings/tokens
1. Run `packer init && packer build build.pkr.hcl` to create a new AMI in your AWS account. Note down the ID of this new AMI.
