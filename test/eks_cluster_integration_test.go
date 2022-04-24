package test

import (
	"fmt"
	"net/url"
	"path/filepath"
	"testing"
	"time"

	awsgo "github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/cloudwatchlogs"
	"github.com/gruntwork-io/terratest/modules/aws"
	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func verifyEKSCluster(t *testing.T, workingDir string) {
	test_structure.RunTestStage(t, "verify_control_plane_logging", func() {
		awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)

		eksClusterName := terraform.Output(t, eksClusterTerratestOptions, "eks_cluster_name")
		logGroupName := fmt.Sprintf("/aws/eks/%s/cluster", eksClusterName)

		// First validate there are log streams of the name `kube-apiserver-RANDOM_HASH`. Then verify it has entries.
		cloudwatchSvc := aws.NewCloudWatchLogsClient(t, awsRegion)
		result, err := cloudwatchSvc.DescribeLogStreams(&cloudwatchlogs.DescribeLogStreamsInput{
			LogGroupName:        awsgo.String(logGroupName),
			LogStreamNamePrefix: awsgo.String("kube-apiserver-"),
		})
		require.NoError(t, err)
		logStreams := result.LogStreams
		require.True(t, len(logStreams) > 0)
		entries := aws.GetCloudWatchLogEntries(t, awsRegion, awsgo.StringValue(logStreams[0].LogStreamName), logGroupName)
		assert.True(t, len(entries) > 0)
	})

	defer test_structure.RunTestStage(t, "destroy_cluster_service", func() {
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		kubectlOptions.Namespace = nginxNamespace
		destroyServiceDeployment(t, kubectlOptions)

		// Load necessary state to determine which network interfaces need to be waited for deletion, and wait for
		// deletion.
		// These network interfaces are created outside of terraform and managed by Kubernetes, so we need to wait for
		// Kubernetes to complete its garbage collection before continuing on to terraform destroy. Otherwise, the
		// destroy will fail due to dependencies between the VPC and these resources.
		var networkInterfaceIds []string
		path := test_structure.FormatTestDataPath(workingDir, "serviceNetworkInterfaceIds.json")
		test_structure.LoadTestData(t, path, &networkInterfaceIds)
		region := test_structure.LoadString(t, workingDir, "awsRegion")
		err := waitForNetworkInterfacesToBeDeletedE(t, region, networkInterfaceIds)
		// We purposefully do not fail the test if the interfaces are not deleted, because there is a weird eventual
		// consistency issue where Kubernetes sometimes does not cull all the interfaces.
		// Note that if there is an actual failure here, the test will fail later when it tries to destroy.
		if err != nil {
			logger.Logf(t, "WARNING: Not all interfaces were culled. Error: %s", err)
		}
	})

	test_structure.RunTestStage(t, "verify_cluster_service", func() {
		region := test_structure.LoadString(t, workingDir, "awsRegion")
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)

		// NOTE: Store a reference of all the existing ENIs. This is used to determine all the new ENIs created by the service
		// deployment. This is necessary because Kubernetes will allocate ENIs as needed for both the pods and the load
		// balancers. This isn't really a problem, except they are not managed by Terraform and they take some time to
		// be deleted. Those network interfaces MUST be deleted BEFORE the destroy call; otherwise, the destroy call
		// will fail.
		vpcId := terraform.Output(t, eksClusterTerratestOptions, "vpc_id")
		beforeServiceNetworkInterfaces := getENIsForVpc(t, region, vpcId)

		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		kubectlOptions.Namespace = nginxNamespace
		deployLBServiceDeployment(t, kubectlOptions)
		verifyLBServiceDeployment(t, kubectlOptions, nginxServiceName)
		verifyLBServiceDeployment(t, kubectlOptions, nginxServiceName+"-nlb")

		// Now we store the new network interfaces created since the service was deployed, so we can use it later to
		// verify they are all deleted
		afterServiceNetworkInterfaces := newENIsForVpc(t, region, vpcId, beforeServiceNetworkInterfaces)
		networkInterfaceIds := getENIIds(afterServiceNetworkInterfaces)
		path := test_structure.FormatTestDataPath(workingDir, "serviceNetworkInterfaceIds.json")
		test_structure.SaveTestData(t, path, networkInterfaceIds)
	})

	test_structure.RunTestStage(t, "verify_rollout", func() {
		region := test_structure.LoadString(t, workingDir, "awsRegion")
		uniqueID := test_structure.LoadString(t, workingDir, "uniqueID")
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		kubectlOptions.Namespace = nginxNamespace
		verifyEksRolloutCommand(t, kubectlOptions, eksClusterTerratestOptions, region, uniqueID)
	})
}

