package test

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"

	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/k8s"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestEKSFargateCluster(t *testing.T) {
	t.Parallel()

	workingDir := filepath.Join(".", "stages", t.Name())

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_select_region", "true")
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_verify", "true")
	//os.Setenv("SKIP_cleanup", "true")

	test_structure.RunTestStage(t, "select_region", func() {
		region := getRandomFargateRegion(t)
		test_structure.SaveString(t, workingDir, "awsRegion", region)
	})

	region := test_structure.LoadString(t, workingDir, "awsRegion")
	deployEKSAndVerify(
		t,
		"eks-fargate-cluster",
		0,
		region,
		createEKSFargateClusterTerraformOptions,
		verifyBasicEKSFargateFunctionality,
		func(t *testing.T, workingDir string) {},
	)
}

func TestEKSFargateClusterWithAddOns(t *testing.T) {
	t.Parallel()

	workingDir := filepath.Join(".", "stages", t.Name())

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("TERRATEST_REGION", "eu-west-1")
	//os.Setenv("SKIP_select_region", "true")
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_verify", "true")
	//os.Setenv("SKIP_verify_addons", "true")
	//os.Setenv("SKIP_cleanup", "true")

	test_structure.RunTestStage(t, "select_region", func() {
		region := getRandomFargateRegion(t)
		test_structure.SaveString(t, workingDir, "awsRegion", region)
	})

	region := test_structure.LoadString(t, workingDir, "awsRegion")
	deployEKSAndVerify(
		t,
		"eks-fargate-cluster",
		0,
		region,
		createEKSFargateClusterWithAddOnsTerraformOptions,
		verifyEKSFargateWithAddOnsFunctionality,
		func(t *testing.T, workingDir string) {},
	)
}

func verifyBasicEKSFargateFunctionality(t *testing.T, workingDir string) {
	kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
	kubectlOptions.Namespace = nginxNamespace
	nginxDeploymentPath, err := filepath.Abs("./kubefixtures/nginx-deployment.yml")
	require.NoError(t, err)

	test_structure.RunTestStage(t, "verify", func() {
		defer k8s.KubectlDelete(t, kubectlOptions, nginxDeploymentPath)
		k8s.KubectlApply(t, kubectlOptions, nginxDeploymentPath)
		waitForNginxDeploymentPods(t, kubectlOptions)

		// Open a tunnel to the nginx pod and verify that it is up
		tunnel := k8s.NewTunnel(kubectlOptions, k8s.ResourceTypeService, nginxServiceName, 0, 80)
		defer tunnel.Close()
		tunnel.ForwardPort(t)

		// We only check for up to 2 minutes (60 tries, 2 seconds in between each trial) because at this point, we have
		// already waited for all the pods to boot.
		http_helper.HttpGetWithRetryWithCustomValidation(
			t,
			fmt.Sprintf("http://%s", tunnel.Endpoint()),
			nil,
			60,
			2*time.Second,
			func(statusCode int, body string) bool {
				return statusCode == 200 && strings.Contains(body, "Welcome to nginx")
			},
		)
	})
}

func verifyEKSFargateWithAddOnsFunctionality(t *testing.T, workingDir string) {
	verifyBasicEKSFargateFunctionality(t, workingDir)

	test_structure.RunTestStage(t, "verify_addons", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
		eksAddOns := terraform.OutputMapOfObjects(t, terraformOptions, "eks_cluster_addons")
		for k, v := range eksAddOns {
			addonName := v.(map[string]interface{})["addon_name"]
			assert.Equal(t, k, addonName)
		}
	})
}

func waitForNginxDeploymentPods(t *testing.T, kubectlOptions *k8s.KubectlOptions) {
	// Try for up to 5 minutes (60 tries, 5 seconds in between each trial)
	const waitTimerRetries = 60
	const waitTimerSleep = 5 * time.Second

	filters := metav1.ListOptions{LabelSelector: "app=nginx"}
	k8s.WaitUntilNumPodsCreated(t, kubectlOptions, filters, 2, waitTimerRetries, waitTimerSleep)
	pods := k8s.ListPods(t, kubectlOptions, filters)
	for _, pod := range pods {
		k8s.WaitUntilPodAvailable(t, kubectlOptions, pod.Name, waitTimerRetries, waitTimerSleep)
	}
}
