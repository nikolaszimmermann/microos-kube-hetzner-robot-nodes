#!/bin/bash
# Remove stale k8s node from cluster before starting k3s-agent
# This script runs on MicroOS via SSH
# Variables substituted by terraform templatefile():
#   - server_name, kubeconfig_content
set -e

# Write kubeconfig temporarily
KUBECONFIG_FILE=$(mktemp)
trap "rm -f $KUBECONFIG_FILE" EXIT
cat > "$KUBECONFIG_FILE" << 'KUBECONFIG_EOF'
${kubeconfig_content}
KUBECONFIG_EOF

# Delete existing node if present (ignore errors if not found)
if k3s kubectl --kubeconfig="$KUBECONFIG_FILE" get node "${server_name}" &>/dev/null; then
  echo "Found existing node '${server_name}', deleting..."
  k3s kubectl --kubeconfig="$KUBECONFIG_FILE" delete node "${server_name}" --wait=false
  echo "Node deleted successfully"
else
  echo "No existing node '${server_name}' found, proceeding..."
fi
