package test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Test that restricting the public access CIDRs will prevent access to the EKS cluster via kubectl.
func TestEKSFargateClusterRestrictedPublicAccess(t *testing.T) {
	t.Parallel()

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_restrict_public_access", "true")
	//os.Setenv("SKIP_restore_public_access", "true")
	//os.Setenv("SKIP_cleanup", "true")

	deployEKSAndVerify(
		t,
		"eks-fargate-cluster",
		0,
		"us-east-2", // we hard code the region for this test because other regions are not able to setup the public endpoint quick enough
		createEKSFargateClusterTerraformOptions,
		verifyRestrictedPublicEndpoint,
		// There is no need for a special clean up function here
		func(t *testing.T, workingDir string) {},
	)
}

func verifyRestrictedPublicEndpoint(t *testing.T, workingDir string) {

	defer test_structure.RunTestStage(t, "restore_public_access", func() {
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)

		// We restrict to the current CIDR
		statusCode, myIp := http_helper.HttpGet(t, "https://checkip.amazonaws.com", nil)
		require.Equal(t, statusCode, 200)
		eksClusterTerratestOptions.Vars["endpoint_public_access_cidrs"] = []string{fmt.Sprintf("%s/32", strings.TrimSpace(myIp))}

		// We disable refreshing because the eks-k8s-role-mapping config map won't be accessible while public access is
		// restricted
		_, err := terraform.RunTerraformCommandE(
			t,
			eksClusterTerratestOptions,
			terraform.FormatArgs(eksClusterTerratestOptions, "apply", "-input=false", "-lock=false", "-auto-approve", "-refresh=false")...,
		)
		require.NoError(t, err)
		terraform.InitAndApply(t, eksClusterTerratestOptions)

		// Verify we can get nodes after restoring access
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		require.NoError(t, k8s.RunKubectlE(t, kubectlOptions, "get", "nodes"))
	})

	test_structure.RunTestStage(t, "restrict_public_access", func() {
		// Verify we can get nodes before restricting public access
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		require.NoError(t, k8s.RunKubectlE(t, kubectlOptions, "get", "nodes"))

		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		// Restrict to an ip block that we know we can never get
		eksClusterTerratestOptions.Vars["endpoint_public_access_cidrs"] = []string{"8.8.8.8/32"}
		terraform.InitAndApply(t, eksClusterTerratestOptions)

		// ... and verify we can't get nodes after restricting public access.
		// Note that we have a retry loop here because there is eventual consistency properties in switching the
		// endpoint.
		out, err := retry.DoWithRetryE(
			t,
			"Waiting for endpoint to be inaccessible",
			// Try for up to 5 minutes: 30 tries, 10 seconds between tries
			30,
			10*time.Second,
			func() (string, error) {
				out, err := k8s.RunKubectlAndGetOutputE(t, kubectlOptions, "get", "nodes")
				// We are waiting for an error here, so we "flip" the error result.
				if err == nil {
					return "", fmt.Errorf("API still accesssible publicly.")
				}
				return out, nil
			},
		)
		require.NoError(t, err)
		assert.True(t, strings.Contains(out, "Unable to connect to the server"))
	})
}
