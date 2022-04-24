package main

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/gruntwork-io/gruntwork-cli/errors"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/sirupsen/logrus"
	"gopkg.in/yaml.v2"
	corev1 "k8s.io/api/core/v1"
	k8serrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

const (
	// The namespace and name of the main aws-auth ConfigMap. This should be set to what EKS expects.
	// Refer to https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html
	mainAwsAuthConfigMapNamespace = "kube-system"
	mainAwsAuthConfigMapName      = "aws-auth"

	// These labels are used to indicate if the aws-auth ConfigMap is automatically managed by the merger.
	managedByLabelKey            = "gruntwork.io/managed-by"
	managedByLabelValue          = "aws-auth-merger"
	sourcesAnnotationKey         = "gruntwork.io/aws-auth-merger-sources"
	autoCreateAnnotationKey      = "gruntwork.io/aws-auth-merger-created"
	mergedTimestampAnnotationKey = "gruntwork.io/aws-auth-merger-timestamp"

	// aws-auth ConfigMap data keys
	mapRolesKey = "mapRoles"
	mapUsersKey = "mapUsers"

	preExistingConfigMapCreateName = "preexisting-aws-auth"
)

type AwsAuthMerger struct {
	// Set from CLI
	// Namespace to watch for ConfigMaps to merge.
	namespace string
	// Label Selector to use when looking up ConfigMaps to merge.
	labelSelector string
	// Labels to apply to any ConfigMaps that are autocreated. For example, when there is a manually managed aws-auth
	// ConfigMap that already exists, this tool will automatically migrate that to the merge Namespace so that the
	// preexisting roles and users are included in the final map.
	autoCreateLabels map[string]string
	// How often to poll the Namespace for aws-auth ConfigMaps
	refreshInterval time.Duration

	// K8s auth params
	kubeconfig  string
	kubecontext string

	// Internally set
	logger    *logrus.Logger
	clientset *kubernetes.Clientset
	ctx       context.Context
}

// newK8sClientset returns a Kubernetes API client set that can be used to make API calls to the Kubernetes cluster.
// Uses in-cluster mode if kubeconfig is not set.
func (authMerger *AwsAuthMerger) newK8sClientset() (*kubernetes.Clientset, error) {
	var config *rest.Config
	if authMerger.kubeconfig != "" {
		authMerger.logger.Infof("Kubeconfig is set so will source credentials from kubeconfig %s", authMerger.kubeconfig)

		// Currently this function can be used both for tests and in production, but we need to be careful since this
		// library is from terratest, a library primarily used for writing infrastructure tests.
		rawConfig, err := k8s.LoadApiClientConfigE(authMerger.kubeconfig, authMerger.kubecontext)
		if err != nil {
			return nil, errors.WithStackTrace(err)
		}
		config = rawConfig
	} else {
		authMerger.logger.Info("Kubeconfig is not set so will source credentials from ServiceAccount env vars (in-cluster mode)")

		rawConfig, err := rest.InClusterConfig()
		if err != nil {
			return nil, errors.WithStackTrace(err)
		}
		config = rawConfig
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, errors.WithStackTrace(err)
	}
	return clientset, nil
}

