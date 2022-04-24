package test

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	awsgo "github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/cloudwatchlogs"
	"github.com/gruntwork-io/terratest/modules/aws"
	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	WaitTimerRetries = 120
	WaitTimerSleep   = 10 * time.Second
	NumPodsExpected  = 3

	// This is a Hosted Zone in the Gruntwork Phoenix DevOps AWS account
	DefaultDomainNameForTest = "gruntwork.in"
)

var DefaultDomainTagForTest = map[string]string{
	"shared-management-with-kubernetes": "true",
}

// Test that we can:
//
// 1. Provision an EKS cluster using the eks-cluster module
// 2. Provision multiple worker pools against the same cluster
// 3. Configure kubectl to connect to the EKS cluster using the eks-cluster module
// 4. Deploy aws-auth configmap using eks-k8s-role-mapping module for all worker pools provisioned
// 5. Transfer EC2 tags on the worker pools to be node labels in Kubernetes
// 6. Verify the nodes are registered and ready
// 7. Deploy enough workload to trigger an autoscaling event
func TestEKSClusterAutoscaler(t *testing.T) {
	t.Parallel()

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_foo", "true") // This stage doesn't exist, but is useful in preventing copying to a tmp dir
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_verify_worker_node_types", "true")
	//os.Setenv("SKIP_deploy_core_services", "true")
	//os.Setenv("SKIP_autoscaler_test", "true")
	//os.Setenv("SKIP_cleanup_core_services", "true")
	//os.Setenv("SKIP_cleanup", "true")
	//os.Setenv("SKIP_cleanup_cluster_logs", "true")
	//os.Setenv("SKIP_cleanup_container_insights_logs", "true")

	defer test_structure.RunTestStage(t, "cleanup_cluster_logs", func() {
		cleanupClusterLogs(t)
	})

	defer test_structure.RunTestStage(t, "cleanup_container_insights_logs", func() {
		cleanupContainerInsightsLogs(t)
	})

	deployEKSAndVerify(
		t,
		"eks-cluster-with-supporting-services/eks-cluster",
		3,
		"",
		createEKSClusterWithSupportingServicesTerraformOptions,
		verifyEKSClusterWithAutoscaler,
		cleanUpAmi,
	)
}

// Test that we can:
//
// 1. Provision an EKS cluster using the eks-cluster module
// 2. Provision multiple worker pools against the same cluster
// 3. Configure kubectl to connect to the EKS cluster using the eks-cluster module
// 4. Deploy aws-auth configmap using eks-k8s-role-mapping module for all worker pools provisioned
// 5. Transfer EC2 tags on the worker pools to be node labels in Kubernetes
// 6. Verify the nodes are registered and ready
// 7. Deploy nginx using k8s-service chart using helm and verify you can access the nginx server
func TestEKSClusterWithSupportingServices(t *testing.T) {
	t.Parallel()

	workingDir := filepath.Join(".", "stages", t.Name())

	// Uncomment any of the following to skip that section during the test
	//os.Setenv("SKIP_foo", "true") // This stage doesn't exist, but is useful in preventing copying to a tmp dir
	//os.Setenv("SKIP_select_region", "true")
	//os.Setenv("SKIP_create_test_copy_of_examples", "true")
	//os.Setenv("SKIP_create_terratest_options", "true")
	//os.Setenv("SKIP_terraform_apply", "true")
	//os.Setenv("SKIP_wait_for_workers", "true")
	//os.Setenv("SKIP_verify_worker_node_types", "true")
	//os.Setenv("SKIP_deploy_core_services", "true")
	//os.Setenv("SKIP_verify_container_insights_logs", "true")
	//os.Setenv("SKIP_deploy_and_verify_nginx_without_dns", "true")
	//os.Setenv("SKIP_deploy_and_verify_nginx_with_private_dns", "true")
	//os.Setenv("SKIP_deploy_and_verify_nginx_with_public_dns", "true")
	//os.Setenv("SKIP_cleanup_core_services", "true")
	//os.Setenv("SKIP_cleanup", "true")
	//os.Setenv("SKIP_cleanup_cluster_logs", "true")
	//os.Setenv("SKIP_cleanup_container_insights_logs", "true")

	test_structure.RunTestStage(t, "select_region", func() {
		region := getRandomRegionWithACMCerts(t)
		test_structure.SaveString(t, workingDir, "awsRegion", region)
	})

	defer test_structure.RunTestStage(t, "cleanup_cluster_logs", func() {
		cleanupClusterLogs(t)
	})

	defer test_structure.RunTestStage(t, "cleanup_container_insights_logs", func() {
		cleanupContainerInsightsLogs(t)
	})

	region := test_structure.LoadString(t, workingDir, "awsRegion")
	deployEKSAndVerify(
		t,
		"eks-cluster-with-supporting-services/eks-cluster",
		3,
		region,
		createEKSClusterWithSupportingServicesTerraformOptions,
		verifyEKSClusterWithSupportingServices,
		cleanUpAmi,
	)
}

