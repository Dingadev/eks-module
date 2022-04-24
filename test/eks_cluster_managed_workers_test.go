package test

import (
	"fmt"
	"testing"

	v1 "k8s.io/api/core/v1"

	awsgo "github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/helm"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestEKSClusterManagedWorkers(t *testing.T) {
	t.Parallel()

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_cleanup", "true")

	deployEKSAndVerify(
		t,
		"eks-cluster-managed-workers",
		4,
		"",
		createEKSClusterManagedWorkersTerraformOptions,
		func(t *testing.T, workingDir string) {},
		func(t *testing.T, workingDir string) {},
	)
}

func TestEKSClusterManagedWorkersWithAddOns(t *testing.T) {
	t.Parallel()

	//os.Setenv("TERRATEST_REGION", "eu-west-1")
	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_verify_addons", "true")
	//os.Setenv("SKIP_cleanup", "true")

	deployEKSAndVerify(
		t,
		"eks-cluster-managed-workers",
		4,
		"",
		createEKSClusterManagedWorkersWithAddOnsTerraformOptions,
		verifyEKSClusterManagedWorkersAddOns,
		func(t *testing.T, workingDir string) {},
	)
}

func TestEKSClusterManagedWorkersWithPrefixDelegation(t *testing.T) {
	t.Parallel()

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_verify_network", "true")
	//os.Setenv("SKIP_cleanup", "true")

	deployEKSAndVerify(
		t,
		"eks-cluster-managed-workers",
		4,
		"",
		createEKSClusterManagedWorkersWithPrefixDelegationTerraformOptions,
		verifyEKSClusterManagedWorkersPrefixDelegationNetwork,
		func(t *testing.T, workingDir string) {
			keyPair := test_structure.LoadEc2KeyPair(t, workingDir)
			aws.DeleteEC2KeyPair(t, keyPair)
		},
	)
}

func TestEKSClusterManagedWorkersWithLaunchTemplate(t *testing.T) {
	t.Parallel()

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_verify_worker_node_tag_sync", "true")
	//os.Setenv("SKIP_cleanup", "true")

	deployEKSAndVerify(
		t,
		"eks-cluster-managed-workers",
		4,
		"",
		createEKSClusterManagedWorkersLaunchTemplateTerraformOptions,
		verifyEKSClusterManagedWorkersLaunchTemplate,
		cleanUpAmi,
	)
}

func TestEKSClusterManagedWorkersWithAutoscaler(t *testing.T) {
	t.Parallel()

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_deploy_autoscaler", "true")
	//os.Setenv("SKIP_autoscaler_test", "true")
	//os.Setenv("SKIP_cleanup_autoscaler", "true")
	//os.Setenv("SKIP_cleanup", "true")

	deployEKSAndVerify(
		t,
		"eks-cluster-managed-workers",
		4,
		"",
		createEKSClusterManagedWorkersTerraformOptions,
		verifyEKSClusterManagedWorkersWithAutoscaler,
		func(t *testing.T, workingDir string) {},
	)
}

func verifyEKSClusterManagedWorkersWithAutoscaler(t *testing.T, workingDir string) {
	awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")
	kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
	eksClusterTerraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	eksClusterName := terraform.Output(t, eksClusterTerraformOptions, "eks_cluster_name")
	autoscalerKubectlOptions := k8s.NewKubectlOptions(kubectlOptions.ContextName, kubectlOptions.ConfigPath, "kube-system")
	autoscalerKubectlOptions.Env = kubectlOptions.Env
	autoscalerHelmOptions := &helm.Options{
		KubectlOptions: autoscalerKubectlOptions,
		SetValues: map[string]string{
			"awsRegion":                             awsRegion,
			"cloudProvider":                         "aws",
			"rbac.create":                           "true",
			"extraArgs.expander":                    "least-waste",
			"extraArgs.balance-similar-node-groups": "true",
			"extraArgs.scale-down-unneeded-time":    "2m",
			"extraArgs.scale-down-delay-after-add":  "2m",
			"autoDiscovery.clusterName":             eksClusterName,
		},
	}

	defer test_structure.RunTestStage(t, "cleanup_autoscaler", func() {
		helm.Delete(t, autoscalerHelmOptions, "cluster-autoscaler", true)
	})
	test_structure.RunTestStage(t, "deploy_autoscaler", func() {
		_, err := helm.RunHelmCommandAndGetOutputE(t, autoscalerHelmOptions, "repo", "add", "autoscaler", "https://kubernetes.github.io/autoscaler")
		require.NoError(t, err)
		helm.Install(t, autoscalerHelmOptions, "autoscaler/cluster-autoscaler-chart", "cluster-autoscaler")
	})

	test_structure.RunTestStage(t, "autoscaler_test", func() {
		verifyAutoscaler(t, workingDir, 8, 4)
	})
}

func verifyEKSClusterManagedWorkersPrefixDelegationNetwork(t *testing.T, workingDir string) {
	awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")

	var workerASGNames map[string][]string
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	terraform.OutputStruct(t, terraformOptions, "eks_worker_asg_names", &workerASGNames)

	flattenedASGNames := []string{}
	for _, asgNames := range workerASGNames {
		flattenedASGNames = append(flattenedASGNames, asgNames...)
	}

	test_structure.RunTestStage(t, "verify_network", func() {
		// With the deployed settings of minimum 17 and 2 warm, we expect 2 prefixes initially on each node, so verify
		// that first.
		for _, asgName := range flattenedASGNames {
			expectPrefixesOnASG(t, awsRegion, asgName, 2)
		}
	})
}

func expectPrefixesOnASG(t *testing.T, region string, asgName string, expectedPrefixCount int) {
	ec2Client, err := aws.NewEc2ClientE(t, region)
	require.NoError(t, err)

	instanceIDs := aws.GetInstanceIdsForAsg(t, asgName, region)
	for _, instanceID := range instanceIDs {
		request := &ec2.DescribeNetworkInterfacesInput{
			Filters: []*ec2.Filter{
				{Name: awsgo.String("attachment.instance-id"), Values: awsgo.StringSlice([]string{instanceID})},
			},
		}
		resp, err := ec2Client.DescribeNetworkInterfaces(request)
		require.NoError(t, err)

		// For the instance type we are using, only one prefix can be assigned per ENI, so we assert that the expected
		// prefix count is equal to the number of ENIs on the node. We also check to verify that one prefix is allocated
		// on the ENI.
		networkInterfaces := resp.NetworkInterfaces
		assert.Equal(t, expectedPrefixCount, len(networkInterfaces))
		for _, nInterface := range networkInterfaces {
			assert.Equal(t, 1, len(nInterface.Ipv4Prefixes))
		}
	}
}

func verifyEKSClusterManagedWorkersLaunchTemplate(t *testing.T, workingDir string) {
	test_structure.RunTestStage(t, "verify_worker_node_tag_sync", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
		launchTemplateID := terraform.Output(t, terraformOptions, "eks_worker_launch_template_id")

		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		allNodes := k8s.GetNodes(t, kubectlOptions)
		for _, node := range allNodes {
			nodeLabelLaunchTemplateID, hasLaunchTemplateID := node.Labels["eks.amazonaws.com/sourceLaunchTemplateId"]
			require.True(t, hasLaunchTemplateID, fmt.Sprintf("Node %s does not have label \"eks.amazonaws.com/sourceLaunchTemplateId\"", node.Name))
			assert.Equal(t, launchTemplateID, nodeLabelLaunchTemplateID)
		}
	})
}