// eventLoop is the main event handler loop. This will start a routine that will:
// - Check and migrate if a manually managed aws-auth ConfigMap exists, so that we don't overwrite it and lose the
//   information.
// - Merge and sync the initial set of aws-auth ConfigMaps in the Namespace.
// - Watch for changes to the aws-auth ConfigMaps in the Namespace and sync everytime a change is detected.
// - Start a polling routine that will sync the ConfigMap even if there was no change.
func (authMerger *AwsAuthMerger) eventLoop() error {
	authMerger.logger = getProjectLogger()
	authMerger.logConfig()

	if err := authMerger.setK8sClientset(); err != nil {
		return err
	}
	authMerger.logger.Info("Successfully authenticated to Kubernetes API")

	configmap, err := authMerger.migratePreExistingConfigMap()
	if err != nil {
		authMerger.logger.Errorf("Error while checking for and migrating a manually configured aws-auth ConfigMap: %s", err)
		return err
	}
	if configmap == nil {
		authMerger.logger.Info("No manually configured aws-auth ConfigMap was detected.")
	} else {
		authMerger.logger.Info("Found existing aws-auth ConfigMap in kube-system namespace.")
		authMerger.logger.Infof("Migrated existing configuration to ConfigMap %s in Namespace %s.", configmap.Name, configmap.Namespace)
	}

	if err := authMerger.syncAwsAuthConfigMaps(); err != nil {
		return err
	}

	// Start the controller in the background to stream watch events. We use an informer instead of a watcher here to
	// ensure we can recover from API based recoverable errors.
	stopChan := make(chan struct{})
	defer close(stopChan)
	notifyChan := make(chan struct{})
	controller := NewConfigMapWatchController(
		authMerger.logger,
		authMerger.clientset,
		authMerger.namespace,
		authMerger.labelSelector,
		notifyChan,
	)
	if err := controller.Run(stopChan); err != nil {
		authMerger.logger.Errorf("Error while setting up watcher for ConfigMaps in Namespace %s and label selector %s", authMerger.namespace, authMerger.labelSelector)
		return err
	}

	// Setup a debouncer for syncing
	authMerger.logger.Infof("Successfully set up watcher for ConfigMaps in Namespace %s and label selector %s", authMerger.namespace, authMerger.labelSelector)
	debouncedSync, syncErrChan := debounceNoArgsFunc(authMerger.logger, 1*time.Second, authMerger.syncAwsAuthConfigMaps)

	// Main handler. This watches for events on the watcher channel, scheduling a call to sync every time an event comes
	// in. Note that we debounce the call so that if there are multiple events that happen concurrently, we don't spam
	// the sync call for every event.
	ticker := time.NewTicker(authMerger.refreshInterval)
	for {
		select {
		// We ignore the items in the watcher channel because the sync call will list the latest data. All we care about here is
		// the notification that something has changed.
		case <-notifyChan:
			authMerger.logger.Infof("Detected change in aws-auth ConfigMaps in Namespace %s and label selector %s", authMerger.namespace, authMerger.labelSelector)
			debouncedSync()
		case tick := <-ticker.C:
			tickUTC := tick.UTC()
			tickUTCStr := tickUTC.Format("2006-01-02T15:04:05Z")
			authMerger.logger.Infof("Refresh interval reached (%s): performing forced sync.", tickUTCStr)
			debouncedSync()
		case err := <-syncErrChan:
			if err != nil {
				return err
			}
		}
	}
}

// setK8sClientset will set the Kubernetes clientset on the AwsAuthMerger object so that API calls can be made.
func (authMerger *AwsAuthMerger) setK8sClientset() error {
	clientset, err := authMerger.newK8sClientset()
	if err != nil {
		return errors.WithStackTrace(err)
	}
	authMerger.clientset = clientset
	authMerger.ctx = context.Background()
	return nil
}

// getMainAwsAuthConfigMap returns the main aws-auth ConfigMap that the EKS cluster uses for role mappings, if it
// exists. This will return nil for the ConfigMap if it does not exist.
func (authMerger *AwsAuthMerger) getMainAwsAuthConfigMap() (*corev1.ConfigMap, error) {
	configmap, err := authMerger.clientset.CoreV1().ConfigMaps(mainAwsAuthConfigMapNamespace).Get(authMerger.ctx, mainAwsAuthConfigMapName, metav1.GetOptions{})
	if err != nil && k8serrors.IsNotFound(err) {
		return nil, nil
	} else if err != nil {
		return nil, errors.WithStackTrace(err)
	}
	return configmap, nil
}