func verifyEKSClusterWithAutoscaler(t *testing.T, workingDir string) {
	// We don't save the terraform options for deploying core services, because all the dynamic state necessary to
	// construct it is already stored.
	deployCoreServicesTerraformOptions := constructDeployCoreServicesTerraformOptionsFromCluster(t, workingDir)

	test_structure.RunTestStage(t, "verify_worker_node_types", func() { checkNodeWorkerTypes(t, workingDir) })

	defer test_structure.RunTestStage(t, "cleanup_core_services", func() {
		getLogsIfFailed(t, workingDir)
		terraform.Destroy(t, deployCoreServicesTerraformOptions)
	})

	test_structure.RunTestStage(t, "deploy_core_services", func() {
		terraform.InitAndApply(t, deployCoreServicesTerraformOptions)
	})

	test_structure.RunTestStage(t, "autoscaler_test", func() {
		verifyAutoscaler(t, workingDir, 4, 3)
	})
}

// verifyEKSClusterWithSupportingServices verifies the various expected properties of the cluster.
func verifyEKSClusterWithSupportingServices(t *testing.T, workingDir string) {
	// We don't save the terraform options for deploying core services, because all the dynamic state necessary to
	// construct it is already stored.
	deployCoreServicesTerraformOptions := constructDeployCoreServicesTerraformOptionsFromCluster(t, workingDir)

	test_structure.RunTestStage(t, "verify_worker_node_types", func() { checkNodeWorkerTypes(t, workingDir) })

	defer test_structure.RunTestStage(t, "cleanup_core_services", func() {
		getLogsIfFailed(t, workingDir)
		terraform.Destroy(t, deployCoreServicesTerraformOptions)
	})

	test_structure.RunTestStage(t, "deploy_core_services", func() {
		// To test that you can independently destroy and apply the core services, we deploy core services twice
		terraform.InitAndApply(t, deployCoreServicesTerraformOptions)
		terraform.Destroy(t, deployCoreServicesTerraformOptions)
		terraform.Apply(t, deployCoreServicesTerraformOptions)

		// We also want to make sure there is no perpetual diff
		counts := terraform.GetResourceCount(t, terraform.InitAndPlan(t, deployCoreServicesTerraformOptions))
		assert.Equal(t, 0, counts.Add)
		assert.Equal(t, 0, counts.Change)
		assert.Equal(t, 0, counts.Destroy)
	})

	test_structure.RunTestStage(t, "verify_container_insights_logs", func() {
		verifyContainerInsightsLogs(t, workingDir)
	})

	// Spawn nginx verification tests
	// We group the tests in a synchronous call so that all the tests must finish running before starting the cleanup
	// procedures. The groups within the outer test will be run in parallel.
	t.Run("NginxService", func(outerT *testing.T) {
		outerT.Run("NoDNS", func(innerT *testing.T) {
			innerT.Parallel()
			verifyNginxServiceNoDNS(innerT, workingDir)
		})

		outerT.Run("PrivDNS", func(innerT *testing.T) {
			innerT.Parallel()
			verifyNginxServicePrivDNS(innerT, workingDir)
		})

		outerT.Run("PubDNS", func(innerT *testing.T) {
			innerT.Parallel()
			verifyNginxServicePubDNS(innerT, workingDir)
		})
	})
}

