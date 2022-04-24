package main

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/sirupsen/logrus"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v2"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

func TestGetMainAwsAuthConfigMapNoExist(t *testing.T) {
	// We intentionally run this test serially as we don't want it to conflict with any of the other tests that depend
	// on the main aws-auth configmap existing.

	clientset, err := k8s.GetKubernetesClientE(t)
	require.NoError(t, err)

	authMerger := AwsAuthMerger{clientset: clientset, ctx: context.Background(), logger: logrus.New()}
	configmap, err := authMerger.getMainAwsAuthConfigMap()
	assert.NoError(t, err)
	assert.Nil(t, configmap)
}

// Group of tests that run with the main aws-auth ConfigMap in existence. This test will create the unique main aws-auth
// ConfigMap in the kube-system namespace prior to running each of the sub tests. Any test that depend on the main
// aws-auth ConfigMap should go in here.
func TestWithMainAwsAuthConfigMap(t *testing.T) {
	t.Parallel()

	randomID := random.UniqueId()

	kubectlOptions := k8s.NewKubectlOptions("", "", "")
	namespaceName := fmt.Sprintf("a%s", strings.ToLower(random.UniqueId()))
	defer k8s.DeleteNamespace(t, kubectlOptions, namespaceName)
	k8s.CreateNamespace(t, kubectlOptions, namespaceName)

	clientset, err := k8s.GetKubernetesClientFromOptionsE(t, kubectlOptions)
	require.NoError(t, err)

	defer deleteMainAwsAuthConfigMap(t, clientset)
	newConfigMap := createFakeAwsAuthConfigMap(t, clientset)

	authMerger := AwsAuthMerger{
		namespace: namespaceName,
		autoCreateLabels: map[string]string{
			"gruntwork.io/random-id": randomID,
		},

		clientset: clientset,
		ctx:       context.Background(),
		logger:    logrus.New(),
	}

	// Group the subtests that run in parallel under a serial subtest so that the main test routine waits for all the
	// parallel subtests to finish before proceeding from this line. This ensures that the defer call to delete the main
	// aws-auth configmap doesn't happen until after all the parallel tests finish.
	t.Run("group", func(t *testing.T) {
		// Test that getMainAwsAuthConfigMap returns the main configmap when it exists (we know it exists because it was
		// created in the setup routine above, by the call to createFakeAwsAuthConfigMap).
		t.Run("getMainAwsAuthConfigMap", func(t *testing.T) {
			t.Parallel()
			configmap, err := authMerger.getMainAwsAuthConfigMap()
			require.NoError(t, err)
			require.NotNil(t, configmap)

			assert.Equal(t, sampleMapRolesYaml, configmap.Data[mapRolesKey])
			assert.Equal(t, sampleMapUsersYaml, configmap.Data[mapUsersKey])
		})

		// Test that migratePreExistingConfigMap will snapshot the existing main aws-auth ConfigMap as a new one in the
		// configured namespace.
		t.Run("migrateMainAwsAuthConfigMapUnmanaged", func(t *testing.T) {
			t.Parallel()
			configmap, err := authMerger.migratePreExistingConfigMap()
			require.NoError(t, err)
			require.NotNil(t, configmap)

			assert.True(t, strings.HasPrefix(configmap.Name, preExistingConfigMapCreateName))
			assert.Equal(t, namespaceName, configmap.Namespace)
			assert.Equal(t, randomID, configmap.Labels["gruntwork.io/random-id"])
			assert.Equal(t, sampleMapRolesYaml, configmap.Data[mapRolesKey])
			assert.Equal(t, sampleMapUsersYaml, configmap.Data[mapUsersKey])
		})
	})

	// This test depends on having the custom managedby label on the aws-auth ConfigMap, and it checks that
	// migratePreExistingConfigMap ignores the main aws-auth ConfigMap if it has that label.
	t.Run("migrateMainAwsAuthConfigMapIgnoresManaged", func(t *testing.T) {
		newConfigMap.Labels = map[string]string{managedByLabelKey: managedByLabelValue}
		_, err := clientset.CoreV1().ConfigMaps("kube-system").Update(context.Background(), newConfigMap, metav1.UpdateOptions{})
		require.NoError(t, err)

		configmap, err := authMerger.migratePreExistingConfigMap()
		assert.NoError(t, err)
		assert.Nil(t, configmap)
	})
}