// listAwsAuthConfigMaps will lookup the AWS Auth ConfigMaps that should be merged together.
func (authMerger *AwsAuthMerger) listAwsAuthConfigMaps() ([]corev1.ConfigMap, error) {
	configmapList, err := authMerger.clientset.CoreV1().ConfigMaps(authMerger.namespace).List(authMerger.ctx, metav1.ListOptions{LabelSelector: authMerger.labelSelector})
	if err != nil {
		return nil, errors.WithStackTrace(err)
	}

	allConfigMaps := configmapList.Items
	for configmapList.Continue != "" {
		configmapList, err = authMerger.clientset.CoreV1().ConfigMaps(authMerger.namespace).List(
			authMerger.ctx,
			metav1.ListOptions{LabelSelector: authMerger.labelSelector, Continue: configmapList.Continue},
		)
		if err != nil {
			return nil, errors.WithStackTrace(err)
		}
		allConfigMaps = append(allConfigMaps, configmapList.Items...)

	}
	return allConfigMaps, nil
}

// migratePreExistingConfigMap will migrate an existing manually managed aws-auth ConfigMap to the aws-auth-merger
// Namespace so that it will be included in the final merged version. Returns the new ConfigMap if it was migrated.
func (authMerger *AwsAuthMerger) migratePreExistingConfigMap() (*corev1.ConfigMap, error) {
	mainConfigMap, err := authMerger.getMainAwsAuthConfigMap()
	if err != nil {
		return nil, err
	}
	if mainConfigMap == nil {
		return nil, nil
	}

	if isManagedByMerger(mainConfigMap) {
		return nil, nil
	}

	newConfigMap := corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			// We use GenerateName here instead of Name so that we can get a unique name for the ConfigMap that is
			// unlikely to conflict with those created/managed by users
			GenerateName: preExistingConfigMapCreateName,
			Namespace:    authMerger.namespace,
			Labels:       authMerger.autoCreateLabels,
			Annotations: map[string]string{
				autoCreateAnnotationKey: "true",
			},
		},
		Data: mainConfigMap.Data,
	}
	createdConfigMap, err := authMerger.clientset.CoreV1().ConfigMaps(authMerger.namespace).Create(authMerger.ctx, &newConfigMap, metav1.CreateOptions{})
	if err != nil {
		return nil, errors.WithStackTrace(err)
	}
	return createdConfigMap, nil
}

// syncAwsAuthConfigMaps will lookup all the aws-auth ConfigMaps that should be merged in the configured Namespace,
// merge them, and upsert the main aws-auth ConfigMap in kube-system Namespace.
//
// Note that this currently ignores manual changes made to the central ConfigMap outside of the merger. We intentionally
// do NOT handle this situation to keep the code simple. We can enhance the functionality of the merger in the future if
// this becomes a problem. However, we expect that this is unlikely:
//
// - For manual updates by humans, the work will be lost. This can be a frustrating experience for the user. However,
//   the hope is that users will be encouraged and educated to manage the ConfigMap by code, thereby reducing the risk
//   of out of band updates. This action (making updates manually to the central ConfigMap) will be similar to out of
//   band AWS updates in the console in a terraform managed world, and should be known to cause issues in an IaC centric
//   operation. The hope is that users who are using Gruntwork will already be in an IaC mindset such that it should be
//   rare for the user to manually edit this ConfigMap.
// - For automated updates by EKS, there are several ways this can fail, most notably when adding a Managed Node Group
//   or Fargate profile for the first time after the aws-auth-merger is deployed. EKS will make changes to the central
//   ConfigMap in these scenarios, and those will be lost when the merger syncs the distributed ConfigMaps. To handle
//   this, we recommend users include the Fargate profile execution IAM role and Managed Node Group worker IAM roles in
//   one of the distributed ConfigMaps so that they are merged in and not lost. See
//   core-concepts.md#how-do-i-handle-conflicts-with-automatic-updates-by-eks for more info on this topic.
func (authMerger *AwsAuthMerger) syncAwsAuthConfigMaps() error {
	configmaps, err := authMerger.listAwsAuthConfigMaps()
	if err != nil {
		authMerger.logger.Errorf("Error while looking up aws-auth ConfigMaps in namespace %s with label selector %s", authMerger.namespace, authMerger.labelSelector)
		return err
	}
	authMerger.logger.Infof("Found %d ConfigMaps in namespace %s with label selector %s", len(configmaps), authMerger.namespace, authMerger.labelSelector)

	merged, err := mergeAwsAuthConfigMaps(configmaps)
	if err != nil {
		authMerger.logger.Errorf("Error while merging %d aws-auth ConfigMaps in namespace %s with label selector %s", len(configmaps), authMerger.namespace, authMerger.labelSelector)
		return err
	}
	authMerger.logger.Infof("Successfully merged %d ConfigMaps in namespace %s with label selector %s", len(configmaps), authMerger.namespace, authMerger.labelSelector)

	created, err := authMerger.upsertConfigMap(merged)
	if err != nil {
		authMerger.logger.Error("Error while upserting merged aws-auth ConfigMap in kube-system Namespace.")
		return err
	}
	if created {
		authMerger.logger.Infof("Created new aws-auth ConfigMaps using those in Namespace %s", authMerger.namespace)
	} else {
		authMerger.logger.Infof("Replaced existing aws-auth ConfigMaps using those in Namespace %s", authMerger.namespace)
	}
	return nil
}

