#!/bin/bash
# Install and configure k3s-agent on MicroOS
# Required env: SSH_PRIVATE_KEY, SERVER_IP, IDENTITY_FILE_NAME, SSH_PORT,
#               K3S_CONFIG, K3S_INSTALL_SCRIPT, CLEANUP_SCRIPT, START_SCRIPT
set -e

source "$(dirname "$0")/common.sh"

setup_identity_file

# Write secrets to temp files and clear env vars to minimize exposure window
# (env vars are visible in /proc/PID/environ)
K3S_CONFIG_FILE=$(write_secret_file "K3S_CONFIG" "k3s-config")

# Wait for server to be available on configured SSH port
printf "\n##### Step 1/4: Waiting for server...\n"
wait_for_ssh "$SERVER_IP" "$SSH_PORT" 300

printf "\n##### Step 2/4: Installing k3s agent...\n"

# Write k3s config file (read from temp file)
ssh_run "$SERVER_IP" "$SSH_PORT" 30 "mkdir -p /etc/rancher/k3s && cat > /etc/rancher/k3s/config.yaml" < "$K3S_CONFIG_FILE"

printf "\n##### Step 2.1: Configuring container registry credentials...\n"
ssh_run "$SERVER_IP" "$SSH_PORT" 30 "cat > /etc/rancher/k3s/registries.yaml" << REGISTRIES_END
mirrors:
  registry.k8s.io:
REGISTRIES_END

printf "\n##### Step 2.2: Installing k3s binary...\n"
echo "$K3S_INSTALL_SCRIPT" | ssh_run_script "$SERVER_IP" "$SSH_PORT" 180

printf "\n##### Step 3/4: Removing stale node from cluster (if exists)...\n"
echo "$CLEANUP_SCRIPT" | ssh_run_script "$SERVER_IP" "$SSH_PORT" 30

printf "\n##### Step 4/4: Starting k3s agent...\n"
echo "$START_SCRIPT" | ssh_run_script "$SERVER_IP" "$SSH_PORT" 180

printf "\n##### Verifying k3s agent...\n"
ssh_run "$SERVER_IP" "$SSH_PORT" 30 'k3s --version'

printf "\n##### K3s agent installation complete!\n"
