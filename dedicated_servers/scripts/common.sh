#!/bin/bash
# Common functions for dedicated server provisioning scripts
# Source this file: source "$(dirname "$0")/common.sh"

# SSH options to suppress warnings and use only identity file
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o LogLevel=ERROR"

# Track temp files for cleanup
TEMP_SECRET_FILES=()

# Cleanup function to remove all temp secret files
cleanup_secret_files() {
  for f in "${TEMP_SECRET_FILES[@]}"; do
    rm -f "$f" 2>/dev/null || true
  done
}

# Write secret from env var to temp file with secure permissions
# Clears the env var after writing to minimize exposure window
# Usage: SECRET_FILE=$(write_secret_file "ENV_VAR_NAME")
# Args: env_var_name [filename_prefix]
write_secret_file() {
  local env_var_name=$1
  local prefix=${2:-secret}
  local value="${!env_var_name}"

  if [ -z "$value" ]; then
    echo "ERROR: Environment variable $env_var_name is not set" >&2
    return 1
  fi

  local temp_file
  temp_file=$(mktemp "/tmp/${prefix}.XXXXXX")
  install -m 600 /dev/null "$temp_file"
  echo "$value" > "$temp_file"
  TEMP_SECRET_FILES+=("$temp_file")

  # Clear the env var to minimize exposure window
  unset "$env_var_name"

  echo "$temp_file"
}

# Setup SSH identity file from environment variable
# Required env: SSH_PRIVATE_KEY, IDENTITY_FILE_NAME
# Note: SSH_PRIVATE_KEY is cleared after writing to reduce exposure
setup_identity_file() {
  IDENTITY_FILE="/tmp/${IDENTITY_FILE_NAME}"
  install -m 600 /dev/null "$IDENTITY_FILE"
  echo "$SSH_PRIVATE_KEY" > "$IDENTITY_FILE"
  TEMP_SECRET_FILES+=("$IDENTITY_FILE")

  # Clear the env var to minimize exposure (visible in /proc/PID/environ)
  unset SSH_PRIVATE_KEY

  # Set trap to clean up all secret files on exit
  trap cleanup_secret_files EXIT
}

# Wait for SSH to become available
# Args: host port [timeout_sec] [check_cmd]
wait_for_ssh() {
  local host=$1
  local port=$2
  local timeout_sec=${3:-600}
  local check_cmd=${4:-"true"}

  echo "Waiting for SSH on ${host}:${port}..."
  timeout "$timeout_sec" bash -c "
    until ssh $SSH_OPTS -o ConnectTimeout=5 -i '$IDENTITY_FILE' -p $port root@$host '$check_cmd' >/dev/null 2>&1; do
      sleep 15
    done
  "
  echo "SSH is available!"
}

# Run command on remote host via SSH
# Args: host port timeout_sec command...
ssh_run() {
  local host=$1
  local port=$2
  local timeout_sec=$3
  shift 3

  timeout "$timeout_sec" ssh $SSH_OPTS \
    -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
    -i "$IDENTITY_FILE" -p "$port" "root@$host" "$@"
}

# Run script on remote host via SSH (reads from stdin)
# Args: host port timeout_sec
ssh_run_script() {
  local host=$1
  local port=$2
  local timeout_sec=$3

  timeout "$timeout_sec" ssh $SSH_OPTS \
    -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
    -i "$IDENTITY_FILE" -p "$port" "root@$host" 'bash -s'
}

# Call Hetzner Robot API
# Required env: HROBOT_USERNAME, HROBOT_PASSWORD
# Args: method endpoint [curl_args...]
hetzner_api() {
  local method=$1
  local endpoint=$2
  shift 2

  curl -s --user "${HROBOT_USERNAME}:${HROBOT_PASSWORD}" \
    -X "$method" \
    "https://robot-ws.your-server.de${endpoint}" "$@"
}

# Check Hetzner API response for errors
# Args: response
check_api_response() {
  local response=$1
  if echo "$response" | grep -q '"error"'; then
    echo "ERROR: API call failed"
    echo "$response"
    return 1
  fi
  return 0
}