// Test that listAwsAuthConfigMaps will return the list of ConfigMaps that match the label selector in the configured
// namespace by creating a bunch of random, sample configmaps that match that label.
func TestListAwsAuthConfigMaps(t *testing.T) {
	t.Parallel()

	kubectlOptions := k8s.NewKubectlOptions("", "", "")
	namespaceName := fmt.Sprintf("a%s", strings.ToLower(random.UniqueId()))
	defer k8s.DeleteNamespace(t, kubectlOptions, namespaceName)
	k8s.CreateNamespace(t, kubectlOptions, namespaceName)

	clientset, err := k8s.GetKubernetesClientFromOptionsE(t, kubectlOptions)
	require.NoError(t, err)

	randomID := random.UniqueId()
	labels := map[string]string{"gruntwork.io/random-id": randomID}

	authMerger := AwsAuthMerger{
		namespace:     namespaceName,
		labelSelector: fmt.Sprintf("gruntwork.io/random-id=%s", randomID),

		clientset: clientset,
		ctx:       context.Background(),
		logger:    logrus.New(),
	}
	configmaps := createAwsAuthConfigMapDataset(t, clientset, namespaceName, labels)

	nameSet := map[string]bool{}
	for _, cm := range configmaps {
		nameSet[cm.Name] = true
	}

	// Also create a bunch of configmaps that do not match the label set
	createAwsAuthConfigMapDataset(t, clientset, namespaceName, map[string]string{})

	existing, err := authMerger.listAwsAuthConfigMaps()
	require.NoError(t, err)
	existingNameSet := map[string]bool{}
	for _, cm := range existing {
		existingNameSet[cm.Name] = true
	}
	// By doing a equal check with the matched configmaps, we also verify that none of the nomatch configmaps are
	// included.
	assert.Equal(t, nameSet, existingNameSet)
}

func TestMergeAwsAuthConfigMaps(t *testing.T) {
	t.Parallel()

	kubectlOptions := k8s.NewKubectlOptions("", "", "")
	namespaceName := fmt.Sprintf("a%s", strings.ToLower(random.UniqueId()))
	defer k8s.DeleteNamespace(t, kubectlOptions, namespaceName)
	k8s.CreateNamespace(t, kubectlOptions, namespaceName)

	clientset, err := k8s.GetKubernetesClientFromOptionsE(t, kubectlOptions)
	require.NoError(t, err)

	randomID := random.UniqueId()
	labels := map[string]string{"gruntwork.io/random-id": randomID}

	// K8S client-go library create API returns a list of ConfigMap pointers, but our internal functions deal with list
	// of ConfigMap objects, so we need to convert the pointers to objects to pass through to our internal functions.
	configmapPtrs := createAwsAuthConfigMapDataset(t, clientset, namespaceName, labels)
	expectedSources := []string{}
	configmaps := []corev1.ConfigMap{}
	expectedMapRoles := map[string]RoleMapping{}
	expectedMapUsers := map[string]UserMapping{}
	for _, cmPtr := range configmapPtrs {
		configmaps = append(configmaps, *cmPtr)
		expectedSources = append(expectedSources, cmPtr.Name)

		var roleMapping []RoleMapping
		require.NoError(t, yaml.Unmarshal([]byte(cmPtr.Data[mapRolesKey]), &roleMapping))
		rmMap := convertRoleMappingListToMap(roleMapping)
		for key, val := range rmMap {
			expectedMapRoles[key] = val
		}

		var userMapping []UserMapping
		require.NoError(t, yaml.Unmarshal([]byte(cmPtr.Data[mapUsersKey]), &userMapping))
		umMap := convertUserMappingListToMap(userMapping)
		for key, val := range umMap {
			expectedMapUsers[key] = val
		}
	}
	sort.Strings(expectedSources)

	merged, err := mergeAwsAuthConfigMaps(configmaps)
	require.NoError(t, err)

	assert.Equal(t, "aws-auth", merged.Name)
	assert.Equal(t, "kube-system", merged.Namespace)

	var sources []string
	require.NoError(t, json.Unmarshal([]byte(merged.Annotations[sourcesAnnotationKey]), &sources))
	sort.Strings(sources)
	assert.Equal(t, expectedSources, sources)

	var actualRoleMapping []RoleMapping
	require.NoError(t, yaml.Unmarshal([]byte(merged.Data[mapRolesKey]), &actualRoleMapping))
	assert.Equal(t, expectedMapRoles, convertRoleMappingListToMap(actualRoleMapping))

	var actualUserMapping []UserMapping
	require.NoError(t, yaml.Unmarshal([]byte(merged.Data[mapUsersKey]), &actualUserMapping))
	assert.Equal(t, expectedMapUsers, convertUserMappingListToMap(actualUserMapping))
}

func convertRoleMappingListToMap(roleMapping []RoleMapping) map[string]RoleMapping {
	out := map[string]RoleMapping{}
	for _, rm := range roleMapping {
		out[rm.RoleArn] = rm
	}
	return out
}

