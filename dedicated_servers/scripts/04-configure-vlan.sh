#!/bin/bash
# Configure vSwitch VLAN interface on MicroOS
# Required env: SSH_PRIVATE_KEY, SERVER_IP, IDENTITY_FILE_NAME, SSH_PORT, VLAN_SCRIPT
set -e

source "$(dirname "$0")/common.sh"

setup_identity_file

# Wait for server to be available on configured SSH port (5 min timeout)
printf "\n##### Step 1/2: Waiting for server...\n"
wait_for_ssh "$SERVER_IP" "$SSH_PORT" 300

printf "\n##### Step 2/2: Configuring vSwitch VLAN interface...\n"
echo "$VLAN_SCRIPT" | ssh_run_script "$SERVER_IP" "$SSH_PORT" 60

printf "\n##### VLAN configuration complete!\n"