func verifyEKSClusterManagedWorkersAddOns(t *testing.T, workingDir string) {
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	eksAddOns := terraform.OutputMapOfObjects(t, terraformOptions, "eks_cluster_addons")
	kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)

	test_structure.RunTestStage(t, "verify_addons", func() {
		// Verify that the addons are properly set up
		for k, v := range eksAddOns {
			addonName := v.(map[string]interface{})["addon_name"]
			assert.Equal(t, k, addonName)
		}

		// Verify that the the aws-node DS is properly configured
		awsnodeKubectlOptions := k8s.NewKubectlOptions(kubectlOptions.ContextName, kubectlOptions.ConfigPath, "kube-system")
		awsnodeKubectlOptions.Env = kubectlOptions.Env
		awsNodeDaemonSet := k8s.GetDaemonSet(t, awsnodeKubectlOptions, "aws-node")
		containers := awsNodeDaemonSet.Spec.Template.Spec.Containers
		for _, v := range containers {
			assert.True(t, envVarsContains(v.Env, "ENABLE_PREFIX_DELEGATION", "1"), "Prefix delegation set")
		}
	})
}

func envVarsContains(envVars []v1.EnvVar, key string, value string) bool {
	for _, env := range envVars {
		if env.Name == key && env.Value == value {
			return true
		}
	}
	return false
}
