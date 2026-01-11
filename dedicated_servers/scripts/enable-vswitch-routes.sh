#!/bin/bash
# Toggle route exposure to vSwitch for cloud <-> bare metal routing
# This forces Hetzner to re-propagate routes to the vSwitch
# Required for: https://docs.hetzner.com/cloud/networks/connect-dedi-vswitch/
# Required env: HCLOUD_TOKEN, NETWORK_ID
set -e

echo "Toggling expose_routes_to_vswitch on network ${NETWORK_ID}..."

# Step 1: Disable route exposure
echo "Step 1: Disabling expose_routes_to_vswitch..."
RESPONSE=$(curl -s -X PUT \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"expose_routes_to_vswitch": false}' \
  "https://api.hetzner.cloud/v1/networks/${NETWORK_ID}")

echo "$RESPONSE"

if echo "$RESPONSE" | grep -q '"error"'; then
  echo "ERROR: Failed to disable expose_routes_to_vswitch"
  exit 1
fi

# Step 2: Wait for the change to propagate
echo "Step 2: Waiting 30 seconds for route removal to propagate..."
sleep 30

# Step 3: Re-enable route exposure
echo "Step 3: Re-enabling expose_routes_to_vswitch..."
RESPONSE=$(curl -s -X PUT \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"expose_routes_to_vswitch": true}' \
  "https://api.hetzner.cloud/v1/networks/${NETWORK_ID}")

echo "$RESPONSE"

if echo "$RESPONSE" | grep -q '"error"'; then
  echo "ERROR: Failed to re-enable expose_routes_to_vswitch"
  exit 1
fi

# Step 4: Wait for the change to propagate
echo "Step 4: Waiting 30 seconds for route addition to propagate..."
sleep 30

echo "Successfully toggled route exposure to vSwitch"
