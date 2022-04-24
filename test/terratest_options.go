package test

import (
	"fmt"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

const (
	maxTerraformRetries          = 3
	sleepBetweenTerraformRetries = 5 * time.Second
)

var (
	// Set up terratest to retry on known failures
	retryableTerraformErrors = map[string]string{
		// Helm related terraform calls may fail when too many tests run in parallel. While the exact cause is unknown,
		// this is presumably due to all the network contention involved. Usually a retry resolves the issue.
		".*read: connection reset by peer.*": "Failed to reach helm charts repository.",
		".*transport is closing.*":           "Failed to reach Kubernetes API.",

		// `terraform init` frequently fails in CI due to network issues accessing plugins. The reason is unknown, but
		// eventually these succeed after a few retries.
		".*unable to verify signature.*":             "Failed to retrieve plugin due to transient network error.",
		".*unable to verify checksum.*":              "Failed to retrieve plugin due to transient network error.",
		".*no provider exists with the given name.*": "Failed to retrieve plugin due to transient network error.",
		".*registry service is unreachable.*":        "Failed to retrieve plugin due to transient network error.",
		".*Error installing provider.*":              "Failed to retrieve plugin due to transient network error.",

		// Sometimes the OpenID Connect endpoint fails when trying to retrieve the thumbprint as the cluster is coming
		// up. These errors should eventually work themselves out, because it is suspected to have to do with the
		// asynchronous nature of the Kubernetes boot up process.
		".*Error retrieving root CA Thumbprint.*": "Failed to retrieve OIDC thumbprint.",

		// Sometimes terraform fails on attempting to tag resources, which is an eventual consistency error in
		// providers. See https://github.com/terraform-providers/terraform-provider-aws/issues/12427 for example.
		// Retrying is known to work in these cases.
		".*error tagging resource.*": "Failed to tag resource due to eventual consistency error.",

		// Provider bugs where the data after apply is not propagated. This is usually an eventual consistency issue, so
		// retrying should self resolve it.
		// See https://github.com/terraform-providers/terraform-provider-aws/issues/12449 for the most common one in the
		// EKS module (aws_vpc_endpoint_route_table_association).
		".*Provider produced inconsistent result after apply.*": "Provider eventual consistency error.",

		// Fargate profiles take a long time to destroy, which can cause EKS tokens to expire. This can have downstream
		// effects if we are also deploying additional resources to the Kubernetes cluster, as the token may expire
		// before the resource updates are made by terraform. These will error with the cryptic "Unauthorized" message.
		".*Unauthorized.*": "Token to access EKS cluster expired.",

		// Due to unknown reasons, the request to hit the k8s API can time out. These are recoverable via retries.
		".*dial tcp .*:443: i/o timeout.*": "Timed out reaching k8s API endpoint.",

		// Based on the full error message: "module.vpc_app_example.aws_vpc_endpoint_route_table_association.s3_private[0], provider "registry.terraform.io/hashicorp/aws" produced an unexpected new value: Root resource was present, but now absent."
		// See https://github.com/hashicorp/terraform-provider-aws/issues/12449 and https://github.com/hashicorp/terraform-provider-aws/issues/12829
		"Root resource was present, but now absent": "This seems to be an eventual consistency issue with AWS where Terraform looks for a route table association that was just created but doesn't yet see it: https://github.com/hashicorp/terraform-provider-aws/issues/12449",

		// Based on the full error message:
		// "error reading Route Table Association (rtbassoc-0debe83161f2691ec): Empty result"
		// "error reading Route Table Association (rtbassoc-0debe83161f2691ec): couldn't find resource"
		"error reading.*[Ee]mpty result":        "This seems to be an eventual consistency issue with AWS where Terraform looks for a route table association that was just created but doesn't yet see it: https://github.com/hashicorp/terraform-provider-aws/issues/12449",
		"error reading.*couldn't find resource": "This seems to be an eventual consistency issue with AWS where Terraform looks for a route table association that was just created but doesn't yet see it: https://github.com/hashicorp/terraform-provider-aws/issues/12449",

		// Based on the full error message: "error waiting for Route Table Association (rtbassoc-0c83c992303e0797f)
		// delete: unexpected state 'associated', wanted target ''"
		"error waiting for Route Table Association.*delete: unexpected state": "This seems to be an eventual consistency issue with AWS where Terraform looks for a route table association that was just created but doesn't yet see it: https://github.com/hashicorp/terraform-provider-aws/issues/12449",
		"error waiting for Route in Route Table.*couldn't find resource":      "This seems to be an eventual consistency issue with AWS where Terraform looks for a route table association that was just created but doesn't yet see it: https://github.com/hashicorp/terraform-provider-aws/issues/12449",
	}
)

func createEKSClusterSelfManagedWorkersTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	vpcName := fmt.Sprintf("eks-vpc-%s", uniqueID)
	eksClusterName := fmt.Sprintf("eks-cluster-%s", uniqueID)

	keyPair := ssh.GenerateRSAKeyPair(t, 2048)
	awsKeyPair := aws.ImportEC2KeyPair(t, region, uniqueID, keyPair)
	test_structure.SaveEc2KeyPair(t, workingDir, awsKeyPair)

	usableZones := getUsableAvailabilityZones(t, region)

	terraformVars := map[string]interface{}{
		"aws_region":                   region,
		"vpc_name":                     vpcName,
		"eks_cluster_name":             eksClusterName,
		"eks_worker_keypair_name":      awsKeyPair.Name,
		"allowed_availability_zones":   usableZones,
		"endpoint_public_access_cidrs": []string{"0.0.0.0/0"},
		"unique_identifier":            uniqueID,
		"configure_kubectl":            1,
		"kubectl_config_path":          kubeConfigPath,
	}
	terratestOptions := terraform.Options{
		TerraformDir:             templatePath,
		Vars:                     terraformVars,
		RetryableTerraformErrors: retryableTerraformErrors,
		MaxRetries:               maxTerraformRetries,
		TimeBetweenRetries:       sleepBetweenTerraformRetries,
	}
	return &terratestOptions
}

func createEKSClusterManagedWorkersTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	keyPair := aws.CreateAndImportEC2KeyPair(t, region, uniqueID)
	test_structure.SaveEc2KeyPair(t, workingDir, keyPair)

	vpcName := fmt.Sprintf("eks-vpc-%s", uniqueID)
	eksClusterName := fmt.Sprintf("eks-cluster-%s", uniqueID)
	usableZones := getUsableAvailabilityZones(t, region)[:2]

	terraformVars := map[string]interface{}{
		"aws_region":                    region,
		"vpc_name":                      vpcName,
		"eks_cluster_name":              eksClusterName,
		"allowed_availability_zones":    usableZones,
		"cluster_instance_keypair_name": keyPair.Name,
		"endpoint_public_access_cidrs":  []string{"0.0.0.0/0"},
		"unique_identifier":             uniqueID,
		"configure_kubectl":             1,
		"kubectl_config_path":           kubeConfigPath,
	}
	terratestOptions := terraform.Options{
		TerraformDir:             templatePath,
		Vars:                     terraformVars,
		RetryableTerraformErrors: retryableTerraformErrors,
		MaxRetries:               maxTerraformRetries,
		TimeBetweenRetries:       sleepBetweenTerraformRetries,
	}

	return &terratestOptions
}

func createEKSClusterManagedWorkersWithAddOnsTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	terraformOptions := createEKSClusterManagedWorkersTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	terraformOptions.Vars["enable_eks_addons"] = true
	// Enable prefix delegation, so we can later verify that the setting is there even with the addons
	terraformOptions.Vars["vpc_cni_enable_prefix_delegation"] = true
	return terraformOptions
}

func createEKSClusterManagedWorkersWithPrefixDelegationTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	terraformOptions := createEKSClusterManagedWorkersTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	terraformOptions.Vars["vpc_cni_enable_prefix_delegation"] = true
	// Set values that are easy to test:
	// - warm IP target to 2 so we can verify prefix allocation behavior.
	// - minimum IP target to 17 so we can verify the node allocates 2 prefixes at launch.
	terraformOptions.Vars["vpc_cni_warm_ip_target"] = "2"
	terraformOptions.Vars["vpc_cni_minimum_ip_target"] = "17"
	return terraformOptions
}

func createEKSClusterManagedWorkersLaunchTemplateTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	// We use a custom AMI to test the launch template functionality.
	testFolder := test_structure.LoadString(t, workingDir, "testFolder")
	amiID := buildSupportingServicesEKSClusterAMI(t, region, testFolder)
	test_structure.SaveArtifactID(t, workingDir, amiID)

	terraformOptions := createEKSClusterManagedWorkersTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	terraformOptions.Vars["use_launch_template"] = true
	terraformOptions.Vars["launch_template_ami_id"] = amiID
	return terraformOptions
}

