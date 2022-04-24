package test

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	awsgo "github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/ecr"
	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	awsRegionTestDataKey = "awsRegion"
	uniqueIDTestDataKey  = "uniqueID"
)

// deployEKSAndVerify is a test helper that abstracts the common test structure of EKS example tests. This takes in the
// example folder name, a function to create terratest options for that example, a verification function that is called
// after the EKS cluster has been applied and deployed.
// More specifically, this will:
// - Copy the terraform code for the example to a working directory
// - Create new terratest terraform options
// - Apply the terraform code
// - Wait for the EKS workers to come up
// - Run verification function
// - Tear down cluster
func deployEKSAndVerify(
	t *testing.T,
	exampleName string,
	numWorkers int,
	region string,
	createTerraformOptions func(*testing.T, string, string, string, string, string) *terraform.Options,
	verifyCluster func(*testing.T, string),
	cleanUpFunc func(*testing.T, string),
) {
	// Create a directory path that won't conflict
	workingDir := filepath.Join(".", "stages", t.Name())

	test_structure.RunTestStage(t, "create_test_copy_of_examples", func() {
		testFolder := test_structure.CopyTerraformFolderToTemp(t, "..", "examples")
		test_structure.SaveString(t, workingDir, "testFolder", testFolder)
		logger.Logf(t, "path to test folder %s\n", testFolder)
		eksClusterTerraformModulePath := filepath.Join(testFolder, exampleName)
		test_structure.SaveString(t, workingDir, "eksClusterTerraformModulePath", eksClusterTerraformModulePath)
	})

	test_structure.RunTestStage(t, "create_terratest_options", func() {
		eksClusterTerraformModulePath := test_structure.LoadString(t, workingDir, "eksClusterTerraformModulePath")
		tmpKubeConfigPath := k8s.CopyHomeKubeConfigToTemp(t)
		kubectlOptions := k8s.NewKubectlOptions("", tmpKubeConfigPath, "")
		uniqueID := random.UniqueId()
		if region == "" {
			region = getRandomRegion(t)
		}
		eksClusterTerratestOptions := createTerraformOptions(
			t, workingDir, uniqueID, region, eksClusterTerraformModulePath, tmpKubeConfigPath)
		test_structure.SaveString(t, workingDir, uniqueIDTestDataKey, uniqueID)
		test_structure.SaveString(t, workingDir, awsRegionTestDataKey, region)
		test_structure.SaveTerraformOptions(t, workingDir, eksClusterTerratestOptions)
		test_structure.SaveKubectlOptions(t, workingDir, kubectlOptions)
	})

	defer test_structure.RunTestStage(t, "cleanup", func() {
		region := test_structure.LoadString(t, workingDir, awsRegionTestDataKey)
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		// We ignore output errors when destroying, since we want to destroy the resources before exiting the test
		terraformVpcCniAwareDestroy(t, eksClusterTerratestOptions, region)

		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		err := os.Remove(kubectlOptions.ConfigPath)
		require.NoError(t, err)

		cleanUpFunc(t, workingDir)
	})

	test_structure.RunTestStage(t, "terraform_apply", func() {
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		terraform.InitAndApply(t, eksClusterTerratestOptions)
	})

	if numWorkers > 0 {
		test_structure.RunTestStage(t, "wait_for_workers", func() {
			kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
			verifyEksWorkersReady(t, kubectlOptions, numWorkers)
		})
	}

	verifyCluster(t, workingDir)
}

// Verify that all the workers on the cluster reach the Ready state.
func verifyEksWorkersReady(t *testing.T, kubectlOptions *k8s.KubectlOptions, numWorkers int) {
	kubeWaitUntilNumNodes(t, kubectlOptions, numWorkers, 30, 10*time.Second)
	k8s.WaitUntilAllNodesReady(t, kubectlOptions, 30, 10*time.Second)
	readyNodes := k8s.GetReadyNodes(t, kubectlOptions)
	if !assert.Equal(t, len(readyNodes), numWorkers) {
		// If assertion failed, log all the ready nodes and pods to make it easier to debug
		logger.Logf(t, "Ready nodes for cluster:")
		for _, node := range readyNodes {
			logger.Logf(t, "\t- %s", node.ObjectMeta.Name)
		}
		logAllPods(t, kubectlOptions)
	}
}

