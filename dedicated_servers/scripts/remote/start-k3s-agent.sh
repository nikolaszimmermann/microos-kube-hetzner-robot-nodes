#!/bin/bash
# Start k3s-agent service on MicroOS and verify cluster join
# This script runs on MicroOS via SSH
# Variables substituted by terraform templatefile():
#   - server_name, kubeconfig_content
set -e

printf "\n##### Step 4.1: Starting k3s-agent service...\n"
systemctl enable k3s-agent
systemctl start k3s-agent

printf "\n##### Step 4.2: Waiting for k3s-agent to be active...\n"
timeout 120 bash -c '
  until systemctl is-active --quiet k3s-agent; do
    echo "Waiting for k3s-agent to start..."
    sleep 5
  done
'
echo "k3s-agent is running!"
systemctl status k3s-agent --no-pager

printf "\n##### Step 4.3: Verifying node joined cluster...\n"
# Write kubeconfig temporarily
KUBECONFIG_FILE=$(mktemp)
trap "rm -f $KUBECONFIG_FILE" EXIT
cat > "$KUBECONFIG_FILE" << 'KUBECONFIG_EOF'
${kubeconfig_content}
KUBECONFIG_EOF

# Wait for node to appear in cluster and become Ready
timeout 180 bash -c "
  until k3s kubectl --kubeconfig='$KUBECONFIG_FILE' get node '${server_name}' 2>/dev/null | grep -q ' Ready'; do
    echo 'Waiting for node ${server_name} to be Ready in cluster...'
    sleep 10
  done
"
echo "Node ${server_name} successfully joined cluster!"
k3s kubectl --kubeconfig="$KUBECONFIG_FILE" get node "${server_name}"