// Return the service endpoint that will reach nginx, on the path where we expect the user data text to be served from.
func getNginxServiceEndpoint(t *testing.T, options *k8s.KubectlOptions) string {
	service := k8s.GetService(t, options, nginxServiceName)
	endpoint := k8s.GetServiceEndpoint(t, options, service, 80)
	serviceUrl, err := url.Parse(fmt.Sprintf("http://%s", endpoint))
	require.NoError(t, err)
	serviceUrl.Path = "/server_text.txt"
	return serviceUrl.String()
}

// Verify that we can deploy services in the cluster
func deployLBServiceDeployment(t *testing.T, options *k8s.KubectlOptions) {
	nginxDeploymentPath, err := filepath.Abs("./kubefixtures/robust-nginx-deployment.yml")
	require.NoError(t, err)
	k8s.KubectlApply(t, options, nginxDeploymentPath)
}

// Verify that we can access services in the cluster
func verifyLBServiceDeployment(t *testing.T, options *k8s.KubectlOptions, serviceName string) {
	k8s.WaitUntilServiceAvailable(t, options, serviceName, 40, 15*time.Second)
	endpoint := getNginxServiceEndpoint(t, options)

	// This will try for up to 5 minutes: 60 retries, 5 seconds inbetween
	// It takes some time for instances to be registered with the ELB, which services traffic to the pods.
	// Note that we wait for 5 consecutive successes before continuing, as empirical testing suggests that DNS
	// propagation delays may cause failures immediately after the first success.
	successCount := 0
	waitForSuccess := 5
	retry.DoWithRetry(
		t,
		"wait for nginx service",
		60,
		5*time.Second,
		func() (string, error) {
			err := http_helper.HttpGetWithValidationE(t, endpoint, nil, 200, "User data text: Hello World")
			if err != nil {
				// reset counter
				logger.Logf(t, "HTTP GET call to %s failed with error %s. Resetting counter (%d => 0)", endpoint, err, successCount)
				successCount = 0
				return "", err
			}
			successCount += 1
			logger.Logf(t, "HTTP GET call to %s succeeded. (%d / %d)", endpoint, successCount, waitForSuccess)
			if successCount >= waitForSuccess {
				logger.Logf(t, "Reached desired number of consecutive successes for HTTP GET call to %s", endpoint)
				return "", nil
			}
			return "", fmt.Errorf("Have not reached required number of consecutive successes (%d / %d)", successCount, waitForSuccess)
		},
	)
}

// Verify the rollout command in kubergrunt. Specifically:
// - Deploy a new version by updating user data
// - Verify rollout is necessary by checking endpoint for updated server text
// - Rollout the new user-data
// - Verify updated server text appears
// NOTE: This used to test the service continuously for downtime, but due to issues with the ALB management, it turns
// out that some degree of downtime is to be expected during the rollout. Since we can't account for that downtime, we
// have removed the continuous checks since v0.15.5, until https://github.com/gruntwork-io/kubergrunt/issues/85 is
// addressed.
func verifyEksRolloutCommand(t *testing.T, kubectlOptions *k8s.KubectlOptions, eksClusterTerratestOptions *terraform.Options, region string, serverText string) {
	eksClusterTerratestOptions.Vars["user_data_text"] = serverText
	terraform.Apply(t, eksClusterTerratestOptions)

	doEksRollout(t, kubectlOptions, eksClusterTerratestOptions, region)

	// Try for up to 2.5 minutes (30 tries, 5 seconds inbetween). This is a shorter wait, because the rollout will
	// already wait for instances to be registered.
	endpoint := getNginxServiceEndpoint(t, kubectlOptions)
	http_helper.HttpGetWithRetry(
		t,
		endpoint,
		nil,
		200,
		fmt.Sprintf("User data text: %s", serverText),
		30,
		5*time.Second,
	)
}

// Destroy the nginx deployment
func destroyServiceDeployment(t *testing.T, kubectlOptions *k8s.KubectlOptions) {
	nginxDeploymentPath, err := filepath.Abs("./kubefixtures/robust-nginx-deployment.yml")
	require.NoError(t, err)
	k8s.KubectlDelete(t, kubectlOptions, nginxDeploymentPath)
}

// Call the kubergrunt functionality that implements the cluster rollout
func doEksRollout(t *testing.T, kubectlOptions *k8s.KubectlOptions, eksClusterTerratestOptions *terraform.Options, region string) {
	asgNames := terraform.OutputList(t, eksClusterTerratestOptions, "eks_worker_asg_names")

	for _, asgName := range asgNames {
		command := shell.Command{
			Command: "kubergrunt",
			Args: []string{
				"eks",
				"deploy",
				"--region", region,
				"--asg-name", asgName,
				"--kubeconfig", kubectlOptions.ConfigPath,
				"--kubectl-context-name", kubectlOptions.ContextName,
				"--delete-local-data",
			},
		}
		shell.RunCommand(t, command)
	}
}