func verifyContainerInsightsLogs(t *testing.T, workingDir string) {
	// Load info necessary to fetch Container Insights Logs
	kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
	eksClusterTerraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")
	eksClusterName := terraform.Output(t, eksClusterTerraformOptions, "eks_cluster_name")

	waitForContainerInsightsLogStreams(t, kubectlOptions, awsRegion, eksClusterName)
}

func verifyNginxServiceNoDNS(t *testing.T, workingDir string) {
	// Load info necessary to create terraform options for the nginx-service example
	uniqueID := test_structure.LoadString(t, workingDir, "uniqueID")
	kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
	eksClusterTerraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")
	eksClusterName := terraform.Output(t, eksClusterTerraformOptions, "eks_cluster_name")
	eksVPCID := terraform.Output(t, eksClusterTerraformOptions, "vpc_id")

	// Base test case that is testing without any DNS hosted zones.
	test_structure.RunTestStage(t, "deploy_and_verify_nginx_without_dns", func() {
		// create a new test folder copy for this test, because it is run in parallel with the other nginx-service tests
		// that share a common terraform path.
		testFolder := test_structure.CopyTerraformFolderToTemp(t, "..", "examples")

		// NOTE: Service Names require starting with alphabet, so we always start with the char 'a'
		appName := fmt.Sprintf("a%s-nginx-nodns", strings.ToLower(uniqueID))
		helmDeploymentTerraformModulePath := filepath.Join(testFolder, "eks-cluster-with-supporting-services/nginx-service")
		nginxServiceTerraformOptions := createNginxServiceTerraformOptions(
			t,
			helmDeploymentTerraformModulePath,
			awsRegion,
			eksClusterName,
			eksVPCID,
			appName,
		)

		defer terraform.Destroy(t, nginxServiceTerraformOptions)
		terraform.InitAndApply(t, nginxServiceTerraformOptions)

		// Verify that the nginx service comes up
		verifyNginxService(t, kubectlOptions, appName)

		// Verify we have nginx access logs from checking it is up
		verifyEC2WorkerCloudWatchLogs(t, kubectlOptions, awsRegion, eksClusterName, appName)

		// Now we check that the ALB endpoint works.
		verifyNginxIngress(t, kubectlOptions, appName)
	})
}

func verifyNginxServicePrivDNS(t *testing.T, workingDir string) {
	// Load info necessary to create terraform options for the nginx-service example
	uniqueID := test_structure.LoadString(t, workingDir, "uniqueID")
	kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
	eksClusterTerraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")
	eksClusterName := terraform.Output(t, eksClusterTerraformOptions, "eks_cluster_name")
	eksVPCID := terraform.Output(t, eksClusterTerraformOptions, "vpc_id")

	// Private DNS test case that is testing association with a private route 53 DNS hosted zones.
	test_structure.RunTestStage(t, "deploy_and_verify_nginx_with_private_dns", func() {
		// create a new test folder copy for this test, because it is run in parallel with the other nginx-service tests
		// that share a common terraform path.
		testFolder := test_structure.CopyTerraformFolderToTemp(t, "..", "examples")

		// NOTE: Service Names require starting with alphabet, so we always start with the char 'a'
		appName := fmt.Sprintf("a%s-nginx-privdns", strings.ToLower(uniqueID))
		helmDeploymentTerraformModulePath := filepath.Join(testFolder, "eks-cluster-with-supporting-services/nginx-service")
		nginxServiceTerraformOptions := createNginxServiceTerraformOptions(
			t,
			helmDeploymentTerraformModulePath,
			awsRegion,
			eksClusterName,
			eksVPCID,
			appName,
		)
		nginxServiceTerraformOptions.Vars["subdomain_suffix"] = appName
		nginxServiceTerraformOptions.Vars["use_private_hostname"] = "1"

		defer terraform.Destroy(t, nginxServiceTerraformOptions)
		terraform.InitAndApply(t, nginxServiceTerraformOptions)
		verifyNginxIngressPrivateDNS(t, kubectlOptions, appName)
	})
}

