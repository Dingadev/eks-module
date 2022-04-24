package test

import (
	"fmt"
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/gruntwork-cli/files"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Test that we can:
//
// 1. Provision an EKS cluster using the eks-cluster module
// 2. Configure kubectl to connect to the EKS cluster using the eks-cluster module
// 3. Create an IAM Role compatible with IRSA
// 4. Deploy a job that lists EKS clusters
// 5. Verify the job has enough permissions to perform the action
func TestEKSFargateClusterIRSA(t *testing.T) {
	t.Parallel()

	workingDir := filepath.Join(".", "stages", t.Name())

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_select_region", "true")
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_verify_irsa", "true")
	//os.Setenv("SKIP_cleanup", "true")

	test_structure.RunTestStage(t, "select_region", func() {
		region := getRandomFargateRegion(t)
		test_structure.SaveString(t, workingDir, "awsRegion", region)
	})

	region := test_structure.LoadString(t, workingDir, "awsRegion")
	deployEKSAndVerify(
		t,
		"eks-fargate-cluster-with-irsa",
		0,
		region,
		createEKSClusterWithIRSATerraformOptions,
		verifyIRSA,
		// There is no need for a special clean up function here
		func(t *testing.T, workingDir string) {},
	)
}

func verifyIRSA(t *testing.T, workingDir string) {
	test_structure.RunTestStage(t, "verify_irsa", func() {
		awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")

		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		kubectlOptions.Namespace = "default"

		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		roleArn := terraform.Output(t, eksClusterTerratestOptions, "example_iam_role_arn")
		eksClusterName := terraform.Output(t, eksClusterTerratestOptions, "eks_cluster_name")

		listEksClustersJobPath, err := filepath.Abs("./kubefixtures/eks-irsa-test.yml")
		require.NoError(t, err)
		listEksClustersManifestTemplate, err := files.ReadFileAsString(listEksClustersJobPath)
		require.NoError(t, err)
		listEksClustersManifest := fmt.Sprintf(listEksClustersManifestTemplate, roleArn, awsRegion)
		defer k8s.KubectlDeleteFromString(t, kubectlOptions, listEksClustersManifest)
		defer k8s.RunKubectl(t, kubectlOptions, "describe", "pods")
		k8s.KubectlApplyFromString(t, kubectlOptions, listEksClustersManifest)

		// Wait until job is done, and then get the logs to verify the permissions
		const waitTimeoutForListCmd = "300s"
		runErr := k8s.RunKubectlE(
			t,
			kubectlOptions,
			"wait",
			"--for=condition=complete",
			fmt.Sprintf("--timeout=%s", waitTimeoutForListCmd),
			"job/list-eks-clusters",
		)
		logOutput, err := k8s.RunKubectlAndGetOutputE(t, kubectlOptions, "logs", "-l", "job-name=list-eks-clusters")
		assert.NoError(t, runErr) // Defer check for runErr to here so we can see logs when we hit timeout
		assert.NoError(t, err)
		assert.Contains(t, logOutput, eksClusterName)
	})
}