// logAllPods will run kubectl get pods --all-namespaces to show all the running pods on the cluster
func logAllPods(t *testing.T, kubectlOptions *k8s.KubectlOptions) {
	k8s.RunKubectl(t, kubectlOptions, "get", "pods", "--all-namespaces")
}

// terraformVpcCniAwareDestroy is a special terraform destroy call that is aware of the kubernetes plugin
// amazon-vpc-cni-k8s. This plugin allocates IP addresses to the pods in the Kubernetes cluster. This plugin works by
// allocating secondary ENI devices to the underlying worker instances. Depending on timing, this plugin could interfere
// with destroying the cluster. Specifically, terraform could shutdown the instances before the VPC CNI pod had a chance
// to cull the ENI devices. These devices are managed outside of terraform, so if they linger, it could interfere with
// destroying the VPC. These should not be considered as test failures because it is simply the nature of how the plugin
// works.
// To workaround this, this function will:
// - Spawn a process that will continuously attempt to delete all detached ENI resources on the related VPC (1 minute
//   intervals)
// - Issue a terraform destroy
// Why do it in the background instead of only attempting to delete after a destroy attempt that fails? This is because
// in the failure scenario, terraform doesn't realize that there is a lingering ENI. Therefore, terraform attempts to
// delete the underlying subnets and security groups on the VPC, but this fails because there are dependent resources.
// Unfortunately, the timeout for these resources are long (15 minutes), so the first destroy retries endlessly
// attempting to delete a resource that will never succeed. This makes the tests unbearably long, so instead we delete
// as we are running the destroy so that the ENIs are culled while the destroy attempt is happening.
func terraformVpcCniAwareDestroy(t *testing.T, eksClusterTerratestOptions *terraform.Options, region string) {
	vpcId := terraform.Output(t, eksClusterTerratestOptions, "vpc_id")

	stopChecking := make(chan bool, 1)
	wg := continuouslyAttemptToDeleteDetachedNetworkInterfacesForVpc(t, region, vpcId, stopChecking, 1*time.Minute)
	defer func() {
		stopChecking <- true
		wg.Wait()
	}()

	terraformRefresh(t, eksClusterTerratestOptions)
	terraform.Destroy(t, eksClusterTerratestOptions)
}

// Per https://github.com/terraform-aws-modules/terraform-aws-eks/issues/1162#issuecomment-767700530, Terraform 0.14
// no longer refreshes state automatically before calling destroy, so we have to do it manually. This hopefully works
// around the cryptic "Unauthorized" message we sometimes get on destroy.
func terraformRefresh(t *testing.T, terratestOptions *terraform.Options) {
	terraform.RunTerraformCommand(t, terratestOptions, terraform.FormatArgs(terratestOptions, "refresh", "-input=false")...)
}

func createECRRepo(t *testing.T, region string, name string) string {
	client := newECRClient(t, region)
	resp, err := client.CreateRepository(&ecr.CreateRepositoryInput{RepositoryName: awsgo.String(name)})
	require.NoError(t, err)
	return awsgo.StringValue(resp.Repository.RepositoryUri)
}

// deleteECRRepo will force delete the ECR repo by deleting all images prior to deleting the ECR repository.
func deleteECRRepo(t *testing.T, region string, name string) {
	client := newECRClient(t, region)

	resp, err := client.ListImages(&ecr.ListImagesInput{RepositoryName: awsgo.String(name)})
	require.NoError(t, err)

	if len(resp.ImageIds) > 0 {
		_, err = client.BatchDeleteImage(&ecr.BatchDeleteImageInput{
			RepositoryName: awsgo.String(name),
			ImageIds:       resp.ImageIds,
		})
		require.NoError(t, err)
	}

	_, err = client.DeleteRepository(&ecr.DeleteRepositoryInput{RepositoryName: awsgo.String(name)})
	require.NoError(t, err)
}

func newECRClient(t *testing.T, region string) *ecr.ECR {
	sess, err := aws.NewAuthenticatedSession(region)
	require.NoError(t, err)
	return ecr.New(sess)
}
