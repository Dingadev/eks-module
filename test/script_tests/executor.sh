#!/bin/bash
#
# Helper script to support updating python path so that the modules can be loaded properly for testing.
#

set -e

readonly REPO_ROOT="$(git rev-parse --show-toplevel)"
readonly FILEDIR="$(dirname "$0")"

runtests() {
  # This is hard coded to the paths that contain python scripts
  PYTHONPATH="$REPO_ROOT/modules/eks-scripts/bin" tox
}

(cd "${FILEDIR}" && runtests)