func verifyNginxServicePubDNS(t *testing.T, workingDir string) {
	// Load info necessary to create terraform options for the nginx-service example
	uniqueID := test_structure.LoadString(t, workingDir, "uniqueID")
	kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
	eksClusterTerraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")
	eksClusterName := terraform.Output(t, eksClusterTerraformOptions, "eks_cluster_name")
	eksVPCID := terraform.Output(t, eksClusterTerraformOptions, "vpc_id")

	test_structure.RunTestStage(t, "deploy_and_verify_nginx_with_public_dns", func() {
		// create a new test folder copy for this test, because it is run in parallel with the other nginx-service tests
		// that share a common terraform path.
		testFolder := test_structure.CopyTerraformFolderToTemp(t, "..", "examples")

		// NOTE: Service Names require starting with alphabet, so we always start with the char 'a'
		appName := fmt.Sprintf("a%s-nginx-pubdns", strings.ToLower(uniqueID))
		helmDeploymentTerraformModulePath := filepath.Join(testFolder, "eks-cluster-with-supporting-services/nginx-service")
		nginxServiceTerraformOptions := createNginxServiceTerraformOptions(
			t,
			helmDeploymentTerraformModulePath,
			awsRegion,
			eksClusterName,
			eksVPCID,
			appName,
		)
		nginxServiceTerraformOptions.Vars["subdomain_suffix"] = appName
		nginxServiceTerraformOptions.Vars["use_public_hostname"] = "1"
		nginxServiceTerraformOptions.Vars["route53_hosted_zone_name"] = DefaultDomainNameForTest

		defer terraform.Destroy(t, nginxServiceTerraformOptions)
		terraform.InitAndApply(t, nginxServiceTerraformOptions)

		ingress := getHelmDeployedIngress(t, kubectlOptions, appName)
		ingressHost := ingress.Spec.Rules[0].Host
		endpoint := fmt.Sprintf("https://%s", ingressHost)
		err := http_helper.HttpGetWithRetryWithCustomValidationE(
			t,
			endpoint,
			nil,
			WaitTimerRetries,
			WaitTimerSleep,
			func(statusCode int, body string) bool {
				return statusCode == 200 && strings.Contains(body, "Welcome to nginx")
			},
		)
		if err != nil {
			// Make sure to pull down the logs for various services before failing the test
			getDebugLogs(t, kubectlOptions)

			t.Fatalf("Timed out waiting for Ingress endpoint to be available: %s", err)
		}
	})

}

func constructDeployCoreServicesTerraformOptionsFromCluster(t *testing.T, workingDir string) *terraform.Options {
	// Load info that can be generated based on initial step
	testFolder := test_structure.LoadString(t, workingDir, "testFolder")
	deployCoreServicesTerraformModulePath := filepath.Join(testFolder, "eks-cluster-with-supporting-services/core-services")
	awsRegion := test_structure.LoadString(t, workingDir, "awsRegion")

	// Load necessary info for deployment from the eks-cluster output
	eksClusterTerraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	eksClusterName := terraform.Output(t, eksClusterTerraformOptions, "eks_cluster_name")
	eksVPCID := terraform.Output(t, eksClusterTerraformOptions, "vpc_id")
	openidConnectProviderArn := terraform.Output(t, eksClusterTerraformOptions, "eks_openid_connect_provider_arn")
	openidConnectProviderUrl := terraform.Output(t, eksClusterTerraformOptions, "eks_openid_connect_provider_url")

	// Construct the terratest terraform options and return it
	return createDeployCoreServicesTerraformOptions(
		t,
		awsRegion,
		deployCoreServicesTerraformModulePath,
		eksClusterName,
		eksVPCID,
		openidConnectProviderArn,
		openidConnectProviderUrl,
	)
}

