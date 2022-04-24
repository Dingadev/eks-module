package test

import (
	"fmt"
	"path/filepath"
	"sync"
	"testing"
	"time"

	awsgo "github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/gruntwork-io/gruntwork-cli/collections"
	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/environment"
	"github.com/gruntwork-io/terratest/modules/git"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/packer"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// These constants are based on kubefixtures/robust-nginx-deployment.yml
const (
	nginxNamespace   = "default"
	nginxServiceName = "nginx-service"
)

func getRandomFargateRegion(t *testing.T) string {
	// Approve only regions where EKS Fargate is available
	approvedRegions := []string{
		"us-east-1",
		"us-east-2",
		"eu-west-1",
		"ap-northeast-1",
	}
	return aws.GetRandomRegion(t, approvedRegions, []string{})
}

func getRandomRegionWithACMCerts(t *testing.T) string {
	// Regions in Gruntwork Phx DevOps account that have ACM certs
	regionsWithACM := []string{
		"us-east-2",
		"us-west-2",
		"eu-west-1",
		"ap-northeast-1",
		"ap-southeast-2",
		"ca-central-1",
	}
	return aws.GetRandomRegion(t, regionsWithACM, []string{})
}

func getRandomRegion(t *testing.T) string {
	// Approve only regions where EKS and the EKS optimized Linux AMI are available
	approvedRegions := []string{
		"us-west-2",
		"us-east-1",
		"us-east-2",
		"eu-west-1",
		"eu-central-1",
		"ap-southeast-1",
		"ap-southeast-2",
		"ap-northeast-1",
	}
	return aws.GetRandomRegion(t, approvedRegions, []string{})
}

// getUsableAvailabilityZones returns the list of availability zones that work with EKS given a region.
func getUsableAvailabilityZones(t *testing.T, region string) []string {
	// us-east-1e currently does not have capacity to support EKS
	restrictedAvailabilityZones := []string{
		"us-east-1e",
	}

	usableZones := []string{}
	zones := aws.GetAvailabilityZones(t, region)
	for _, zone := range zones {
		// If zone is not in the restricted list, include it
		if !collections.ListContainsElement(restrictedAvailabilityZones, zone) {
			usableZones = append(usableZones, zone)
		}
	}
	return usableZones
}

// getAwsAccountId works around a limitation in terratest aws.GetAccountId where it cannot properly resolve the AWS
// account ID for assumed roles. So here, we will allow the account ID to be fed in via an environment variable, and
// fallback to the terratest function if not defined.
func getAwsAccountId(t *testing.T) string {
	maybeAccountId := environment.GetFirstNonEmptyEnvVarOrEmptyString(
		t, []string{"TERRATEST_AWS_ACCOUNT_ID"})
	if maybeAccountId == "" {
		return aws.GetAccountId(t)
	}
	return maybeAccountId
}

// kubectlCanIWithCreds executes the `auth can-i` function of `kubectl` to verify permissions of the current kubectl
// context. This supports switching EKS contexts by switching the AWS credentials before the call.
func kubectlCanIWithCreds(t *testing.T, options *k8s.KubectlOptions, creds credentials.Value, args []string, canI bool) {
	options.Env = map[string]string{
		"AWS_ACCESS_KEY_ID":     creds.AccessKeyID,
		"AWS_SECRET_ACCESS_KEY": creds.SecretAccessKey,
		"AWS_SESSION_TOKEN":     creds.SessionToken,
	}
	cmdArgs := append([]string{"auth", "can-i"}, args...)
	out, err := k8s.RunKubectlAndGetOutputE(t, options, cmdArgs...)
	if canI {
		require.NoError(t, err)
		require.Equal(t, out, "yes")
	} else {
		// Depending on the platform and kubectl version, the output will be one of these two
		require.True(t, out == "no - no RBAC policy matched" || out == "no")
	}
}

// kubeWaitUntilNumNodes continuously polls the Kubernetes cluster until there are the expected number of nodes
// registered (regardless of readiness).
func kubeWaitUntilNumNodes(t *testing.T, kubectlOptions *k8s.KubectlOptions, numNodes int, retries int, sleepBetweenRetries time.Duration) {
	statusMsg := fmt.Sprintf("Wait for %d Kube Nodes to be registered.", numNodes)
	message, err := retry.DoWithRetryE(
		t,
		statusMsg,
		retries,
		sleepBetweenRetries,
		func() (string, error) {
			nodes, err := k8s.GetNodesE(t, kubectlOptions)
			if err != nil {
				return "", err
			}
			if len(nodes) != numNodes {
				return "", fmt.Errorf("Not enough nodes: %d expected, %d actual", numNodes, len(nodes))
			}
			return "All nodes registered", nil
		},
	)
	if err != nil {
		logger.Logf(t, "Error waiting for expected number of nodes: %s", err)
		t.Fatal(err)
	}
	logger.Logf(t, message)
}

// getENIsForVpc returns all network interfaces associated with the provided vpc.
func getENIsForVpc(t *testing.T, region string, vpcId string) []*ec2.NetworkInterface {
	ec2Client := aws.NewEc2Client(t, region)
	input := ec2.DescribeNetworkInterfacesInput{
		Filters: []*ec2.Filter{
			&ec2.Filter{
				Name:   awsgo.String("vpc-id"),
				Values: []*string{awsgo.String(vpcId)},
			},
		},
	}
	output, err := ec2Client.DescribeNetworkInterfaces(&input)
	require.NoError(t, err)
	return output.NetworkInterfaces
}

// getENIIds returns the network interface id of the provided network interface resources.
func getENIIds(networkInterfaces []*ec2.NetworkInterface) []string {
	output := []string{}
	for _, networkInterface := range networkInterfaces {
		output = append(output, *networkInterface.NetworkInterfaceId)
	}
	return output
}

// newENIsForVpc will return all the network interfaces in the VPC that has been created since the last reference point,
// provided as the list of network interfaces retrieved in the last query.
func newENIsForVpc(
	t *testing.T,
	region string,
	vpcId string,
	oldNetworkInterfaces []*ec2.NetworkInterface,
) []*ec2.NetworkInterface {
	oldNetworkInterfaceIds := getENIIds(oldNetworkInterfaces)
	allNetworkInterfaces := getENIsForVpc(t, region, vpcId)
	newNetworkInterfaces := []*ec2.NetworkInterface{}
	for _, networkInterface := range allNetworkInterfaces {
		isOldInterface := collections.ListContainsElement(
			oldNetworkInterfaceIds,
			awsgo.StringValue(networkInterface.NetworkInterfaceId),
		)
		if !isOldInterface {
			newNetworkInterfaces = append(newNetworkInterfaces, networkInterface)
		}
	}
	return newNetworkInterfaces
}

// waitForNetworkInterfacesToBeDeletedE will wait until the provided network interfaces are deleted. This will time out
// if interfaces are not deleted after 5 minutes and return an error.
func waitForNetworkInterfacesToBeDeletedE(t *testing.T, region string, networkInterfaceIds []string) error {
	ec2Client := aws.NewEc2Client(t, region)
	input := &ec2.DescribeNetworkInterfacesInput{
		Filters: []*ec2.Filter{
			&ec2.Filter{
				Name:   awsgo.String("network-interface-id"),
				Values: awsgo.StringSlice(networkInterfaceIds),
			},
		},
	}
	// Wait for up to 5 minutes, with 5 second intervals in the check
	message, err := retry.DoWithRetryE(
		t,
		"Waiting for network interfaces created by service to be deleted.",
		60,
		5*time.Second,
		func() (string, error) {
			output, err := ec2Client.DescribeNetworkInterfaces(input)
			if err != nil {
				return "Error fetching network interfaces", err
			}
			if len(output.NetworkInterfaces) > 0 {
				return "Network interfaces still exist", NetworkInterfacesStillExist{}
			}
			return "All network interfaces created by service is deleted.", nil
		},
	)
	logger.Logf(t, message)
	return err
}

// deleteDetachedNetworkInterfacesForVpc will grab all the network interfaces in the vpc that are detached and delete
// them.
func deleteDetachedNetworkInterfacesForVpc(t *testing.T, region string, vpcId string) {
	logger.Logf(t, "Attempting to delete detached network interfaces for vpc %s in %s", vpcId, region)
	input := ec2.DescribeNetworkInterfacesInput{
		Filters: []*ec2.Filter{
			&ec2.Filter{
				Name:   awsgo.String("vpc-id"),
				Values: []*string{awsgo.String(vpcId)},
			},
			&ec2.Filter{
				Name:   awsgo.String("status"),
				Values: []*string{awsgo.String("available")},
			},
		},
	}
	ec2Client := aws.NewEc2Client(t, region)
	output, err := ec2Client.DescribeNetworkInterfaces(&input)
	assert.NoError(t, err)
	networkInterfaceCount := len(output.NetworkInterfaces)
	if networkInterfaceCount > 0 {
		logger.Logf(
			t,
			"Found %d network interfaces in detached state. Initiating delete.",
			networkInterfaceCount,
		)
	} else {
		logger.Logf(t, "Found no network interfaces in detached state")
	}
	for _, networkInterface := range output.NetworkInterfaces {
		_, err := ec2Client.DeleteNetworkInterface(&ec2.DeleteNetworkInterfaceInput{
			NetworkInterfaceId: networkInterface.NetworkInterfaceId,
		})
		if err != nil {
			// We don't fail the test for an error because this function is used in a background goroutine that will
			// repeat the attempt later.
			// Typically this happens due to eventual consistency issues in AWS, where the describe call returns an
			// available network interface that AWS still thinks is in use at the delete stage.
			logger.Logf(t, "WARNING: error deleting interface %s: %s", *networkInterface.NetworkInterfaceId, err)
		} else {
			logger.Logf(t, "Deleted interface %s", *networkInterface.NetworkInterfaceId)
		}
	}
}

// continuouslyAttemptToDeleteDetachedNetworkInterfacesForVpc will continuously watch for network interfaces that are
// detached and available, deleting them as they are found.
func continuouslyAttemptToDeleteDetachedNetworkInterfacesForVpc(
	t *testing.T,
	region string,
	vpcId string,
	stopChecking <-chan bool,
	sleepBetweenChecks time.Duration,
) *sync.WaitGroup {
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			select {
			case <-stopChecking:
				logger.Log(t, "Got signal to stop checking for detached network interfaces.\n")
				return
			case <-time.After(sleepBetweenChecks):
				deleteDetachedNetworkInterfacesForVpc(t, region, vpcId)
			}
		}
	}()
	return &wg
}

