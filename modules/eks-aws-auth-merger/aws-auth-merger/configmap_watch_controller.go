package main

import (
	"fmt"
	"time"

	"github.com/gruntwork-io/gruntwork-cli/errors"
	"github.com/sirupsen/logrus"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/informers"
	coreinformers "k8s.io/client-go/informers/core/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/cache"
)

const (
	resyncTime = time.Hour * 24
)

// ConfigMapWatchController will notify the given channel when ConfigMaps in the provided namespace with the given label
// selector has changed.
type ConfigMapWatchController struct {
	informerFactory   informers.SharedInformerFactory
	configMapInformer coreinformers.ConfigMapInformer
	notifyChan        chan struct{}
	logger            *logrus.Logger
}

// Run starts shared informers and waits for the shared informer cache to synchronize.
func (controller *ConfigMapWatchController) Run(stopChan chan struct{}) error {
	// Starts all the shared informers that have been created by the factory so far.
	controller.informerFactory.Start(stopChan)
	// Wait for the initial synchronization of the local cache.
	if !cache.WaitForCacheSync(stopChan, controller.configMapInformer.Informer().HasSynced) {
		return errors.WithStackTrace(fmt.Errorf("Failed to sync"))
	}
	return nil
}

func (controller *ConfigMapWatchController) configMapAdded(obj interface{}) {
	controller.logger.Debugf("Detected ConfigMap add: %v", obj.(*corev1.ConfigMap))
	controller.notifyChan <- struct{}{}
}

func (controller *ConfigMapWatchController) configMapUpdated(obj, updated interface{}) {
	controller.logger.Debug("Detected ConfigMap update:")
	controller.logger.Debugf("\tOld: %v", obj.(*corev1.ConfigMap))
	controller.logger.Debugf("\tNew: %v", updated.(*corev1.ConfigMap))
	controller.notifyChan <- struct{}{}
}

func (controller *ConfigMapWatchController) configMapDeleted(obj interface{}) {
	controller.logger.Debugf("Detected ConfigMap delete: %v", obj.(*corev1.ConfigMap))
	controller.notifyChan <- struct{}{}
}

func NewConfigMapWatchController(
	logger *logrus.Logger,
	clientset *kubernetes.Clientset,
	namespace string,
	labelSelector string,
	notifyChan chan struct{},
) *ConfigMapWatchController {
	informerFactory := informers.NewSharedInformerFactoryWithOptions(
		clientset,
		resyncTime,
		informers.WithNamespace(namespace),
		informers.WithTweakListOptions(
			func(orig *metav1.ListOptions) {
				orig.LabelSelector = labelSelector
			},
		),
	)
	configMapInformer := informerFactory.Core().V1().ConfigMaps()
	controller := &ConfigMapWatchController{
		informerFactory:   informerFactory,
		configMapInformer: configMapInformer,
		notifyChan:        notifyChan,
		logger:            logger,
	}

	configMapInformer.Informer().AddEventHandler(
		// Your custom resource event handlers.
		cache.ResourceEventHandlerFuncs{
			// Called on creation
			AddFunc: controller.configMapAdded,
			// Called on resource update and every resyncPeriod on existing resources.
			UpdateFunc: controller.configMapUpdated,
			// Called on resource deletion.
			DeleteFunc: controller.configMapDeleted,
		},
	)
	return controller
}