func createEKSClusterSelfManagedWorkersTerraformOptionsWithK121(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	terratestOptions := createEKSClusterWithIAMRoleMappingTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	terratestOptions.Vars["kubernetes_version"] = "1.21"
	return terratestOptions
}

func createEKSClusterWithIAMRoleMappingTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	options := createEKSClusterSelfManagedWorkersTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	options.Vars["example_iam_role_name_prefix"] = "EKS-k8s-role-mapping-test-"
	options.Vars["example_iam_role_kubernetes_group_name"] = "eks-k8s-role-mapping-test-group"

	repoURI := test_structure.LoadString(t, workingDir, ecrRepoUriTestDataKey)
	options.Vars["aws_auth_merger_image"] = map[string]string{
		"repo": repoURI,
		"tag":  "v1",
	}
	return options
}

func createEKSClusterWithIAMRoleMappingAndNoSpotWorkers(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	options := createEKSClusterWithIAMRoleMappingTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	options.Vars["deploy_spot_workers"] = false
	options.Vars["additional_autoscaling_group_configurations"] = map[string]interface{}{
		"additional": map[string]interface{}{
			"min_size":          2,
			"max_size":          4,
			"asg_instance_type": "t3.small",
		},
	}
	return options
}

func createEKSClusterWithIAMRoleMappingAndAdditionalASGTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	options := createEKSClusterWithIAMRoleMappingTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	options.Vars["additional_autoscaling_group_configurations"] = map[string]interface{}{
		"additional": map[string]interface{}{
			"min_size":          1,
			"max_size":          2,
			"asg_instance_type": "t2.micro",
		},
	}
	return options
}

func createEKSClusterWithIAMRoleMappingAndFargateTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	options := createEKSClusterWithIAMRoleMappingTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	options.Vars["schedule_control_plane_services_on_fargate"] = true
	return options
}

func createEKSClusterWithIRSATerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	options := createEKSFargateClusterTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	options.Vars["example_iam_role_name_prefix"] = "EKS-IRSA-test-"
	options.Vars["unique_identifier"] = uniqueID
	return options
}

func createEKSClusterWithSupportingServicesTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	// eks-cluster-with-supporting-services example depends on a custom AMI containing the scripts in the eks-scripts
	// module
	testFolder := test_structure.LoadString(t, workingDir, "testFolder")
	amiID := buildSupportingServicesEKSClusterAMI(t, region, testFolder)
	test_structure.SaveArtifactID(t, workingDir, amiID)

	options := createEKSClusterSelfManagedWorkersTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	options.Vars["eks_worker_ami"] = amiID

	return options
}

func createNginxServiceTerraformOptions(
	t *testing.T,
	templatePath string,
	awsRegion string,
	eksClusterName string,
	eksVPCID string,
	appName string,
) *terraform.Options {
	terraformVars := map[string]interface{}{
		"aws_region":               awsRegion,
		"eks_cluster_name":         eksClusterName,
		"vpc_id":                   eksVPCID,
		"application_name":         appName,
		"route53_hosted_zone_tags": DefaultDomainTagForTest,
	}
	terratestOptions := terraform.Options{
		TerraformDir:             templatePath,
		Vars:                     terraformVars,
		RetryableTerraformErrors: retryableTerraformErrors,
		MaxRetries:               maxTerraformRetries,
		TimeBetweenRetries:       sleepBetweenTerraformRetries,
	}
	return &terratestOptions
}

func createFargateNginxServiceTerraformOptions(
	t *testing.T,
	templatePath string,
	awsRegion string,
	eksClusterName string,
	appName string,
) *terraform.Options {
	terraformVars := map[string]interface{}{
		"aws_region":               awsRegion,
		"eks_cluster_name":         eksClusterName,
		"application_name":         appName,
		"subdomain_suffix":         appName,
		"route53_hosted_zone_name": DefaultDomainNameForTest,
		"route53_hosted_zone_tags": DefaultDomainTagForTest,
	}
	terratestOptions := terraform.Options{
		TerraformDir:             templatePath,
		Vars:                     terraformVars,
		RetryableTerraformErrors: retryableTerraformErrors,
		MaxRetries:               maxTerraformRetries,
		TimeBetweenRetries:       sleepBetweenTerraformRetries,
	}
	return &terratestOptions
}

