# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DATA SOURCES
# These resources must already exist.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Use the default EKS optimized AMI available in the region.
data "aws_ami" "eks_worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.kubernetes_version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# Use cloud-init script to initialize the EKS workers
data "cloudinit_config" "cloud_init" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "eks-workers-default-cloud-init"
    content_type = "text/x-shellscript"
    content = templatefile(
      "${path.module}/user-data/user-data.sh",
      {
        user_data_text            = var.user_data_text
        eks_cluster_name          = var.eks_cluster_name
        eks_endpoint              = module.eks_cluster.eks_cluster_endpoint
        eks_certificate_authority = module.eks_cluster.eks_cluster_certificate_authority
      }
    )
  }
}

data "aws_subnet" "all_public" {
  count = module.vpc_app.num_availability_zones
  id    = element(module.vpc_app.public_subnet_ids, count.index)
}
data "aws_subnet" "all_private" {
  count = module.vpc_app.num_availability_zones
  id    = element(module.vpc_app.private_app_subnet_ids, count.index)
}

locals {
  availability_zones = (
    length(var.allowed_availability_zones) == 0
    ? data.aws_subnet.all_public.*.availability_zone
    : var.allowed_availability_zones
  )

  # Filter the list of subnet ids based on the allowed availability zones. This works by matching the availability zone
  # of each subnet in the "all" list against the list of availability zones that we are allowed to use, and then
  # returning just the corresponding ids (the first arg of matchkeys).
  usable_public_subnet_ids = matchkeys(
    data.aws_subnet.all_public.*.id,
    data.aws_subnet.all_public.*.availability_zone,
    local.availability_zones,
  )
  usable_private_subnet_ids = matchkeys(
    data.aws_subnet.all_private.*.id,
    data.aws_subnet.all_private.*.availability_zone,
    local.availability_zones,
  )

  # The caller identity ARN is not exactly the IAM Role ARN when it is an assumed role: it corresponds to an STS
  # AssumedRole ARN. Therefore, we need to massage the data to morph it into the actual IAM Role ARN when it is an
  # assumed-role.
  caller_arn_type = length(regexall("assumed-role", data.aws_caller_identity.current.arn)) > 0 ? "assumed-role" : "user"
  caller_arn_name = replace(data.aws_caller_identity.current.arn, "/.*(assumed-role|user)/([^/]+).*/", "$2")
  caller_real_arn = (
    local.caller_arn_type == "user"
    ? data.aws_caller_identity.current.arn
    : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.caller_arn_name}"
  )
}

# We only want to allow entities in this account to be able to assume the example role
data "aws_iam_policy_document" "allow_access_from_self" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.caller_real_arn]
    }
  }
}

data "aws_caller_identity" "current" {}
