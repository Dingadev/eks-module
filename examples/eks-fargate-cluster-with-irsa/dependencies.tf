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
}