// Pulls down debug logs from the cluster for system Pods. Useful for debugging various test failures.
func getDebugLogs(t *testing.T, kubectlOptions *k8s.KubectlOptions) {
	// Grab the logs for ALB ingress controller
	selector := "app.kubernetes.io/instance=aws-alb-ingress-controller,app.kubernetes.io/name=aws-alb-ingress-controller"
	err := k8s.RunKubectlE(
		t,
		kubectlOptions,
		"logs",
		"-n", "kube-system",
		"-l", selector,
	)
	if err != nil {
		logger.Logf(t, "WARNING: encountered error while retrieving logs for ALB ingress controller - %s", err)
	}

	// Grab the logs for external-dns app
	selector = "app.kubernetes.io/instance=external-dns,app.kubernetes.io/name=external-dns"
	err = k8s.RunKubectlE(
		t,
		kubectlOptions,
		"logs",
		"-n", "kube-system",
		"-l", selector,
	)
	if err != nil {
		logger.Logf(t, "WARNING: encountered error while retrieving logs for ALB ingress controller - %s", err)
	}
}

// Build supporting services EKS cluster AMI
func buildSupportingServicesEKSClusterAMI(
	t *testing.T,
	region string,
	workingDir string,
) string {
	packerTemplatePath := filepath.Join(workingDir, "eks-cluster-with-supporting-services", "packer", "build.pkr.hcl")
	packerOptions := &packer.Options{
		Template: packerTemplatePath,
		Vars: map[string]string{
			"aws_region":               region,
			"terraform_aws_eks_branch": git.GetCurrentBranchName(t),
		},
	}
	return packer.BuildArtifact(t, packerOptions)
}