func createDeployCoreServicesTerraformOptions(
	t *testing.T,
	awsRegion string,
	templatePath string,
	eksClusterName string,
	eksVPCID string,
	openidConnectProviderArn string,
	openidConnectProviderUrl string,
) *terraform.Options {
	tag_filters := []map[string]string{}
	for key, value := range DefaultDomainTagForTest {
		tag_filters = append(tag_filters, map[string]string{
			"key":   key,
			"value": value,
		})
	}
	terraformVars := map[string]interface{}{
		"aws_region":       awsRegion,
		"eks_cluster_name": eksClusterName,
		"eks_vpc_id":       eksVPCID,
		"external_dns_route53_hosted_zone_tag_filters": tag_filters,
		"iam_role_for_service_accounts_config": map[string]string{
			"openid_connect_provider_arn": openidConnectProviderArn,
			"openid_connect_provider_url": openidConnectProviderUrl,
		},
	}
	terratestOptions := terraform.Options{
		TerraformDir:             templatePath,
		Vars:                     terraformVars,
		RetryableTerraformErrors: retryableTerraformErrors,
		MaxRetries:               maxTerraformRetries,
		TimeBetweenRetries:       sleepBetweenTerraformRetries,
	}
	return &terratestOptions
}

func createEKSFargateClusterTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	vpcName := fmt.Sprintf("eks-vpc-%s", uniqueID)
	eksClusterName := fmt.Sprintf("eks-cluster-%s", uniqueID)
	usableZones := getUsableAvailabilityZones(t, region)

	terraformVars := map[string]interface{}{
		"aws_region":                   region,
		"vpc_name":                     vpcName,
		"eks_cluster_name":             eksClusterName,
		"allowed_availability_zones":   usableZones,
		"endpoint_public_access_cidrs": []string{"0.0.0.0/0"},
		"configure_kubectl":            1,
		"kubectl_config_path":          kubeConfigPath,
	}
	terratestOptions := terraform.Options{
		TerraformDir:             templatePath,
		Vars:                     terraformVars,
		RetryableTerraformErrors: retryableTerraformErrors,
		MaxRetries:               maxTerraformRetries,
		TimeBetweenRetries:       sleepBetweenTerraformRetries,
	}

	return &terratestOptions
}

func createEKSFargateClusterWithAddOnsTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	terraformOptions := createEKSFargateClusterTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	terraformOptions.Vars["enable_eks_addons"] = true
	return terraformOptions
}

func createEKSFargateClusterWithBastionTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	opts := createEKSFargateClusterTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)
	delete(opts.Vars, "endpoint_public_access_cidrs")

	opts.Vars["endpoint_public_access"] = true

	keyPair := aws.CreateAndImportEC2KeyPair(t, region, uniqueID)
	test_structure.SaveEc2KeyPair(t, workingDir, keyPair)
	opts.Vars["keypair_name"] = keyPair.Name

	return opts
}

func createDeployFargateCoreServicesTerraformOptions(
	t *testing.T,
	awsRegion string,
	templatePath string,
	eksClusterName string,
	eksVPCID string,
	eksOpenIDConnectProviderArn string,
	eksOpenIDConnectProviderUrl string,
	fargateExecutionRoleArn string,
) *terraform.Options {
	tag_filters := []map[string]string{}
	for key, value := range DefaultDomainTagForTest {
		tag_filters = append(tag_filters, map[string]string{
			"key":   key,
			"value": value,
		})
	}
	terraformVars := map[string]interface{}{
		"aws_region":                                   awsRegion,
		"eks_cluster_name":                             eksClusterName,
		"eks_vpc_id":                                   eksVPCID,
		"eks_openid_connect_provider_arn":              eksOpenIDConnectProviderArn,
		"eks_openid_connect_provider_url":              eksOpenIDConnectProviderUrl,
		"pod_execution_iam_role_arn":                   fargateExecutionRoleArn,
		"external_dns_route53_hosted_zone_tag_filters": tag_filters,
	}
	terratestOptions := terraform.Options{
		TerraformDir:             templatePath,
		Vars:                     terraformVars,
		RetryableTerraformErrors: retryableTerraformErrors,
		MaxRetries:               maxTerraformRetries,
		TimeBetweenRetries:       sleepBetweenTerraformRetries,
	}
	return &terratestOptions
}