// checkNodeWorkerTypes makes sure that:
// - there are 2 application type node workers
// - there is 1 core type node worker
func checkNodeWorkerTypes(t *testing.T, workingDir string) {
	kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
	allNodes := k8s.GetNodes(t, kubectlOptions)
	countByType := map[string]int{}
	for _, node := range allNodes {
		nodeType, hasType := node.Labels["ec2.amazonaws.com/type"]
		require.True(t, hasType, fmt.Sprintf("Node %s does not have label \"ec2.amazonaws.com/type\"", node.Name))
		prevVal, hasType := countByType[nodeType]
		if !hasType {
			prevVal = 0
		}
		countByType[nodeType] = prevVal + 1
	}
	assert.Equal(t, countByType["application"], 2)
	assert.Equal(t, countByType["core"], 1)
}

func verifyNginxService(t *testing.T, kubectlOptions *k8s.KubectlOptions, appName string) {
	kubectlOptions.Namespace = "kube-system"

	// Get the service and wait until it is available
	service := getHelmDeployedService(t, kubectlOptions, appName)
	k8s.WaitUntilServiceAvailable(t, kubectlOptions, service.Name, WaitTimerRetries, WaitTimerSleep)

	// Now hit the service endpoint to verify it is accessible
	servicePtr := k8s.GetService(t, kubectlOptions, service.Name)
	serviceEndpoint := getServiceEndpointForApplication(t, kubectlOptions, servicePtr, 80)
	http_helper.HttpGetWithRetryWithCustomValidation(
		t,
		fmt.Sprintf("http://%s", serviceEndpoint),
		nil,
		WaitTimerRetries,
		WaitTimerSleep,
		func(statusCode int, body string) bool {
			return statusCode == 200 && strings.Contains(body, "Welcome to nginx")
		},
	)
}

func verifyNginxIngress(t *testing.T, kubectlOptions *k8s.KubectlOptions, appName string) {
	kubectlOptions.Namespace = "kube-system"

	// Get the ingress and wait until it is available
	ingress := getHelmDeployedIngress(t, kubectlOptions, appName)
	k8s.WaitUntilIngressAvailable(
		t,
		kubectlOptions,
		ingress.Name,
		WaitTimerRetries,
		WaitTimerSleep,
	)

	// Now hit the endpoint to make sure it is available
	var endpoint string
	ingress = *k8s.GetIngress(t, kubectlOptions, ingress.Name)
	ingressEndpoint := ingress.Status.LoadBalancer.Ingress[0].Hostname
	endpoint = fmt.Sprintf("http://%s", ingressEndpoint)
	err := http_helper.HttpGetWithRetryWithCustomValidationE(
		t,
		endpoint,
		nil,
		WaitTimerRetries,
		WaitTimerSleep,
		func(statusCode int, body string) bool {
			return statusCode == 200 && strings.Contains(body, "Welcome to nginx")
		},
	)
	if err != nil {
		// Make sure to pull down the logs for various services before failing the test
		getDebugLogs(t, kubectlOptions)

		t.Fatalf("Timed out waiting for Ingress endpoint to be available: %s", err)
	}
}

