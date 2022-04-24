package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
)

func TestEKSWorkersOptionality(t *testing.T) {
	t.Parallel()

	testFolder := test_structure.CopyTerraformFolderToTemp(t, "..", "modules/eks-cluster-workers")
	region := getRandomRegion(t)
	terraformOptions := &terraform.Options{
		TerraformDir: testFolder,
		Vars: map[string]interface{}{
			"cluster_name": "test-cluster",
			"autoscaling_group_configurations": map[string]interface{}{
				"asg1": map[string]interface{}{
					"min_size":          1,
					"max_size":          2,
					"asg_instance_type": "t3.micro",
					"subnet_ids":        []string{"doesnt-matter"},
					"tags":              []string{},
				},
			},
			"asg_default_instance_ami": "doesnt-matter",
			"create_resources":         false,
		},
		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": region,
		},
	}
	planStruct := terraform.InitAndPlanAndShowWithStructNoLogTempPlanFile(t, terraformOptions)
	assert.Equal(t, 0, len(planStruct.ResourcePlannedValuesMap))
	assert.Equal(t, 0, len(planStruct.ResourceChangesMap))
}

func TestEKSManagedWorkersOptionality(t *testing.T) {
	t.Parallel()

	testFolder := test_structure.CopyTerraformFolderToTemp(t, "..", "modules/eks-cluster-managed-workers")
	region := getRandomRegion(t)
	terraformOptions := &terraform.Options{
		TerraformDir: testFolder,
		Vars: map[string]interface{}{
			"cluster_name": "test-cluster",
			"node_group_configurations": map[string]interface{}{
				"ngroup1": map[string]interface{}{
					"min_size":     1,
					"max_size":     2,
					"desired_size": 1,
					"subnet_ids":   []string{"doesnt-matter"},
				},
			},
			"create_resources": false,
		},
		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": region,
		},
	}
	planStruct := terraform.InitAndPlanAndShowWithStructNoLogTempPlanFile(t, terraformOptions)
	assert.Equal(t, 0, len(planStruct.ResourcePlannedValuesMap))
	assert.Equal(t, 0, len(planStruct.ResourceChangesMap))
}
