package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMergeRoleMapping(t *testing.T) {
	t.Parallel()

	sampleOne := RoleMapping{
		RoleArn:  "asdf",
		Username: "Asdf",
		Groups:   []string{},
	}
	sampleTwo := RoleMapping{
		RoleArn:  "hjkl",
		Username: "Hjkl",
		Groups: []string{
			"system:masters",
			"system:node",
		},
	}
	sampleThree := RoleMapping{
		RoleArn:  "1234",
		Username: "1234",
		Groups: []string{
			"autodeploy",
		},
	}

	testCases := []struct {
		name        string
		mappingA    []RoleMapping
		mappingB    []RoleMapping
		expected    []RoleMapping
		hasConflict bool
	}{
		{
			"mergeEmpty",
			[]RoleMapping{},
			[]RoleMapping{},
			[]RoleMapping{},
			false,
		},
		{
			"mergeEmptyA",
			[]RoleMapping{},
			[]RoleMapping{sampleOne, sampleTwo},
			[]RoleMapping{sampleOne, sampleTwo},
			false,
		},
		{
			"mergeEmptyB",
			[]RoleMapping{sampleOne, sampleTwo},
			[]RoleMapping{},
			[]RoleMapping{sampleOne, sampleTwo},
			false,
		},
		{
			"mergeBoth",
			[]RoleMapping{sampleOne, sampleTwo},
			[]RoleMapping{sampleThree},
			[]RoleMapping{sampleOne, sampleTwo, sampleThree},
			false,
		},
		{
			"hasConflict",
			[]RoleMapping{sampleOne, sampleTwo},
			[]RoleMapping{sampleTwo},
			nil,
			true,
		},
	}

	for _, tc := range testCases {
		// Capture range variable so that it doesn't change as the goroutine swaps contexts across the parallel sub
		// tests.
		tc := tc

		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			mapping, err := mergeRoleMappingLists(tc.mappingA, tc.mappingB)
			if tc.hasConflict {
				assert.Error(t, err)
				assert.Nil(t, mapping)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tc.expected, mapping)
			}
		})
	}
}

func TestMergeUserMapping(t *testing.T) {
	t.Parallel()

	sampleOne := UserMapping{
		UserArn:  "asdf",
		Username: "Asdf",
		Groups:   []string{},
	}
	sampleTwo := UserMapping{
		UserArn:  "hjkl",
		Username: "Hjkl",
		Groups: []string{
			"system:masters",
			"system:node",
		},
	}
	sampleThree := UserMapping{
		UserArn:  "1234",
		Username: "1234",
		Groups: []string{
			"autodeploy",
		},
	}

	testCases := []struct {
		name        string
		mappingA    []UserMapping
		mappingB    []UserMapping
		expected    []UserMapping
		hasConflict bool
	}{
		{
			"mergeEmpty",
			[]UserMapping{},
			[]UserMapping{},
			[]UserMapping{},
			false,
		},
		{
			"mergeEmptyA",
			[]UserMapping{},
			[]UserMapping{sampleOne, sampleTwo},
			[]UserMapping{sampleOne, sampleTwo},
			false,
		},
		{
			"mergeEmptyB",
			[]UserMapping{sampleOne, sampleTwo},
			[]UserMapping{},
			[]UserMapping{sampleOne, sampleTwo},
			false,
		},
		{
			"mergeBoth",
			[]UserMapping{sampleOne, sampleTwo},
			[]UserMapping{sampleThree},
			[]UserMapping{sampleOne, sampleTwo, sampleThree},
			false,
		},
		{
			"hasConflict",
			[]UserMapping{sampleOne, sampleTwo},
			[]UserMapping{sampleTwo},
			nil,
			true,
		},
	}

	for _, tc := range testCases {
		// Capture range variable so that it doesn't change as the goroutine swaps contexts across the parallel sub
		// tests.
		tc := tc

		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			mapping, err := mergeUserMappingLists(tc.mappingA, tc.mappingB)
			if tc.hasConflict {
				assert.Error(t, err)
				assert.Nil(t, mapping)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tc.expected, mapping)
			}
		})
	}
}
