package test

import (
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
)

func testKubergruntASGDrain(t *testing.T, workingDir string) {
	test_structure.RunTestStage(t, "asg_drain", func() {
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)

		allASGs := terraform.OutputList(t, eksClusterTerratestOptions, "eks_worker_asg_names")

		args := []string{
			"eks",
			"drain",
			"--region", awsRegion,
			"--kubeconfig", kubectlOptions.ConfigPath,
			"--kubectl-context-name", kubectlOptions.ContextName,
			"--delete-local-data",
		}
		for _, asgName := range allASGs {
			args = append(args, "--asg-name", asgName)
		}

		command := shell.Command{
			Command: "kubergrunt",
			Args:    args,
		}
		shell.RunCommand(t, command)
	})

	test_structure.RunTestStage(t, "verify_asg_drain", func() {
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		nodes := k8s.GetNodes(t, kubectlOptions)
		// Verify all non Fargate nodes are cordoned by the drain process.
		for _, node := range nodes {
			if !strings.HasPrefix(node.ObjectMeta.Name, "fargate") {
				assert.True(t, node.Spec.Unschedulable)
			}
		}
	})
}