// upsertConfigMap will perform an upsert of the given ConfigMap. If the ConfigMap with the name and namespace exists,
// this will update the existing one, while creating if it does not. Returns true if a new one was created.
//
// Note that this upsert is NOT atomic and that is ok. Kubernetes doesn't provide a way to lock objects in the API, nor
// does it provide an atomic upsert API, so this naively does a get call to check for existence, before doing create or
// update. This means that if the ConfigMap is automatically or manually created between the time this routine does a
// get and create, it will fail with an error. This is ok, as the command will ultimately exit in this scenario and
// Kubernetes will restart the Pod, causing it to run the routine from the beginning, in which case it will retry the
// upsert here and correctly update the existing ConfigMap.
func (authMerger *AwsAuthMerger) upsertConfigMap(configmap corev1.ConfigMap) (bool, error) {
	var existing *corev1.ConfigMap
	result, err := authMerger.clientset.CoreV1().ConfigMaps(configmap.Namespace).Get(authMerger.ctx, configmap.Name, metav1.GetOptions{})
	if err != nil && !k8serrors.IsNotFound(err) {
		return false, errors.WithStackTrace(err)
	} else if err == nil {
		existing = result
	} else {
		// This case is when k8serrors.IsNotFound returns true.
		existing = nil
	}

	if existing == nil {
		if _, err := authMerger.clientset.CoreV1().ConfigMaps(configmap.Namespace).Create(authMerger.ctx, &configmap, metav1.CreateOptions{}); err != nil {
			return false, errors.WithStackTrace(err)
		}
		return true, nil
	}

	if _, err := authMerger.clientset.CoreV1().ConfigMaps(configmap.Namespace).Update(authMerger.ctx, &configmap, metav1.UpdateOptions{}); err != nil {
		return false, errors.WithStackTrace(err)
	}
	return false, nil
}

// logConfig will log out settings passed in.
func (authMerger *AwsAuthMerger) logConfig() {
	authMerger.logger.Info("Configured Settings:")
	authMerger.logger.Infof("\tNamespace: %s", authMerger.namespace)
	authMerger.logger.Infof("\tLabel Selector: '%s'", authMerger.labelSelector)
	authMerger.logger.Infof("\tRefresh Interval: %s", authMerger.refreshInterval)
	authMerger.logger.Info("\tAutoCreateLabels:")
	for key, val := range authMerger.autoCreateLabels {
		authMerger.logger.Infof("\t\t%s=%s", key, val)
	}
	authMerger.logger.Info("")
	authMerger.logger.Info("")
}