func verifyNginxIngressPrivateDNS(t *testing.T, kubectlOptions *k8s.KubectlOptions, appName string) {
	ingress := getHelmDeployedIngress(t, kubectlOptions, appName)
	ingressHost := ingress.Spec.Rules[0].Host

	// The ingress external DNS hostname is a private hosted zone. This means that it is only available from within the
	// VPC. Pods in the cluster are able to resolve the endpoint, so we deploy a curl pod that we can use to execute
	// curl commands.
	endpoint := fmt.Sprintf("http://%s", ingressHost)
	podName := fmt.Sprintf("curl-%s", strings.ToLower(appName))
	defer k8s.RunKubectl(t, kubectlOptions, "delete", "pod", podName)
	// We deploy the curl container with a long sleep so that it stays up. We can then use `exec` to synchronously run
	// curl commands from the container.
	k8s.RunKubectl(t, kubectlOptions, "run", podName, "--image", "curlimages/curl:7.69.1", "--", "sleep", "999999")

	_, err := retry.DoWithRetryE(
		t,
		fmt.Sprintf("Waiting for ingress to be available at %s", ingressHost),
		WaitTimerRetries,
		WaitTimerSleep,
		func() (string, error) {
			args := []string{"exec", podName, "--", "curl", endpoint}
			out, err := k8s.RunKubectlAndGetOutputE(t, kubectlOptions, args...)
			if err != nil {
				return "", err
			}
			if !strings.Contains(out, "Welcome to nginx") {
				return "", fmt.Errorf("Invalid curl: %s", out)
			}
			return "Successfully retrieved nginx page from ingress", nil
		},
	)
	if err != nil {
		// Make sure to pull down the logs for various services before failing the test
		getDebugLogs(t, kubectlOptions)

		t.Fatalf("Timed out waiting for Ingress endpoint to be available: %s", err)
	}
}

// To test the autoscaler, we deploy a Deployment that provisions enough pods to trigger a scale up event. Then, we
// delete that deployment and verify the scaled up node eventually terminates in a scale down event.
func verifyAutoscaler(t *testing.T, workingDir string, scaleUpNodeCount int, normalNodeCount int) {
	kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
	kubectlOptions.Namespace = "default"

	// Deploy autoscaler test pods to trigger scale up event
	autoscalerTestDeploymentPath, err := filepath.Abs("./kubefixtures/autoscaler-test-pods-deployment.yml")
	require.NoError(t, err)

	func() {
		defer cleanUpAutoscaler(t, kubectlOptions, autoscalerTestDeploymentPath)
		k8s.KubectlApply(t, kubectlOptions, autoscalerTestDeploymentPath)

		// Wait for scale up, for up to 10 minutes
		kubeWaitUntilNumNodes(t, kubectlOptions, scaleUpNodeCount, 120, 10*time.Second)
		k8s.WaitUntilAllNodesReady(t, kubectlOptions, 120, 10*time.Second)
	}()

	// Wait for scale down, for up to 10 minutes
	kubeWaitUntilNumNodes(t, kubectlOptions, normalNodeCount, 120, 10*time.Second)
}

func cleanUpAutoscaler(t *testing.T, kubectlOptions *k8s.KubectlOptions, k8sManifestPath string) {
	if t.Failed() {
		// Get logs from the cluster autoscaler for debugging purposes
		k8s.RunKubectl(t, kubectlOptions, "logs", "-n=kube-system", "-l=\"app.kubernetes.io/name=aws-cluster-autoscaler\"")
	}
	k8s.KubectlDelete(t, kubectlOptions, k8sManifestPath)
}

func verifyEC2WorkerCloudWatchLogs(
	t *testing.T,
	kubectlOptions *k8s.KubectlOptions,
	awsRegion string,
	eksClusterName string,
	appName string,
) {
	verifyCloudWatchLogs(t, kubectlOptions, awsRegion, eksClusterName, appName, "fluentbit-kube", "docker", true)
}

func verifyFargateWorkerCloudWatchLogs(
	t *testing.T,
	kubectlOptions *k8s.KubectlOptions,
	awsRegion string,
	eksClusterName string,
	appName string,
) {
	verifyCloudWatchLogs(t, kubectlOptions, awsRegion, eksClusterName, appName, "fargatekube", "containerd", false)
}