func convertUserMappingListToMap(userMapping []UserMapping) map[string]UserMapping {
	out := map[string]UserMapping{}
	for _, um := range userMapping {
		out[um.UserArn] = um
	}
	return out
}

// 3 ConfigMaps:
// - 1 role mapping ; no user mapping
// - no role mapping ; 1 user mapping
// - 2 role mappings ; 2 user mapping
func createAwsAuthConfigMapDataset(t *testing.T, clientset *kubernetes.Clientset, namespace string, labels map[string]string) []*corev1.ConfigMap {
	sampleRoleOne := RoleMapping{
		RoleArn:  "asdf",
		Username: "Asdf",
		Groups:   []string{},
	}
	sampleRoleTwo := RoleMapping{
		RoleArn:  "hjkl",
		Username: "Hjkl",
		Groups: []string{
			"system:masters",
			"system:node",
		},
	}
	sampleRoleThree := RoleMapping{
		RoleArn:  "1234",
		Username: "1234",
		Groups: []string{
			"autodeploy",
		},
	}
	sampleUserOne := UserMapping{
		UserArn:  "asdf",
		Username: "Asdf",
		Groups:   []string{},
	}
	sampleUserTwo := UserMapping{
		UserArn:  "hjkl",
		Username: "Hjkl",
		Groups: []string{
			"system:masters",
			"system:node",
		},
	}
	sampleUserThree := UserMapping{
		UserArn:  "1234",
		Username: "1234",
		Groups: []string{
			"autodeploy",
		},
	}
	created := []*corev1.ConfigMap{}

	created = append(
		created,
		createRandomAwsAuthConfigMap(t, clientset, namespace, labels, []RoleMapping{sampleRoleOne}, []UserMapping{}),
		createRandomAwsAuthConfigMap(t, clientset, namespace, labels, []RoleMapping{}, []UserMapping{sampleUserOne}),
		createRandomAwsAuthConfigMap(t, clientset, namespace, labels, []RoleMapping{sampleRoleTwo, sampleRoleThree}, []UserMapping{sampleUserTwo, sampleUserThree}),
	)
	return created
}

func createRandomAwsAuthConfigMap(
	t *testing.T,
	clientset *kubernetes.Clientset,
	namespace string,
	labels map[string]string,
	roleMapping []RoleMapping,
	userMapping []UserMapping,
) *corev1.ConfigMap {
	mapRolesYaml, err := yaml.Marshal(roleMapping)
	require.NoError(t, err)
	mapUsersYaml, err := yaml.Marshal(userMapping)
	require.NoError(t, err)

	randomName := fmt.Sprintf("a%s", strings.ToLower(random.UniqueId()))
	newConfigMap := corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      randomName,
			Namespace: namespace,
			Labels:    labels,
		},
		Data: map[string]string{
			mapRolesKey: string(mapRolesYaml),
			mapUsersKey: string(mapUsersYaml),
		},
	}
	created, err := clientset.CoreV1().ConfigMaps(namespace).Create(context.Background(), &newConfigMap, metav1.CreateOptions{})
	require.NoError(t, err)
	return created
}

func createFakeAwsAuthConfigMap(t *testing.T, clientset *kubernetes.Clientset) *corev1.ConfigMap {
	configmap := corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "aws-auth",
			Namespace: "kube-system",
		},
		Data: map[string]string{
			mapRolesKey: sampleMapRolesYaml,
			mapUsersKey: sampleMapUsersYaml,
		},
	}
	created, err := clientset.CoreV1().ConfigMaps("kube-system").Create(context.Background(), &configmap, metav1.CreateOptions{})
	require.NoError(t, err)
	return created
}

func deleteMainAwsAuthConfigMap(t *testing.T, clientset *kubernetes.Clientset) {
	err := clientset.CoreV1().ConfigMaps("kube-system").Delete(context.Background(), "aws-auth", metav1.DeleteOptions{})
	require.NoError(t, err)
}

const (
	sampleMapRolesYaml = `
- rolearn: arn:aws:iam::111122223333:role/doc-test-nodes-NodeInstanceRole-WDO5P42N3ETB
  username: system:node:{{EC2PrivateDNSName}}
  groups:
    - system:bootstrappers
    - system:nodes
`
	sampleMapUsersYaml = `
- userarn: arn:aws:iam::555555555555:user/admin
  username: admin
  groups:
    - system:masters
- userarn: arn:aws:iam::111122223333:user/ops-user
  username: ops-user
  groups:
    - system:masters
`
)
