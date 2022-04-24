package main

import (
	"fmt"
	"strings"

	"github.com/gruntwork-io/gruntwork-cli/errors"
)

type mappingType string

const (
	roleMappingType mappingType = "Role"
	userMappingType             = "User"
)

type RoleMapping struct {
	RoleArn  string   `yaml:"rolearn"`
	Username string   `yaml:"username"`
	Groups   []string `yaml:"groups"`
}

type UserMapping struct {
	UserArn  string   `yaml:"userarn"`
	Username string   `yaml:"username"`
	Groups   []string `yaml:"groups"`
}

// mergeRoleMapping merges the two role mapping lists, using the RoleArn as a key to determine conflicts. This will
// return an error if there is a conflict.
func mergeRoleMappingLists(roleMappingA []RoleMapping, roleMappingB []RoleMapping) ([]RoleMapping, error) {
	seen := map[string]bool{}
	newRoleMapping := []RoleMapping{}
	// Technically, we will want to handle conflicts in each individual list, but that adds complexity to the code. We
	// choose not to handle that situation here by assuming that conflicts scoped within each individual ConfigMap is
	// easier to detect by reading the source creating/managing it.
	for _, roleMapping := range roleMappingA {
		seen[roleMapping.RoleArn] = true
		newRoleMapping = append(newRoleMapping, roleMapping)
	}
	for _, roleMapping := range roleMappingB {
		if _, hasSeen := seen[roleMapping.RoleArn]; hasSeen {
			return nil, errors.WithStackTrace(MappingConflictErr{roleMappingType, roleMapping.RoleArn})
		}
		newRoleMapping = append(newRoleMapping, roleMapping)
	}
	return newRoleMapping, nil
}

// mergeUserMapping merges the two user mapping lists, using the UserArn as a key to determine conflicts. This will
// return an error if there is a conflict.
func mergeUserMappingLists(userMappingA []UserMapping, userMappingB []UserMapping) ([]UserMapping, error) {
	seen := map[string]bool{}
	newUserMapping := []UserMapping{}
	// Technically, we will want to handle conflicts in each individual list, but that adds complexity to the code. We
	// choose not to handle that situation here by assuming that conflicts scoped within each individual ConfigMap is
	// easier to detect by reading the source creating/managing it.
	for _, userMapping := range userMappingA {
		seen[userMapping.UserArn] = true
		newUserMapping = append(newUserMapping, userMapping)
	}
	for _, userMapping := range userMappingB {
		if _, hasSeen := seen[userMapping.UserArn]; hasSeen {
			return nil, errors.WithStackTrace(MappingConflictErr{userMappingType, userMapping.UserArn})
		}
		newUserMapping = append(newUserMapping, userMapping)
	}
	return newUserMapping, nil
}

// Custom error messages

type MappingConflictErr struct {
	mappingType mappingType
	arn         string
}

func (err MappingConflictErr) Error() string {
	return fmt.Sprintf("%v ARN %s is already in the %s mapping list.", err.mappingType, err.arn, strings.ToLower(string(err.mappingType)))
}
