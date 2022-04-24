#!/usr/bin/env bash
#
# Script used by gruntwork-install to install the eks-scripts module.

set -e

readonly DEFAULT_DESTINATION_DIR="/usr/local/bin"

# Locate the directory in which this script is located
readonly script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Move the bin files into DEFAULT_DESTINATION_DIR
sudo cp "$script_path/bin/map-ec2-tags-to-node-labels" "$DEFAULT_DESTINATION_DIR"

# Change ownership and permissions
sudo chmod +x "$DEFAULT_DESTINATION_DIR/map-ec2-tags-to-node-labels"
