#!/bin/bash
# Disable Hetzner firewall for dedicated server
# Required env: HROBOT_USERNAME, HROBOT_PASSWORD, SERVER_ID
set -e

source "$(dirname "$0")/common.sh"

echo "Disabling firewall for server ${SERVER_ID}..."

# Hetzner Robot API requires status, whitelist_hos (Hetzner services), and template_id
# Setting whitelist_hos=true and no template (empty rules)
RESPONSE=$(hetzner_api POST "/firewall/${SERVER_ID}" \
  -d "status=disabled" \
  -d "whitelist_hos=true")

echo "$RESPONSE"
check_api_response "$RESPONSE"

echo "Firewall disabled successfully for server ${SERVER_ID}"
