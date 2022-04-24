package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func verifyClusterVersionUpgrade(t *testing.T, workingDir string) {
	test_structure.RunTestStage(t, "verify_cluster_upgrade", func() {
		eksClusterTerratestOptions := test_structure.LoadTerraformOptions(t, workingDir)
		eksClusterTerratestOptions.Vars["kubernetes_version"] = "1.22"
		eksClusterTerratestOptions.Vars["wait_for_component_upgrade_rollout"] = "1"
		terraform.Init(t, eksClusterTerratestOptions)

		// Show the plan to see what it plans to do when the k8s version is bumped
		terraform.Plan(t, eksClusterTerratestOptions)
		terraform.Apply(t, eksClusterTerratestOptions)
	})
}
