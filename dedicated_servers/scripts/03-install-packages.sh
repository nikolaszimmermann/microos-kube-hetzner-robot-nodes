#!/bin/bash
# Install packages on MicroOS
# Required env: SSH_PRIVATE_KEY, SERVER_IP, IDENTITY_FILE_NAME, SSH_PORT,
#               PACKAGES_SCRIPT, NEEDED_PACKAGES, MICROOS_BOOT_WAIT, MICROOS_REBOOT_WAIT
set -e

source "$(dirname "$0")/common.sh"

setup_identity_file

printf "\n##### Step 1/3: Waiting for MicroOS to boot (${MICROOS_BOOT_WAIT}s)...\n"
sleep "$MICROOS_BOOT_WAIT"

# Wait for MicroOS on configured SSH port
wait_for_ssh "$SERVER_IP" "$SSH_PORT" 600 "grep -q MicroOS /etc/os-release"

printf "\n##### Step 2/3: Installing packages...\n"
echo "Packages: ${NEEDED_PACKAGES}"
echo "$PACKAGES_SCRIPT" | ssh_run_script "$SERVER_IP" "$SSH_PORT" 600

printf "\n##### Step 3/3: Waiting for reboot (${MICROOS_REBOOT_WAIT}s)...\n"
sleep "$MICROOS_REBOOT_WAIT"

# Wait for MicroOS to come back up
wait_for_ssh "$SERVER_IP" "$SSH_PORT" 600

printf "\n##### MicroOS package installation complete.\n"
