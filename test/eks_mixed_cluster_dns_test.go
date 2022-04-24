package test

import (
	"net"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/require"
)

func verifyClusterMixedWorkersDNS(t *testing.T, workingDir string) {
	test_structure.RunTestStage(t, "verify_cluster_dns", func() {
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)

		namespaceName := strings.ToLower(random.UniqueId())

		defer k8s.DeleteNamespace(t, kubectlOptions, namespaceName)
		k8s.CreateNamespace(t, kubectlOptions, namespaceName)
		kubectlOptions.Namespace = namespaceName

		out := retry.DoWithRetry(
			t,
			"run curl",
			3,
			5*time.Second,
			func() (string, error) {
				return k8s.RunKubectlAndGetOutputE(
					t,
					kubectlOptions,
					"run",
					"--attach",
					"--quiet",
					"--rm",
					"--restart=Never",
					"curl",
					"--image",
					"curlimages/curl",
					"--",
					"-s",
					"checkip.amazonaws.com",
				)
			},
		)

		// Output can sometimes contain an error message if kubectl attempts to connect to pod too early, so we always
		// get the last line of the output.
		outLines := strings.Split(out, "\n")
		maybeIP := outLines[len(outLines)-1]
		require.NotNil(t, net.ParseIP(maybeIP))
	})
}
