package test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestEKSFargateClusterPrivateAccess(t *testing.T) {
	t.Parallel()

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_restrict_public_access", "true")
	//os.Setenv("SKIP_verify_private_access", "true")
	//os.Setenv("SKIP_restore_public_access", "true")
	//os.Setenv("SKIP_cleanup", "true")

	deployEKSAndVerify(
		t,
		"eks-private-fargate-cluster",
		0,
		"us-east-2", // we hard code the region for this test because other regions are not able to setup the public endpoint quick enough
		createEKSFargateClusterWithBastionTerraformOptions,
		verifyPrivateEndpointAccess,
		func(t *testing.T, workingDir string) {
			keyPair := test_structure.LoadEc2KeyPair(t, workingDir)
			aws.DeleteEC2KeyPair(t, keyPair)
		},
	)
}

func verifyPrivateEndpointAccess(t *testing.T, workingDir string) {
	defer test_structure.RunTestStage(t, "restore_public_access", func() {
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		eksClusterTerratestOptions.Vars["endpoint_public_access"] = true

		// First, we make the change to the endpoint with no refreshing because the eks-k8s-role-mapping config map
		// won't be accessible while public access is restricted
		_, err := terraform.RunTerraformCommandE(
			t,
			eksClusterTerratestOptions,
			terraform.FormatArgs(eksClusterTerratestOptions, "apply", "-input=false", "-lock=false", "-auto-approve", "-refresh=false")...,
		)
		require.NoError(t, err)

		// We then apply with refresh only to update the state to the latest information.
		_, refreshErr := terraform.RunTerraformCommandE(
			t,
			eksClusterTerratestOptions,
			terraform.FormatArgs(eksClusterTerratestOptions, "apply", "-input=false", "-lock=false", "-auto-approve", "-refresh-only")...,
		)
		require.NoError(t, refreshErr)

		// Finally, we make sure everything is synced up.
		terraform.InitAndApply(t, eksClusterTerratestOptions)
	})

	test_structure.RunTestStage(t, "restrict_public_access", func() {
		// Verify we can get nodes before restricting public access
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		require.NoError(t, k8s.RunKubectlE(t, kubectlOptions, "get", "nodes"))

		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		eksClusterTerratestOptions.Vars["endpoint_public_access"] = false
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

	test_structure.RunTestStage(t, "verify_private_access", func() {
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		keyPair := test_structure.LoadEc2KeyPair(t, workingDir)
		publicIP := terraform.Output(t, eksClusterTerratestOptions, "bastion_host_ip")

		publicHost := ssh.Host{
			Hostname:    publicIP,
			SshUserName: "ubuntu",
			SshKeyPair:  keyPair.KeyPair,
		}
		retry.DoWithRetry(
			t,
			"kubectl from bastion host",
			4,
			15*time.Second,
			func() (string, error) {
				out, err := ssh.CheckSshCommandE(t, publicHost, "kubectl get nodes")
				if err != nil {
					logger.Logf(t, "Error running ssh: %s", out)
				}
				return out, err
			},
		)
	})
}
