package test

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	awsgo "github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/cloudtrail"
	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	// We have created a master key in the Phoenix DevOps account that we can use for automated testing without creating
	// a new key on each run. That's because generating a KMS Master Key costs $1/month, even if we delete it right
	// after, which can add up quickly if we run this test often.
	masterKeyForTestingID     = "alias/dedicated-test-key"
	masterKeyForTestingRegion = "us-east-1"
)

// Test that we can use a CMK as an encryption key for envelope encryption of Secrets, and verify usage of the key by
// EKS.
func TestEKSFargateClusterWithKMSEncryption(t *testing.T) {
	t.Parallel()

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_verify", "true")
	//os.Setenv("SKIP_cleanup", "true")

	deployEKSAndVerify(
		t,
		"eks-fargate-cluster",
		0,
		masterKeyForTestingRegion,
		createEKSFargateClusterWithKMSTerraformOptions,
		verifySecretEncryptionWithKMS,
		func(t *testing.T, workingDir string) {},
	)
}

func verifySecretEncryptionWithKMS(t *testing.T, workingDir string) {
	kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
	kubectlOptions.Namespace = "default"

	test_structure.RunTestStage(t, "verify", func() {
		// Make sure that we can successfully create and retrieve secrets
		testCreds := random.UniqueId()
		k8s.RunKubectl(
			t,
			kubectlOptions,
			"create", "secret", "generic", "test-creds",
			fmt.Sprintf("--from-literal=test-creds=%s", testCreds),
		)
		createTime := time.Now()
		testSecret := k8s.GetSecret(t, kubectlOptions, "test-creds")
		assert.Equal(t, string(testSecret.Data["test-creds"]), testCreds)

		// And verify that EKS used the CMK. We do this by looking up all CloudTrail events related to the KMS key and
		// making sure we find at least one event that originated from the EKS cluster we launched. Since CloudTrail
		// takes time to sync, we retry this routine up to 10 minutes.
		retry.DoWithRetry(
			t,
			"lookup cloudtrail events",
			60,
			20*time.Second,
			func() (string, error) {
				// Search KMS encrypt entries in a +/- 1 minute window of creating the Secret.
				if !foundEKSEncryptViaKMSEvents(t, createTime.Add(-1*time.Minute), createTime.Add(1*time.Minute)) {
					return "", fmt.Errorf("Could not find corresponding KMS encrypt event from EKS")
				}
				return "", nil
			},
		)
	})
}

func foundEKSEncryptViaKMSEvents(t *testing.T, startTime time.Time, endTime time.Time) bool {
	keyArn := aws.GetCmkArn(t, masterKeyForTestingRegion, masterKeyForTestingID)
	ctrailSvc := getCloudTrailClient(t, masterKeyForTestingRegion)
	found := false
	err := ctrailSvc.LookupEventsPages(
		&cloudtrail.LookupEventsInput{
			StartTime: awsgo.Time(startTime),
			EndTime:   awsgo.Time(endTime),
			LookupAttributes: []*cloudtrail.LookupAttribute{
				&cloudtrail.LookupAttribute{
					AttributeKey:   awsgo.String(cloudtrail.LookupAttributeKeyEventName),
					AttributeValue: awsgo.String("Encrypt"),
				},
			},
		},
		func(resp *cloudtrail.LookupEventsOutput, _ bool) bool {
			for _, event := range resp.Events {
				var eventData map[string]interface{}
				err := json.Unmarshal([]byte(awsgo.StringValue(event.CloudTrailEvent)), &eventData)
				require.NoError(t, err)
				identity := eventData["userIdentity"].(map[string]interface{})
				requestData := eventData["requestParameters"].(map[string]interface{})
				if isInvokedByAWSEKS(identity) && requestData["keyId"] == keyArn {
					// Found at least one matching event, so cut the loop short.
					found = true
					return false
				}
			}
			return true
		},
	)
	require.NoError(t, err)
	return found
}

func isInvokedByAWSEKS(eventIdentityData map[string]interface{}) bool {
	return eventIdentityData["type"] == "AWSService" && eventIdentityData["invokedBy"] == "eks.amazonaws.com"
}

func createEKSFargateClusterWithKMSTerraformOptions(
	t *testing.T,
	workingDir string,
	uniqueID string,
	region string,
	templatePath string,
	kubeConfigPath string,
) *terraform.Options {
	options := createEKSFargateClusterTerraformOptions(t, workingDir, uniqueID, region, templatePath, kubeConfigPath)

	// Set the envelope encryption secret key
	keyArn := aws.GetCmkArn(t, masterKeyForTestingRegion, masterKeyForTestingID)
	options.Vars["secret_envelope_encryption_kms_key_arn"] = keyArn
	return options
}

func getCloudTrailClient(t *testing.T, region string) *cloudtrail.CloudTrail {
	sess, err := aws.NewAuthenticatedSession(region)
	require.NoError(t, err)
	return cloudtrail.New(sess)
}
