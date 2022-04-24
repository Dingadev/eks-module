package main

import (
	"os"
	"strings"
	"time"

	"github.com/gruntwork-io/gruntwork-cli/entrypoint"
	"github.com/gruntwork-io/gruntwork-cli/errors"
	"github.com/gruntwork-io/gruntwork-cli/logging"
	homedir "github.com/mitchellh/go-homedir"
	"github.com/sirupsen/logrus"
	"github.com/urfave/cli"
)

const (
	commandName = "aws-auth-merger"
)

var (
	// CLI meta params
	logLevelFlag = cli.StringFlag{
		Name:  "loglevel",
		Value: logrus.InfoLevel.String(),
		Usage: "Logging verbosity level. Must be one of: trace, debug, info, warn, error, fatal, panic.",
	}

	// merger logic params
	namespaceFlag = cli.StringFlag{
		Name:  "watch-namespace",
		Value: "aws-auth-merger",
		Usage: "Namespace to watch for aws-auth ConfigMaps to merge into the main one.",
	}
	labelSelectorFlag = cli.StringFlag{
		Name:  "watch-label-selector",
		Usage: "Labels to use when collecting aws-auth ConfigMaps to merge. If blank, will use all ConfigMaps in the Namespace.",
	}
	autoCreateLabelsFlag = cli.StringSliceFlag{
		Name:  "autocreate-labels",
		Usage: "Labels to attach to autocreated ConfigMaps in the watch namespace as a key=value pairs. Pass multiple times to assign more than one label. If no value is provided (e.g. --autocreate-labels key), then the label will use empty string for the value.",
	}
	refreshIntervalFlag = cli.DurationFlag{
		Name:  "refresh-interval",
		Value: 5 * time.Minute,
		Usage: "Interval to poll the Namespace for aws-auth ConfigMaps to merge as a duration string (e.g. 5m10s for 5 minutes 10 seconds).",
	}

	// k8s auth params
	kubeconfigPathFlag = cli.StringFlag{
		Name:  "kubeconfig",
		Usage: "Path to the kubeconfig file to use for CLI requests. If unset, will default to ServiceAccount authentication (in-cluster mode)",
	}
	kubeContextFlag = cli.StringFlag{
		Name:  "context",
		Usage: "The name of the kubeconfig context to use. Defaults to the default context set in the kubeconfig.",
	}
)

// initCli initializes the CLI app before any command is actually executed. This function will handle all the setup
// code, such as setting up the logger with the appropriate log level.
func initCli(cliContext *cli.Context) error {
	// Set logging level
	logLevel := cliContext.String(logLevelFlag.Name)
	level, err := logrus.ParseLevel(logLevel)
	if err != nil {
		return errors.WithStackTrace(err)
	}
	logging.SetGlobalLogLevel(level)

	// If logging level is for debugging (debug or trace), enable stacktrace debugging
	if level == logrus.DebugLevel || level == logrus.TraceLevel {
		os.Setenv("GRUNTWORK_DEBUG", "true")
	}
	return nil
}

func newApp() *cli.App {
	entrypoint.HelpTextLineWidth = 120
	app := entrypoint.NewApp()
	app.Name = commandName
	app.Author = "Gruntwork <www.gruntwork.io>"
	cli.AppHelpTemplate = entrypoint.CLI_COMMAND_HELP_TEMPLATE // There are no subcommands, so directly use the command template in the app help
	app.Description = `A Kubernetes app that watches for aws-auth ConfigMaps in a Namespace and merges them into the main aws-auth ConfigMap in the kube-system Namespace.

This will setup a watcher to listen for new and updated aws-auth ConfigMaps and will refresh the ConfigMap as changes are detected. For redundancy and fault tolerance of the event system, this will also periodically refresh the ConfigMap even if no changes are detected.`
	app.Before = initCli
	app.Flags = []cli.Flag{
		logLevelFlag,
		namespaceFlag,
		labelSelectorFlag,
		autoCreateLabelsFlag,
		refreshIntervalFlag,
		kubeconfigPathFlag,
		kubeContextFlag,
	}
	app.Action = errors.WithPanicHandling(awsAuthMerger)
	return app
}

func awsAuthMerger(cliContext *cli.Context) error {
	namespace, err := entrypoint.StringFlagRequiredE(cliContext, namespaceFlag.Name)
	if err != nil {
		return err
	}
	labelSelector := cliContext.String(labelSelectorFlag.Name)
	refreshInterval := cliContext.Duration(refreshIntervalFlag.Name)
	autoCreateLabelsRaw := cliContext.StringSlice(autoCreateLabelsFlag.Name)
	autoCreateLabels := parseLabelsKeyValuePairs(autoCreateLabelsRaw)

	kubeconfigPath := cliContext.String(kubeconfigPathFlag.Name)
	if kubeconfigPath != "" {
		kubeconfigPath, err = homedir.Expand(kubeconfigPath)
		if err != nil {
			return err
		}
	}
	kubeContext := cliContext.String(kubeContextFlag.Name)

	authMerger := AwsAuthMerger{
		namespace:        namespace,
		labelSelector:    labelSelector,
		autoCreateLabels: autoCreateLabels,
		refreshInterval:  refreshInterval,
		kubeconfig:       kubeconfigPath,
		kubecontext:      kubeContext,
	}
	return authMerger.eventLoop()
}

func parseLabelsKeyValuePairs(kvPairs []string) map[string]string {
	out := map[string]string{}
	for _, pair := range kvPairs {
		splitPair := strings.Split(pair, "=")
		key := splitPair[0]
		value := ""
		if len(splitPair) > 1 {
			// If the value contains =, this will split into more than 2, so we join everything but the first element
			// which is the key.
			value = strings.Join(splitPair[1:], "=")
		}
		out[key] = value
	}
	return out
}

// getProjectLogger returns a configured logger for the project that can be used to log messages at various logging
// levels.
func getProjectLogger() *logrus.Logger {
	return logging.GetLogger(commandName)
}
