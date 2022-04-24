package test

import (
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/elb"
	terraAws "github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/logger"
)

// continuouslyWatchPods will continuously log a bunch of information in the background about the kubernetes state in
// the nginx service deployment namespace. This will NOT cause the test to fail if it encounters any errors, as it is
// there purely for debuggability.
// Specifically, this will log:
// - Information about the deployed pods
// - Information about the currently hooked worker nodes
// - What the desired capacity of the ASG is
// - What the current capacity of the ASG is
// - All the registered instances to the ELB and their state
// - All the private hostnames registered to the ELB
func continuouslyWatchPods(
	t *testing.T,
	options *k8s.KubectlOptions,
	region string,
	asgNames []string,
	stopChecking <-chan bool,
	sleepBetweenChecks time.Duration,
	verbose bool,
) *sync.WaitGroup {
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			select {
			case <-stopChecking:
				logger.Log(t, "Got signal to stop watching pods.\n")
				return
			case <-time.After(sleepBetweenChecks):
				logKubernetesInfo(t, options)
				if verbose {
					logVerboseKubernetesInfo(t, options)
				}
				for _, asgName := range asgNames {
					logAsgInfo(t, region, asgName)
				}
				logElbInfo(t, region, options)
			}
		}
	}()
	return &wg
}

func logKubernetesInfo(t *testing.T, options *k8s.KubectlOptions) {
	err := k8s.RunKubectlE(t, options, "get", "pods", "-o", "wide")
	if err != nil {
		logger.Log(t, "WARNING: error getting pod info")
	}
	err = k8s.RunKubectlE(t, options, "get", "nodes", "-o", "wide")
	if err != nil {
		logger.Log(t, "WARNING: error getting nodes")
	}
}

func logVerboseKubernetesInfo(t *testing.T, options *k8s.KubectlOptions) {
	oldNamespace := options.Namespace
	options.Namespace = "kube-system"
	err := k8s.RunKubectlE(t, options, "get", "pods", "-o", "wide")
	if err != nil {
		logger.Log(t, "WARNING: error getting pod info in system namespace")
	}
	options.Namespace = oldNamespace
	err = k8s.RunKubectlE(t, options, "describe", "pods")
	if err != nil {
		logger.Log(t, "WARNING: error getting detailed pod info")
	}
	err = k8s.RunKubectlE(t, options, "get", "endpoints", "nginx-service")
	if err != nil {
		logger.Log(t, "WARNING: error getting endpoints")
	}
}

func logAsgInfo(t *testing.T, region string, asgName string) {
	capacityInfo, err := terraAws.GetCapacityInfoForAsgE(t, asgName, region)
	if err != nil {
		logger.Logf(t, "WARNING: error getting ASG %s capacity info in debugger: %s", asgName, err)
		return
	}
	logger.Logf(t, "ASG (%s) desired capacity: %d", asgName, capacityInfo.DesiredCapacity)
	logger.Logf(t, "ASG (%s) current capacity: %d", asgName, capacityInfo.CurrentCapacity)
}

type ELBInstanceInfo struct {
	InstanceId      string
	InstanceState   string
	PrivateHostname string
}

func logElbInfo(t *testing.T, region string, options *k8s.KubectlOptions) {
	elbName, err := GetLoadBalancerNameFromService(t, options, "nginx-service")
	if err != nil {
		logger.Logf(t, "WARNING: error getting service name in debugger: %s", err)
		return
	}

	instanceIds, err := GetRegisteredInstanceIdsFromElbE(t, region, elbName)
	if err != nil {
		logger.Logf(t, "WARNING: error getting instance ids for lb %s in debugger: %s", elbName, err)
		return
	}

	instanceInfo, err := getInstanceInfo(t, region, elbName, instanceIds)
	if err != nil {
		logger.Logf(t, "WARNING: error getting instance info for lb %s in debugger: %s", elbName, err)
		return
	}

	for _, info := range instanceInfo {
		logger.Logf(t, "ELB instance (%s); state - %s; hostname %s", info.InstanceId, info.InstanceState, info.PrivateHostname)
	}
}