// mergeAwsAuthConfigMaps will take a list of aws-auth ConfigMaps and merge them together into one. This will return an
// error if there are any conflicts in the roles or users.
func mergeAwsAuthConfigMaps(configmaps []corev1.ConfigMap) (corev1.ConfigMap, error) {
	merged := corev1.ConfigMap{}
	sources := []string{}
	mapRolesMerged := []RoleMapping{}
	mapUsersMerged := []UserMapping{}
	for _, configmap := range configmaps {
		sources = append(sources, configmap.Name)

		currentMapRoles, err := getRoleMappingFromConfigMap(configmap)
		if err != nil {
			return merged, err
		}
		mapRolesMerged, err = mergeRoleMappingLists(mapRolesMerged, currentMapRoles)
		if err != nil {
			return merged, err
		}

		currentMapUsers, err := getUserMappingFromConfigMap(configmap)
		if err != nil {
			return merged, err
		}
		mapUsersMerged, err = mergeUserMappingLists(mapUsersMerged, currentMapUsers)
		if err != nil {
			return merged, err
		}
	}

	// Encode the combined data so that it can be injected into the ConfigMap
	sourcesJson, err := json.Marshal(sources)
	if err != nil {
		return merged, errors.WithStackTrace(err)
	}
	mapRolesYaml, err := yaml.Marshal(mapRolesMerged)
	if err != nil {
		return merged, errors.WithStackTrace(err)
	}
	mapUsersYaml, err := yaml.Marshal(mapUsersMerged)
	if err != nil {
		return merged, errors.WithStackTrace(err)
	}

	currentTime := time.Now().UTC()
	currentTimeStr := currentTime.Format("2006-01-02T15:04:05Z")
	merged.ObjectMeta = metav1.ObjectMeta{
		Name:      mainAwsAuthConfigMapName,
		Namespace: mainAwsAuthConfigMapNamespace,
		Labels: map[string]string{
			managedByLabelKey: managedByLabelValue,
		},
		Annotations: map[string]string{
			sourcesAnnotationKey:         string(sourcesJson),
			mergedTimestampAnnotationKey: currentTimeStr,
		},
	}
	merged.Data = map[string]string{
		mapRolesKey: string(mapRolesYaml),
		mapUsersKey: string(mapUsersYaml),
	}
	return merged, nil
}

// getRoleMappingFromConfigMap will return the role mapping list from the given ConfigMap. This will return an error if
// the mapRoles key does not contain a valid role mapping list schema.
func getRoleMappingFromConfigMap(configmap corev1.ConfigMap) ([]RoleMapping, error) {
	mapRolesRaw, hasMapRoles := configmap.Data[mapRolesKey]
	if !hasMapRoles {
		return []RoleMapping{}, nil
	}

	var currentRoleMapping []RoleMapping
	if err := yaml.Unmarshal([]byte(mapRolesRaw), &currentRoleMapping); err != nil {
		return nil, errors.WithStackTrace(InvalidMappingListErr{roleMappingType, configmap.Name, err})
	}
	return currentRoleMapping, nil
}

// getUserMappingFromConfigMap will return the user mapping list from the given ConfigMap. This will return an error if
// the mapUsers key does not contain a valid user mapping list schema.
func getUserMappingFromConfigMap(configmap corev1.ConfigMap) ([]UserMapping, error) {
	mapUsersRaw, hasMapUsers := configmap.Data[mapUsersKey]
	if !hasMapUsers {
		return []UserMapping{}, nil
	}

	var currentUserMapping []UserMapping
	if err := yaml.Unmarshal([]byte(mapUsersRaw), &currentUserMapping); err != nil {
		return nil, errors.WithStackTrace(InvalidMappingListErr{userMappingType, configmap.Name, err})
	}
	return currentUserMapping, nil
}

// isManagedByMerger returns true if the given ConfigMap is merged by the aws-auth merger, which is determined by
// checking for the managed-by label.
func isManagedByMerger(configmap *corev1.ConfigMap) bool {
	labels := configmap.GetLabels()
	val, hasLabel := labels[managedByLabelKey]
	return hasLabel && val == managedByLabelValue
}

// Custom errors

type InvalidMappingListErr struct {
	mappingType   mappingType
	configMapName string
	underlyingErr error
}

func (err InvalidMappingListErr) Error() string {
	switch err.mappingType {
	case roleMappingType:
		return fmt.Sprintf("Error parsing mapRoles on ConfigMap %s : %s", err.configMapName, err.underlyingErr)
	case userMappingType:
		return fmt.Sprintf("Error parsing mapUsers on ConfigMap %s : %s", err.configMapName, err.underlyingErr)
	default:
		return fmt.Sprintf("Unknown mapping type: %s", err.mappingType)
	}
}
