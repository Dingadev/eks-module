package test

import (
	"context"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go/aws/arn"
	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v2"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	ecrRepoTestDataKey    = "ecrRepo"
	ecrRepoUriTestDataKey = "ecrRepoUri"
)

type RoleMapping struct {
	RoleArn  string   `yaml:"rolearn"`
	Username string   `yaml:"username"`
	Groups   []string `yaml:"groups"`
}

func validateAuthConfigMapAndIAMRoleMapping(t *testing.T, workingDir string) {
	test_structure.RunTestStage(t, "verify_config_map", func() {
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		validateAwsAuthConfigMap(t, kubectlOptions, eksClusterTerratestOptions)
	})

	test_structure.RunTestStage(t, "verify_cluster_access", func() {
		region := test_structure.LoadString(t, workingDir, awsRegionTestDataKey)
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		testIamRoleMapping(t, kubectlOptions, region, eksClusterTerratestOptions)
	})
}

func validateAwsAuthConfigMap(t *testing.T, kubectlOptions *k8s.KubectlOptions, eksClusterTerratestOptions *terraform.Options) {
	clientset, err := k8s.GetKubernetesClientFromOptionsE(t, kubectlOptions)
	require.NoError(t, err)

	configmap, err := clientset.CoreV1().ConfigMaps("kube-system").Get(context.TODO(), "aws-auth", metav1.GetOptions{})
	require.NoError(t, err)

	roleMappingYaml, exists := configmap.Data["mapRoles"]
	assert.True(t, exists)

	var roleMappingList []RoleMapping
	require.NoError(t, yaml.Unmarshal([]byte(roleMappingYaml), &roleMappingList))
	assert.Equal(t, 4, len(roleMappingList))

	// Convert list of RoleMapping objects to map from rolearn to mapping so we can do better checks on it.
	roleMappings := map[string]RoleMapping{}
	for _, rm := range roleMappingList {
		roleMappings[rm.RoleArn] = rm
	}

	workerRoleArn := terraform.Output(t, eksClusterTerratestOptions, "eks_worker_iam_role_arn")
	actualWorkerRoleMapping := roleMappings[workerRoleArn]
	assert.Equal(t, "system:node:{{EC2PrivateDNSName}}", actualWorkerRoleMapping.Username)
	expectedWorkerGroups := []string{
		"system:bootstrappers",
		"system:nodes",
	}
	sort.Strings(expectedWorkerGroups)
	sort.Strings(actualWorkerRoleMapping.Groups)
	assert.Equal(t, expectedWorkerGroups, actualWorkerRoleMapping.Groups)

	fargateRoleArn := terraform.Output(t, eksClusterTerratestOptions, "eks_fargate_default_execution_role_arn")
	actualFargateRoleMapping := roleMappings[fargateRoleArn]
	assert.Equal(t, "system:node:{{SessionName}}", actualFargateRoleMapping.Username)
	expectedFargateGroups := []string{
		"system:bootstrappers",
		"system:node-proxier",
		"system:nodes",
	}
	sort.Strings(expectedFargateGroups)
	sort.Strings(actualFargateRoleMapping.Groups)
	assert.Equal(t, expectedFargateGroups, actualFargateRoleMapping.Groups)

	exampleRoleArn := terraform.Output(t, eksClusterTerratestOptions, "example_iam_role_arn")
	assert.Equal(
		t,
		RoleMapping{
			RoleArn:  exampleRoleArn,
			Username: nameFromArn(t, exampleRoleArn),
			Groups:   []string{"eks-k8s-role-mapping-test-group"},
		},
		roleMappings[exampleRoleArn],
	)
}

// Test that the newly created role maps to the right group in Kubernetes by checking its permissions.
func testIamRoleMapping(t *testing.T, kubectlOptions *k8s.KubectlOptions, region string, eksClusterTerratestOptions *terraform.Options) {
	// First, create the roles in Kubernetes by applying fixture. Assumes working directory is test folder
	roleMappingTestKubeResourcesPath, err := filepath.Abs("./kubefixtures/eks-k8s-role-mapping-test-role.yml")
	require.NoError(t, err)
	k8s.KubectlApply(t, kubectlOptions, roleMappingTestKubeResourcesPath)

	// Next, check permissions by assuming the newly created role and verifying we can't access the kube-system
	// namespace
	roleArn := terraform.Output(t, eksClusterTerratestOptions, "example_iam_role_arn")
	sess, err := aws.NewAuthenticatedSessionFromRole(region, roleArn)
	require.NoError(t, err)

	// Ignore error here, because `NewAuthenticatedSessionFromRole` already checks if credentials can be obtained
	creds, _ := sess.Config.Credentials.Get()

	kubectlCanIWithCreds(t, kubectlOptions, creds, []string{"get", "pods", "--namespace", "example"}, true)
	kubectlCanIWithCreds(t, kubectlOptions, creds, []string{"get", "pods", "--namespace", "kube-system"}, false)
}

func nameFromArn(t *testing.T, arnStr string) string {
	parsedArn, err := arn.Parse(arnStr)
	require.NoError(t, err)

	resourceSplit := strings.Split(parsedArn.Resource, "/")
	require.Equal(t, 2, len(resourceSplit))
	return resourceSplit[1]
}
