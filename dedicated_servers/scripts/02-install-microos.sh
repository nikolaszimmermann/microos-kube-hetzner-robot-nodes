#!/bin/bash
# Install MicroOS on dedicated server via rescue mode (kexec + AutoYaST)
# Required env: SSH_PRIVATE_KEY, SERVER_IP, IDENTITY_FILE_NAME,
#               HROBOT_USERNAME, HROBOT_PASSWORD, SERVER_ID, INSTALL_SCRIPT, SSH_PORT
set -e

source "$(dirname "$0")/common.sh"

setup_identity_file

# Wait for rescue SSH to be available (rescue uses port 22)
printf "\n##### Step 1/3: Waiting for rescue SSH to become available...\n"
wait_for_ssh "$SERVER_IP" 22 600 "echo SSH ready"

printf "\n##### Step 2/3: Running kexec installer setup...\n"
# The install script ends with kexec which replaces the kernel and kills SSH.
# We expect the connection to drop - this is normal.
# Use || true to allow the script to continue after SSH disconnect.
echo "$INSTALL_SCRIPT" | ssh_run_script "$SERVER_IP" 22 600 || {
  echo "SSH connection closed (expected - kexec replaces the kernel)"
}

# After kexec, the MicroOS installer boots and runs AutoYaST automatically.
# This takes approximately 5-10 minutes. The system will reboot into
# the installed MicroOS when AutoYaST completes.
# We don't need to disable rescue mode or manual reboot - AutoYaST handles this.

printf "\n##### Step 3/3: Waiting for MicroOS to boot after AutoYaST installation...\n"
printf "This takes approximately 5-10 minutes. AutoYaST will reboot automatically.\n"

# Wait for MicroOS SSH on the configured SSH port (set by AutoYaST)
# Timeout: 600 seconds (10 minutes) to account for AutoYaST installation time
wait_for_ssh "$SERVER_IP" "$SSH_PORT" 600 "cat /etc/os-release | grep -q MicroOS && echo MicroOS ready"

printf "\n##### MicroOS installation complete!\n"