// The fluentd-cloudwatch container ships logs to CloudWatch using the eks cluster as the log group name.
// The streams for containers are generated in the following format:
//
// kubernetes.var.log.containers.{POD_NAME}_{NAMESPACE}_{CONTAINER_NAME}-{CONTAINER_ID}.log
func verifyCloudWatchLogs(
	t *testing.T,
	kubectlOptions *k8s.KubectlOptions,
	awsRegion string,
	eksClusterName string,
	appName string,
	prefix string,
	runtime string,
	checkFluentbitPods bool,
) {
	// Get the nginx pod info
	filters := getHelmResourcesFilter(appName)
	pods := k8s.ListPods(t, kubectlOptions, filters)
	require.Equal(t, len(pods), 1)

	if checkFluentbitPods {
		// Also check for fluent-bit pod log streams
		fluentbitFilters := metav1.ListOptions{
			LabelSelector: "app.kubernetes.io/name=aws-for-fluent-bit",
		}
		fluentbitPods := k8s.ListPods(t, kubectlOptions, fluentbitFilters)
		require.Equal(t, len(fluentbitPods), 3)
		pods = append(pods, fluentbitPods...)
	}
	for _, pod := range pods {
		podName := pod.Name
		containerName := pod.Status.ContainerStatuses[0].Name
		containerURI := pod.Status.ContainerStatuses[0].ContainerID
		// NOTE: containerURI is of the format RUNTIME://ID_IN_RUNTIME, so we strip the runtime info
		containerID := strings.TrimPrefix(containerURI, fmt.Sprintf("%s://", runtime))
		logStreamName := fmt.Sprintf(
			"%s.var.log.containers.%s_%s_%s-%s.log",
			prefix, podName, kubectlOptions.Namespace, containerName, containerID,
		)
		waitForLogStream(t, awsRegion, eksClusterName, logStreamName)
	}
}

func waitForLogStream(t *testing.T, awsRegion string, eksClusterName string, logStreamName string) {
	// Now continuously fetch the logs and until we can verify that we got at least one entry or we timeout the check.
	logGroupName := fmt.Sprintf("%s-container-logs", eksClusterName)
	retry.DoWithRetry(
		t,
		fmt.Sprintf("Waiting for log stream %s", logStreamName),
		WaitTimerRetries,
		WaitTimerSleep,
		func() (string, error) {
			logger.Logf(t, "Checking log stream %s in group %s in region %s", logStreamName, logGroupName, awsRegion)
			entries, err := aws.GetCloudWatchLogEntriesE(t, awsRegion, logStreamName, logGroupName)
			if err != nil {
				return "", err
			}
			if len(entries) == 0 {
				return "", fmt.Errorf("Log stream is empty: %d", len(entries))
			}
			return "Found log entries in stream", nil
		},
	)
}

func waitForContainerInsightsLogStreams(t *testing.T, kubectlOptions *k8s.KubectlOptions, awsRegion string, eksClusterName string) {
	// Now continuously fetch the logs and until we can verify that we got at least one entry or we timeout the check.
	logGroupName := fmt.Sprintf("/aws/containerinsights/%s/performance", eksClusterName)

	allNodes := k8s.GetNodes(t, kubectlOptions)
	for _, node := range allNodes {
		logStreamName := node.Name
		retry.DoWithRetry(
			t,
			fmt.Sprintf("Waiting for log stream %s", logStreamName),
			WaitTimerRetries,
			WaitTimerSleep,
			func() (string, error) {
				logger.Logf(t, "Checking log stream %s in group %s in region %s", logStreamName, logGroupName, awsRegion)
				entries, err := aws.GetCloudWatchLogEntriesE(t, awsRegion, logStreamName, logGroupName)
				if err != nil {
					return "", err
				}
				if len(entries) == 0 {
					return "", fmt.Errorf("Log stream is empty: %d", len(entries))
				}
				return "Found log entries in stream", nil
			},
		)

	}
}

