#!/bin/bash
# Enable rescue mode and trigger hardware reset for dedicated server
# Required env: HROBOT_USERNAME, HROBOT_PASSWORD, SERVER_ID, SSH_FINGERPRINT, RESCUE_BOOT_WAIT
set -e

source "$(dirname "$0")/common.sh"

printf "\n##### Step 1/3: Enabling rescue mode...\n"
RESPONSE=$(hetzner_api POST "/boot/${SERVER_ID}/rescue" \
  -d "os=linux" \
  -d "authorized_key[]=${SSH_FINGERPRINT}")

echo "$RESPONSE"
check_api_response "$RESPONSE"
echo "Rescue mode enabled"

printf "\n##### Step 2/3: Triggering hardware reset...\n"
RESPONSE=$(hetzner_api POST "/reset/${SERVER_ID}" \
  -d "type=hw")

echo "$RESPONSE"
check_api_response "$RESPONSE"
echo "Hardware reset triggered"

printf "\n##### Step 3/3: Waiting for rescue system to boot (${RESCUE_BOOT_WAIT}s)...\n"
sleep "$RESCUE_BOOT_WAIT"
