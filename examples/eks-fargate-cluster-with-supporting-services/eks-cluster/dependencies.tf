# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DATA SOURCES
# These resources must already exist.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

data "aws_subnet" "all" {
  count = module.vpc_app.num_availability_zones
  id    = element(module.vpc_app.private_app_subnet_ids, count.index)
}

locals {
  # Get the list of availability zones to use for the cluster and node based on the allowed list.
  # Here, we use an awkward join and split because Terraform does not support conditional ternary expressions with list
  # values. See https://github.com/hashicorp/terraform/issues/12453
  availability_zones = split(
    ",",
    length(var.allowed_availability_zones) == 0 ? join(",", data.aws_subnet.all.*.availability_zone) : join(",", var.allowed_availability_zones),
  )

  # Filter the list of subnet ids based on the allowed availability zones. This works by matching the availability zone
  # of each subnet in the "all" list against the list of availability zones that we are allowed to use, and then
  # returning just the corresponding ids (the first arg of matchkeys).
  usable_subnet_ids = matchkeys(
    data.aws_subnet.all.*.id,
    data.aws_subnet.all.*.availability_zone,
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

data "aws_caller_identity" "current" {}
