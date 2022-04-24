module github.com/gruntwork-io/terraform-aws-eks/modules/aws-auth-merger/aws-auth-merger

go 1.15

require (
	github.com/gruntwork-io/gruntwork-cli v0.7.0
	github.com/gruntwork-io/terratest v0.40.0
	github.com/hashicorp/golang-lru v0.5.3 // indirect
	github.com/mitchellh/go-homedir v1.1.0
	github.com/sirupsen/logrus v1.8.1
	github.com/stretchr/testify v1.7.0
	github.com/urfave/cli v1.22.2
	gopkg.in/yaml.v2 v2.4.0
	k8s.io/api v0.20.6
	k8s.io/apimachinery v0.20.6
	k8s.io/client-go v0.20.6
	sigs.k8s.io/structured-merge-diff/v4 v4.1.2 // indirect
)
