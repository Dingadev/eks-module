package test

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/docker"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
)

func TestAWSAuthMergerOptionality(t *testing.T) {
	t.Parallel()

	modulePath := filepath.Join("..", "modules", "eks-aws-auth-merger")
	options := &terraform.Options{
		TerraformDir: modulePath,
		Vars: map[string]interface{}{
			"namespace": "does-not-matter",
			"aws_auth_merger_image": map[string]interface{}{
				"repo": "does-not-matter",
				"tag":  "does-not-matter",
			},
			"create_resources": false,
		},
		EnvVars: map[string]string{
			// This doesn't matter for this test that shouldn't deploy any resources, but is necessary for initializing
			// the providers.
			"AWS_DEFAULT_REGION": "us-west-2",
		},
		RetryableTerraformErrors: retryableTerraformErrors,
		MaxRetries:               maxTerraformRetries,
		TimeBetweenRetries:       sleepBetweenTerraformRetries,
	}

	planStruct := terraform.InitAndPlanAndShowWithStructNoLogTempPlanFile(t, options)
	assert.Equal(t, 0, len(planStruct.ResourcePlannedValuesMap))
	assert.Equal(t, 0, len(planStruct.ResourceChangesMap))
}

// This is the top level test routine for all the tests that use the eks-cluster-with-iam-role-mappings module, which
// depends on the aws auth merger. This test will create a global ECR repo and docker image for the aws-auth-merger that
// all the subtests can then use when deploying the EKS cluster.
func TestWithAWSAuthMerger(t *testing.T) {
	t.Parallel()

	// Uncomment any of the following to skip that section during the test
	// GLOBAL SETUP
	//os.Setenv("SKIP_pick_region", "true")
	//os.Setenv("SKIP_build_aws_auth_merger_image", "true")

	// TEST ROUTINE
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_verify_config_map", "true")
	//os.Setenv("SKIP_verify_cluster_access", "true")
	//os.Setenv("SKIP_verify_control_plane_logging", "true")
	//os.Setenv("SKIP_verify_cluster_service", "true")
	//os.Setenv("SKIP_verify_rollout", "true")
	//os.Setenv("SKIP_asg_drain", "true")
	//os.Setenv("SKIP_verify_asg_drain", "true")
	//os.Setenv("SKIP_verify_cluster_upgrade", "true")
	//os.Setenv("SKIP_destroy_cluster_service", "true")
	//os.Setenv("SKIP_cleanup", "true")

	// GLOBAL CLEANUP
	//os.Setenv("SKIP_cleanup_aws_auth_merger_image", "true")

	// Create a directory path that won't conflict
	workingDir := filepath.Join(".", "stages", t.Name())

	test_structure.RunTestStage(t, "pick_region", func() {
		uniqueID := strings.ToLower(random.UniqueId())
		test_structure.SaveString(t, workingDir, uniqueIDTestDataKey, uniqueID)

		region := getRandomRegion(t)
		test_structure.SaveString(t, workingDir, awsRegionTestDataKey, region)
	})

	defer test_structure.RunTestStage(t, "cleanup_aws_auth_merger_image", func() {
		region := test_structure.LoadString(t, workingDir, awsRegionTestDataKey)
		repository := test_structure.LoadString(t, workingDir, ecrRepoTestDataKey)
		deleteECRRepo(t, region, repository)
	})
	test_structure.RunTestStage(t, "build_aws_auth_merger_image", func() {
		uniqueID := test_structure.LoadString(t, workingDir, uniqueIDTestDataKey)
		region := test_structure.LoadString(t, workingDir, awsRegionTestDataKey)

		// Setup the ECR repo for the aws-auth-merger
		repository := fmt.Sprintf("gruntwork/aws-auth-merger-%s", strings.ToLower(uniqueID))
		test_structure.SaveString(t, workingDir, ecrRepoTestDataKey, repository)

		repositoryUri := createECRRepo(t, region, repository)
		test_structure.SaveString(t, workingDir, ecrRepoUriTestDataKey, repositoryUri)

		// Setup ECR login on docker
		loginCmd := shell.Command{
			Command: "bash",
			Args: []string{
				"-c",
				fmt.Sprintf(
					"aws ecr get-login-password --region %s | docker login --username AWS --password-stdin %s",
					region,
					repositoryUri,
				),
			},
		}
		shell.RunCommand(t, loginCmd)

		// Build and push the aws-auth-merger docker image
		awsAuthMergerDockerRepoTag := fmt.Sprintf("%s:v1", repositoryUri)
		buildOpts := &docker.BuildOptions{
			Tags:          []string{awsAuthMergerDockerRepoTag},
			OtherOptions:  []string{"--no-cache"},
			Architectures: []string{"linux/amd64"},
			Push:          true,
		}
		docker.Build(t, "../modules/eks-aws-auth-merger", buildOpts)
	})

	// We wrap the test functions in a subgroup so that the global clean up function waits until all the subtests are
	// finished.
	t.Run("group", func(t *testing.T) {
		for _, testCase := range awsAuthMergerTestCases {
			// We capture the range variable into the for block so that it doesn't get updated when the subtest yields
			// with the t.Parallel calls.
			testCase := testCase

			t.Run(testCase.name, func(t *testing.T) {
				t.Parallel()

				// Check for env var based test gates. These exist for certain tests that are network intensive and thus
				// need to run in a different environment.
				if testCase.envVarGate != "" && os.Getenv(testCase.envVarGate) == "" {
					t.Skipf("Skipping integration test as run flag %s is not set.", testCase.envVarGate)
				}

				// save the ECR repo URI to the innerWorkingDir so that it gets picked up in the create terraform
				// options functions
				repoURI := test_structure.LoadString(t, workingDir, ecrRepoUriTestDataKey)
				innerWorkingDir := filepath.Join(".", "stages", t.Name())
				test_structure.SaveString(t, innerWorkingDir, ecrRepoUriTestDataKey, repoURI)

				region := test_structure.LoadString(t, workingDir, awsRegionTestDataKey)
				deployEKSAndVerify(
					t,
					"eks-cluster-with-iam-role-mappings",
					testCase.expectedWorkerCount,
					region,
					testCase.createTerraformOptions,
					testCase.verifyCluster,
					testCase.cleanUpFunc,
				)
			})
		}
	})
}