func getInstanceInfo(
	t *testing.T,
	region string,
	elbName string,
	instanceIds []string,
) ([]ELBInstanceInfo, error) {
	instanceStates, err := GetElbHealthStatusForInstancesE(t, region, elbName, instanceIds)
	if err != nil {
		logger.Logf(t, "WARNING: error getting instance health in debugger: %s", err)
		return nil, err
	}
	privateHostnames, err := terraAws.GetPrivateHostnamesOfEc2InstancesE(t, instanceIds, region)
	if err != nil {
		logger.Logf(t, "WARNING: error getting private hostnames in debugger: %s", err)
		return nil, err
	}
	out := []ELBInstanceInfo{}
	for idx, instanceId := range instanceIds {
		out = append(out, ELBInstanceInfo{
			InstanceId:      instanceId,
			InstanceState:   instanceStates[idx],
			PrivateHostname: privateHostnames[instanceId],
		})
	}
	return out, nil
}

// GetElbHealthStatusForInstancesE returns the health check status of the attached instances with respect to the
// provided ELB name.
func GetElbHealthStatusForInstancesE(t *testing.T, region string, elbName string, instanceIds []string) ([]string, error) {
	elbClient, err := NewElbClientE(t, region)
	if err != nil {
		return nil, err
	}

	instances := []*elb.Instance{}
	for _, instanceId := range instanceIds {
		instances = append(instances, &elb.Instance{InstanceId: aws.String(instanceId)})
	}

	params := &elb.DescribeInstanceHealthInput{
		Instances:        instances,
		LoadBalancerName: aws.String(elbName),
	}
	resp, err := elbClient.DescribeInstanceHealth(params)
	if err != nil {
		return nil, err
	}

	out := []string{}
	for _, state := range resp.InstanceStates {
		out = append(out, *state.Description)
	}
	return out, nil
}

// GetRegisteredInstanceIdsFromElbE returns the instance ids of all the instances registered to the provided elb.
func GetRegisteredInstanceIdsFromElbE(t *testing.T, region string, elbName string) ([]string, error) {
	elbClient, err := NewElbClientE(t, region)
	if err != nil {
		return nil, err
	}
	resp, err := elbClient.DescribeLoadBalancers(&elb.DescribeLoadBalancersInput{LoadBalancerNames: []*string{aws.String(elbName)}})
	if err != nil {
		return nil, err
	}
	out := []string{}
	for _, inst := range resp.LoadBalancerDescriptions[0].Instances {
		out = append(out, *inst.InstanceId)
	}
	return out, nil
}

// NewElbClientE creates an Auto Scaling Group client.
func NewElbClientE(t *testing.T, region string) (*elb.ELB, error) {
	sess, err := terraAws.NewAuthenticatedSession(region)
	if err != nil {
		return nil, err
	}
	return elb.New(sess), nil
}

// GetLoadBalancerNameFromService will return the name of the LoadBalancer given a Kubernetes service object
func GetLoadBalancerNameFromService(t *testing.T, options *k8s.KubectlOptions, serviceName string) (string, error) {
	service, err := k8s.GetServiceE(t, options, serviceName)
	if err != nil {
		return "", err
	}
	loadbalancerInfo := service.Status.LoadBalancer.Ingress
	if len(loadbalancerInfo) == 0 {
		return "", fmt.Errorf("Loadbalancer for service %s is not ready", service.Name)
	}
	loadbalancerHostname := loadbalancerInfo[0].Hostname

	// TODO: When expanding to GCP, update this logic

	// For ELB, the subdomain will be NAME-TIME
	loadbalancerHostnameSubDomain := strings.Split(loadbalancerHostname, ".")[0]
	loadbalancerHostnameSubDomainParts := strings.Split(loadbalancerHostnameSubDomain, "-")
	if len(loadbalancerHostnameSubDomainParts) != 2 {
		return "", fmt.Errorf("Unexpected format for loadbalancer hostname %s", loadbalancerHostname)
	}
	return loadbalancerHostnameSubDomainParts[0], nil
}
