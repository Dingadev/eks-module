package test

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestEKSFargateWithSupportingServicesCluster(t *testing.T) {
	t.Parallel()

	workingDir := filepath.Join(".", "stages", t.Name())

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_select_region", "true")
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_deploy_core_services", "true")
	//os.Setenv("SKIP_deploy_nginx", "true")
	//os.Setenv("SKIP_verify_nginx", "true")
	//os.Setenv("SKIP_cleanup_nginx", "true")
	//os.Setenv("SKIP_collect_info_on_core_services", "true")
	//os.Setenv("SKIP_cleanup_core_services", "true")
	//os.Setenv("SKIP_cleanup", "true")

	test_structure.RunTestStage(t, "select_region", func() {
		region := getRandomFargateRegion(t)
		test_structure.SaveString(t, workingDir, "awsRegion", region)
	})

	region := test_structure.LoadString(t, workingDir, "awsRegion")
	deployEKSAndVerify(
		t,
		"eks-fargate-cluster-with-supporting-services/eks-cluster",
		0,
		region,
		createEKSFargateClusterTerraformOptions,
		verifyFargateServices,
		func(t *testing.T, workingDir string) {},
	)
}

func verifyFargateServices(t *testing.T, workingDir string) {
	// We don't save the terraform options for deploying core services, because all the dynamic state necessary to
	// construct it is already stored.
	deployCoreServicesTerraformOptions := constructDeployFargateCoreServicesTerraformOptionsFromCluster(t, workingDir)

	defer test_structure.RunTestStage(t, "cleanup_core_services", func() {
		deployCoreServicesTerraformOptions.Targets = []string{}
		terraform.Destroy(t, deployCoreServicesTerraformOptions)
	})

	test_structure.RunTestStage(t, "deploy_core_services", func() {
		terraform.InitAndApply(t, deployCoreServicesTerraformOptions)
	})

	verifyFargateNginxServicePubDNS(t, workingDir)
}

func constructDeployFargateCoreServicesTerraformOptionsFromCluster(t *testing.T, workingDir string) *terraform.Options {
	// Load info that can be generated based on initial step
	testFolder := test_structure.LoadString(t, workingDir, "testFolder")
	deployCoreServicesTerraformModulePath := filepath.Join(testFolder, "eks-fargate-cluster-with-supporting-services/core-services")
	awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")

	// Load necessary info for deployment from the eks-cluster output
	eksClusterTerraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	eksClusterName := terraform.Output(t, eksClusterTerraformOptions, "eks_cluster_name")
	eksVPCID := terraform.Output(t, eksClusterTerraformOptions, "vpc_id")
	eksOpenIDConnectProviderArn := terraform.Output(t, eksClusterTerraformOptions, "eks_openid_connect_provider_arn")
	eksOpenIDConnectProviderUrl := terraform.Output(t, eksClusterTerraformOptions, "eks_openid_connect_provider_url")
	fargateExecutionRoleArn := terraform.Output(t, eksClusterTerraformOptions, "eks_fargate_default_execution_role_arn")

	// Construct the terratest terraform options and return it
	return createDeployFargateCoreServicesTerraformOptions(
		t,
		awsRegion,
		deployCoreServicesTerraformModulePath,
		eksClusterName,
		eksVPCID,
		eksOpenIDConnectProviderArn,
		eksOpenIDConnectProviderUrl,
		fargateExecutionRoleArn,
	)
}

func constructDeployFargateNginxServicesTerraformOptionsFromCluster(t *testing.T, workingDir string) *terraform.Options {
	// Load info that can be generated based on initial step
	testFolder := test_structure.LoadString(t, workingDir, "testFolder")
	helmDeploymentTerraformModulePath := filepath.Join(testFolder, "eks-fargate-cluster-with-supporting-services/nginx-service")
	awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")
	uniqueID := test_structure.LoadString(t, workingDir, "uniqueID")

	// NOTE: Service Names require starting with alphabet, so we always start with the char 'a'
	appName := fmt.Sprintf("a%s-nginx-pubdns", strings.ToLower(uniqueID))

	// Load necessary info for deployment from the eks-cluster output
	eksClusterTerraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	eksClusterName := terraform.Output(t, eksClusterTerraformOptions, "eks_cluster_name")

	// Construct the terratest terraform options and return it
	return createFargateNginxServiceTerraformOptions(
		t,
		helmDeploymentTerraformModulePath,
		awsRegion,
		eksClusterName,
		appName,
	)
}

func verifyFargateNginxServicePubDNS(t *testing.T, workingDir string) {
	// We don't need to store the nginx terraform options, as all the dynamic information to generate it has already
	// been stored.
	nginxServiceTerraformOptions := constructDeployFargateNginxServicesTerraformOptionsFromCluster(t, workingDir)
	appName := nginxServiceTerraformOptions.Vars["application_name"].(string)
	awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")

	// Load necessary info for verifying cloudwatch logs
	eksClusterTerraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	eksClusterName := terraform.Output(t, eksClusterTerraformOptions, "eks_cluster_name")

	defer test_structure.RunTestStage(t, "cleanup_nginx", func() {
		terraform.Destroy(t, nginxServiceTerraformOptions)
	})

	test_structure.RunTestStage(t, "deploy_nginx", func() {
		terraform.InitAndApply(t, nginxServiceTerraformOptions)
	})

	test_structure.RunTestStage(t, "verify_nginx", func() {
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)

		ingress := getHelmDeployedIngress(t, kubectlOptions, appName)
		ingressHost := ingress.Spec.Rules[0].Host
		endpoint := fmt.Sprintf("https://%s", ingressHost)
		err := http_helper.HttpGetWithRetryWithCustomValidationE(
			t,
			endpoint,
			nil,
			WaitTimerRetries,
			WaitTimerSleep,
			func(statusCode int, body string) bool {
				return statusCode == 200 && strings.Contains(body, "Welcome to nginx")
			},
		)
		if err != nil {
			// Make sure to pull down the logs for various services before failing the test
			getDebugLogs(t, kubectlOptions)

			t.Fatalf("Timed out waiting for Ingress endpoint to be available: %s", err)
		}

		// Verify CloudWatch logging for Fargate pods
		kubectlOptions.Namespace = "kube-system"
		verifyFargateWorkerCloudWatchLogs(t, kubectlOptions, awsRegion, eksClusterName, appName)
	})
}
