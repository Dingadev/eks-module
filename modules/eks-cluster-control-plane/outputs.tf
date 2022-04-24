output "eks_cluster_arn" {
  description = "AWS ARN identifier of the EKS cluster resource that is created."
  value       = aws_eks_cluster.eks.arn

  # Add dependency to the null_resource so that you can chain dependencies to the module after kubectl is configured
  # (e.g eks-k8s-role-mapping). See eks-cluster example.
  depends_on = [
    null_resource.local_kubectl,
    null_resource.wait_for_api,
  ]
}

output "eks_cluster_name" {
  description = "Short hand name of the EKS cluster resource that is created."
  value       = aws_eks_cluster.eks.id

  # Add dependency to the null_resource so that you can chain dependencies to the module after kubectl is configured
  # (e.g eks-k8s-role-mapping). See eks-cluster example.
  depends_on = [
    null_resource.local_kubectl,
    null_resource.wait_for_api,
  ]
}

output "eks_cluster_endpoint" {
  description = "URL endpoint of the Kubernetes control plane provided by EKS."
  value       = aws_eks_cluster.eks.endpoint

  # Add dependency to the null_resource so that you can chain dependencies to the module after kubectl is configured
  # (e.g eks-k8s-role-mapping). See eks-cluster example.
  depends_on = [
    null_resource.local_kubectl,
    null_resource.wait_for_api,
  ]
}

output "eks_cluster_certificate_authority" {
  description = "Certificate authority of the Kubernetes control plane provided by EKS encoded in base64."
  value       = aws_eks_cluster.eks.certificate_authority[0].data
}

output "eks_control_plane_security_group_id" {
  description = "AWS ID of the security group created for the EKS Control Plane nodes."
  value       = aws_security_group.eks.id
}

output "eks_control_plane_iam_role_arn" {
  description = "AWS ARN identifier of the IAM role created for the EKS Control Plane nodes."
  value       = aws_iam_role.eks.arn
}

output "eks_control_plane_iam_role_name" {
  description = "Name of the IAM role created for the EKS Control Plane nodes."

  # Use a RegEx (https://www.terraform.io/docs/configuration/interpolation.html#replace_string_search_replace_) that
  # takes a value like "arn:aws:iam::123456789012:role/S3Access" and looks for the string after the last "/".
  value = replace(aws_iam_role.eks.arn, "/.*/+(.*)/", "$1")
}

output "eks_default_fargate_execution_role_arn" {
  description = "A basic IAM Role ARN that has the minimal permissions to pull images from ECR that can be used for most Pods as Fargate Execution Role that do not need to interact with AWS."
  value       = length(aws_iam_role.default_fargate_role) > 0 ? aws_iam_role.default_fargate_role[0].arn : null

  # Add dependency on the default fargate profile created within the module so that additional fargate profiles are not
  # created until that one is done, since you can not concurrently create multiple fargate profiles at this time.
  depends_on = [aws_eks_fargate_profile.control_plane_services]
}

output "eks_default_fargate_execution_role_arn_without_dependency" {
  description = "Same as eks_default_fargate_execution_role_arn, except it does not depend on the Fargate Profile. You can use this instead of the one with the dependency if you are using fargate_profile_dependencies to control the creation of Fargate Profiles."
  value       = length(aws_iam_role.default_fargate_role) > 0 ? aws_iam_role.default_fargate_role[0].arn : null
}

output "eks_iam_openid_connect_provider_arn" {
  description = "ARN of the OpenID Connect Provider that can be used to attach AWS IAM Roles to Kubernetes Service Accounts."
  value       = concat(aws_iam_openid_connect_provider.eks.*.arn, [""])[0]
}

output "eks_iam_openid_connect_provider_url" {
  description = "URL of the OpenID Connect Provider that can be used to attach AWS IAM Roles to Kubernetes Service Accounts."
  value       = concat(aws_iam_openid_connect_provider.eks.*.url, [""])[0]
}

output "eks_iam_openid_connect_provider_issuer_url" {
  description = "The issue URL of the OpenID Connect Provider."
  value       = local.maybe_issuer_url
}

output "eks_cluster_managed_security_group_id" {
  description = "The ID of the EKS Cluster Security Group, which is automatically attached to managed workers."
  # Use try to handle clusters that don't have the cluster security group
  value = try(
    aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id,
    null,
  )

  # Add dependency to the null_resource so that you can chain dependencies to the module after kubectl is configured
  # (e.g eks-k8s-role-mapping). See eks-cluster example.
  depends_on = [
    null_resource.local_kubectl,
    null_resource.wait_for_api,
  ]
}

output "eks_cluster_addons" {
  description = "Map of attribute maps for enabled EKS cluster addons"
  value       = aws_eks_addon.eks_addon
}


output "eks_kubeconfig_context_name" {
  description = "The name of the kubectl config context that was used to setup authentication to the EKS control plane."
  value       = var.kubectl_config_context_name == "" ? aws_eks_cluster.eks.arn : var.kubectl_config_context_name

  # Add dependency to the null_resource so that you can chain dependencies to the module after kubectl is configured
  # (e.g eks-k8s-role-mapping). See eks-cluster example.
  depends_on = [null_resource.local_kubectl]
}

output "eks_kubeconfig" {
  description = "Minimal configuration for kubectl to authenticate with the created EKS cluster."
  value       = local.generated_kubeconfig
}

output "kubergrunt_path" {
  description = "The path to the kubergrunt binary, if in use."
  value       = local.kubergrunt_path
}