func cleanUpAmi(t *testing.T, workingDir string) {
	region := test_structure.LoadString(t, workingDir, "awsRegion")
	amiID := test_structure.LoadArtifactID(t, workingDir)
	aws.DeleteAmiAndAllSnapshots(t, region, amiID)
}

func getHelmResourcesFilter(appName string) metav1.ListOptions {
	return metav1.ListOptions{
		LabelSelector: fmt.Sprintf("app.kubernetes.io/name=%s,app.kubernetes.io/instance=%s", appName, appName),
	}
}

func getHelmDeployedIngress(t *testing.T, kubectlOptions *k8s.KubectlOptions, appName string) networkingv1.Ingress {
	filters := getHelmResourcesFilter(appName)
	ingresses := k8s.ListIngresses(t, kubectlOptions, filters)
	require.Equal(t, len(ingresses), 1)
	ingress := ingresses[0]
	return ingress
}

func getHelmDeployedService(t *testing.T, kubectlOptions *k8s.KubectlOptions, appName string) corev1.Service {
	filters := getHelmResourcesFilter(appName)
	services := k8s.ListServices(t, kubectlOptions, filters)
	require.Equal(t, len(services), 1)
	service := services[0]
	return service
}

// getServiceEndpointForApplication provides similar functionality to k8s.GetServiceEndpoint, only this version is aware
// of node groups and will only get the endpoint using the application node group.
func getServiceEndpointForApplication(t *testing.T, kubectlOptions *k8s.KubectlOptions, service *corev1.Service, servicePort int) string {
	nodePort, err := k8s.FindNodePortE(service, int32(servicePort))
	require.NoError(t, err)

	nodes, err := k8s.GetNodesByFilterE(t, kubectlOptions, metav1.ListOptions{LabelSelector: "ec2.amazonaws.com/type=application"})
	require.NoError(t, err)
	require.Equal(t, len(nodes), 2)

	node := nodes[0]
	nodeHostname, err := k8s.FindNodeHostnameE(t, node)
	require.NoError(t, err)

	return fmt.Sprintf("%s:%d", nodeHostname, nodePort)
}

// The CloudWatch log group for the EKS cluster logs are created automatically, so we need to separately delete them.
func cleanupClusterLogs(t *testing.T) {
	workingDir := filepath.Join(".", "stages", t.Name())
	uniqueID := test_structure.LoadString(t, workingDir, "uniqueID")
	region := test_structure.LoadString(t, workingDir, "awsRegion")
	logGroupName := fmt.Sprintf("/aws/eks/eks-cluster-%s/cluster", uniqueID)

	logs := aws.NewCloudWatchLogsClient(t, region)
	logs.DeleteLogGroup(&cloudwatchlogs.DeleteLogGroupInput{LogGroupName: awsgo.String(logGroupName)})
}

// The CloudWatch log group for Container Insights are created automatically, so we need to separately delete them.
func cleanupContainerInsightsLogs(t *testing.T) {
	workingDir := filepath.Join(".", "stages", t.Name())
	uniqueID := test_structure.LoadString(t, workingDir, "uniqueID")
	region := test_structure.LoadString(t, workingDir, "awsRegion")
	logGroupName := fmt.Sprintf("/aws/containerinsights/eks-cluster-%s/performance", uniqueID)

	logs := aws.NewCloudWatchLogsClient(t, region)
	logs.DeleteLogGroup(&cloudwatchlogs.DeleteLogGroupInput{LogGroupName: awsgo.String(logGroupName)})
}

func getLogsIfFailed(t *testing.T, workingDir string) {
	if t.Failed() {
		kubectlOptions := test_structure.LoadKubectlOptions(t, workingDir)
		k8s.RunKubectl(t, kubectlOptions, "get", "events", "-n", "kube-system")
	}
}
