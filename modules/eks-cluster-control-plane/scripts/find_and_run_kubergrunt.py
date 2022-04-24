""" Find and run kubergrunt with passed in arguments

This script searches for the current installation of kubergrunt in order to run it with the same args passed into
the caller of this script and forwarded to this script.
E.g. The eks-cluster-control-plane module calls this script with arguments after `--` in order to cleanup resources
when destroying the EKS cluster.

This script first looks for kubergrunt in the install_dir where the eks-cluster-control-plane module installs it,
which is within modules/eks-cluster-control-plane/kubergrunt-installation/. If it's not there, it searches for
kubergrunt in the system PATH.

If no kubergrunt is found, it exits with an error detailing how to get kubergrunt installed.

If it finds kubergrunt, it checks the version is >= 0.6.5; otherwise, it exits with an error detailing how to get
the right version of kubergrunt installed.

If all is good, it spawns a kubergrunt process forwarding it the args passed into this script.

Note that this should maximize platform portability, meaning that:
- Only the stdlib is available.
- Should work with various python versions (2.7, 3.5+).
"""

from __future__ import print_function
from distutils.version import LooseVersion
import distutils.spawn
import logging
import os
import subprocess
import sys

# Set up a logger
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

# Set some variables
minimum_kubergrunt_version = '0.6.9'
dir_path = os.path.dirname(os.path.realpath(__file__))
kubergrunt_install_path = '../kubergrunt-installation/kubergrunt'
executable_path = ''
error = [
    '',
    'ERROR: Failed to find a usable Kubergrunt!',
    '',
    'Kubergrunt ~{} is required to handle various EKS cleanup tasks.'.format(minimum_kubergrunt_version),
    'Normally it is installed when running `terraform plan` using this module.',
    'Do one of the following:',
    '* Re-run `terraform plan` with var.auto_install_kubergrunt and var.use_kubergrunt_verification enabled.',
    '* Run `gruntwork-install --binary-name "kubergrunt" --repo "https://github.com/gruntwork-io/kubergrunt" --tag "v{}"`.'
    .format(minimum_kubergrunt_version),
    '* Download and install it manually from https://github.com/gruntwork-io/kubergrunt.',
    '',
    'Exiting.',
]

# Find kubergrunt. Prefer using the one installed in the hardcoded dir
if os.path.isfile(os.path.join(dir_path, kubergrunt_install_path)):
    executable_path = os.path.join(dir_path, kubergrunt_install_path)
else:
    executable_path = distutils.spawn.find_executable('kubergrunt')

# If kubergrunt not found, exit
if not executable_path:
    print(os.linesep.join(error), file=sys.stderr)
    sys.exit(1)

# Check the version of kubergrunt
version = subprocess.check_output([executable_path, '--version']).decode('utf-8').strip().rsplit(' v', 1)[1]

# If kubergrunt too old, exit
if LooseVersion(version) < LooseVersion(minimum_kubergrunt_version):
    print(os.linesep.join(error))
    sys.exit(1)

# Call kubergrunt with args and hand off the process
process_args = sys.argv[2:]
process_args.insert(0, executable_path)

# Use os.execvp instead of subprocess.call so that we replace the current process with the new one.
# This behaves as if we spawned kubergrunt, and the exit code will naturally mirror kubergrunt.
os.execvp(executable_path, process_args)
