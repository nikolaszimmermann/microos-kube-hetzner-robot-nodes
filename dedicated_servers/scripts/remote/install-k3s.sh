#!/bin/bash
# Install k3s agent binary on MicroOS
# This script runs on MicroOS via SSH
# Variables substituted by terraform templatefile():
#   - k3s_channel
set -e

printf "\n##### Step 2.3: Installing k3s agent binary (channel: ${k3s_channel})...\n"
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL='${k3s_channel}' INSTALL_K3S_SKIP_START=true INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC='agent' sh -

printf "\n##### Step 2.4: Restoring SELinux context...\n"
restorecon -v /usr/local/bin/k3s