var awsAuthMergerTestCases = []struct {
	name                   string
	envVarGate             string // If set, gate running tests based on this env var.
	createTerraformOptions func(*testing.T, string, string, string, string, string) *terraform.Options
	verifyCluster          func(*testing.T, string)
	cleanUpFunc            func(*testing.T, string)
	expectedWorkerCount    int
}{

	// Test that we can:
	// 1. Provision an EKS cluster using the eks-cluster module
	// 2. Configure kubectl to connect to the EKS cluster using the eks-cluster module
	// 3. Deploy aws-auth configmap using eks-k8s-role-mapping module
	// 4. Verify the nodes are registered and ready
	// 5. Verify role mappings are applied
	{
		"TestEKSClusterWithIAMRoleMapping",
		"",
		createEKSClusterWithIAMRoleMappingTerraformOptions,
		validateAuthConfigMapAndIAMRoleMapping,
		func(t *testing.T, workingDir string) {},
		3, // 2 worker nodes and 1 fargate node for the aws-auth-merger
	},

	// Test that we can:
	// 1. Provision an EKS cluster using k8s 1.21
	// 2. Update the EKS cluster to version 1.22
	// 3. Verify the component upgrade script runs to completion.
	{
		"TestEKSClusterUpgradeK8SVersion",
		"",
		createEKSClusterSelfManagedWorkersTerraformOptionsWithK121,
		verifyClusterVersionUpgrade,
		func(t *testing.T, workingDir string) {},
		3, // 2 worker nodes and 1 fargate node for the aws-auth-merger
	},

	// Regression test for making sure self managed workers can talk to CoreDNS pods deployed on Fargate.
	{
		"TestEKSMixedWorkersDNS",
		"",
		createEKSClusterWithIAMRoleMappingAndFargateTerraformOptions,
		verifyClusterMixedWorkersDNS,
		func(t *testing.T, workingDir string) {},
		5, // 2 worker nodes, 2 fargate nodes for coredns, and 1 fargate node for the aws-auth-merger
	},

	// Note: this is a mega integration test of EKS cluster modules, because of how long it takes to spin up and down EKS
	// clusters.
	// Test that we can:
	// 1. Provision an EKS cluster using the eks-cluster module
	// 2. Configure kubectl to connect to the EKS cluster using the eks-cluster module
	// 3. Deploy aws-auth configmap using eks-k8s-role-mapping module
	// 4. Verify the nodes are registered and ready
	// 5. Deploy a simple service to the EKS cluster using kubectl
	// 6. Verify the service successfully comes up and is accessible
	// 7. Update the cluster while the service is running
	// 8. Verify the cluster rotated nodes
	{
		"TestEKSClusterIntegration",
		"RUN_KUBERGRUNT_INTEGRATION_TEST",
		createEKSClusterWithIAMRoleMappingAndNoSpotWorkers,
		verifyEKSCluster,
		func(t *testing.T, workingDir string) {},
		3, // 2 worker nodes and 1 fargate node for the aws-auth-merger
	},

	// Integration test to make sure the `kubergrunt eks drain` command works as expected.
	{
		"TestEKSClusterIntegrationDrainASG",
		"RUN_KUBERGRUNT_INTEGRATION_TEST",
		createEKSClusterWithIAMRoleMappingAndAdditionalASGTerraformOptions,
		testKubergruntASGDrain,
		func(t *testing.T, workingDir string) {},
		4, // 2 worker nodes from main ASG, 1 worker node from additional, and 1 fargate node for the aws-auth-merger
	},
}
