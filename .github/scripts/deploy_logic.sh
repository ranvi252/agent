#!/bin/bash
# --- Start of Deployment Logic Script ---
# This script is executed by the GitHub Actions runner for each server in the matrix.
# It handles parsing server details, connecting via SSH/SCP, and executing the remote script.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Enable Verbose Debugging if requested ---
if [[ "$DEBUG_LOGS" == "true" ]]; then
  echo "::debug::Enabling verbose script execution (-x) in deploy_logic.sh"
  set -x # Print each command before executing it
fi

# --- Check required environment variables ---
if [[ -z "$SERVER_INDEX" ]]; then echo "::error::SERVER_INDEX env var not set."; exit 1; fi
if [[ -z "$SERVERS_SECRET" ]]; then echo "::error::SERVERS_SECRET env var not set."; exit 1; fi
if [[ -z "$ENV_FILE_CONTENT" ]]; then echo "::warning::ENV_FILE_CONTENT env var not set or is empty. Remote env_file will be empty."; fi
if [[ -z "$GITHUB_REPOSITORY" ]]; then echo "::error::GITHUB_REPOSITORY env var not set."; exit 1; fi
if [[ -z "$GITHUB_REF_NAME" ]]; then echo "::error::GITHUB_REF_NAME env var not set."; exit 1; fi
if [[ -z "$LOCAL_SCRIPT_PATH" ]]; then echo "::error::LOCAL_SCRIPT_PATH env var not set."; exit 1; fi
# SSH_KEY_SECRET can be empty (for password auth)
# DEBUG_LOGS can be empty or false

# --- Determine Authentication Mode ---
AUTH_MODE="password"
if [[ -n "$SSH_KEY_SECRET" ]]; then
  AUTH_MODE="key"
  echo "Using SSH Key authentication via ssh-agent."
else
  echo "Using Password authentication via sshpass."
fi

# --- Get the specific server line for this job instance ---
echo "Processing Server Index: $SERVER_INDEX"
# Use awk to extract the specific line (NR = Number of Record/Row)
line=$(printf "%s" "$SERVERS_SECRET" | awk "NR==${SERVER_INDEX}")
if [[ -z "$line" ]]; then
  echo "::error::Could not extract server line for index $SERVER_INDEX from SERVERS secret."
  exit 1
fi
echo "Processing Server Line (from index $SERVER_INDEX): [$line]" # Log the retrieved line (masked in logs if sensitive)

# --- Prepare and Validate Server Line ---
# Trim leading/trailing whitespace and trailing comma
line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/,$//')
if [[ -z "$line" ]]; then
    echo "::error::Extracted server line for index $SERVER_INDEX is empty after trimming."
    exit 1
fi

# Validate format: user:password@ip or user@ip
if ! echo "$line" | grep -q '@'; then
  echo "::error::Invalid server line format (missing @) for index $SERVER_INDEX: [$line]"
  exit 1
fi

# --- Parse server details ---
ip=$(echo "$line" | sed 's/.*@//')
user_pass=$(echo "$line" | sed 's/@.*//')
user=""
password=""

# Base SSH options (removed -T as -tt is used conditionally later)
ssh_base_options="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Prepare commands based on auth mode
ssh_connect_cmd=""

if [[ "$AUTH_MODE" == "key" ]]; then
  user="$user_pass" # Password part (if present) is ignored
  echo "Attempting key auth for $user@$ip"
  # Key auth doesn't usually need -tt, add -v conditionally
  ssh_verbose_flag=""
  if [[ "$DEBUG_LOGS" == "true" ]]; then ssh_verbose_flag="-v"; fi
  # Add -T to explicitly disable pseudo-terminal allocation for non-interactive script
  ssh_connect_cmd="ssh $ssh_base_options $ssh_verbose_flag -T ${user}@${ip}"
else
  # Password Auth Mode: user:password@ip format expected
  if ! echo "$user_pass" | grep -q ':'; then
    echo "::error::Invalid server line format for password auth (missing : in user:password part) for index $SERVER_INDEX: [$line]"
    exit 1
  fi
  user=$(echo "$user_pass" | cut -d':' -f1)
  password=$(echo "$user_pass" | cut -d':' -f2-)

  if [[ -z "$password" ]]; then
     echo "::error::Empty password found for user $user@$ip (Index: $SERVER_INDEX)"
     exit 1
  fi
  # Export the raw password to the SSHPASS environment variable for sshpass to use
  export SSHPASS="$password"
  # Add -v for verbose SSH output during connection (conditionally)
  # Add -o PreferredAuthentications=password to only attempt password auth
  # Add -e to explicitly use SSHPASS env var for sshpass
  # Use single -t as it seems necessary for auth with sshpass -e here (trying instead of -tt).
  ssh_verbose_flag=""
  if [[ "$DEBUG_LOGS" == "true" ]]; then ssh_verbose_flag="-v"; fi
  ssh_connect_cmd="sshpass -e ssh $ssh_base_options $ssh_verbose_flag -t -o PreferredAuthentications=password ${user}@${ip}"
  # NOTE: We are no longer using scp_cmd or ssh_exec_cmd from previous attempt
fi

# Final validation of extracted user and IP
if [[ -z "$user" ]] || [[ -z "$ip" ]]; then
  echo "::error::Could not extract user or ip from server line for index $SERVER_INDEX: [$line]"
  exit 1
fi

# --- Define paths ---
# REMOTE_SCRIPT_PATH is no longer needed as we pipe the script content
# REMOTE_SCRIPT_PATH="~/remote_script_$RANDOM.sh"

# Verify the local script to be executed exists
if [ ! -f "$LOCAL_SCRIPT_PATH" ]; then
  echo "::error::Local script to execute ($LOCAL_SCRIPT_PATH) not found. Make sure it exists in the repository and the Checkout step ran."
  exit 1
fi

# --- Prepare remote execution arguments ---
# Base64 encode the env_file content for safe transport
ENCODED_ENV_FILE=$(echo "$ENV_FILE_CONTENT" | base64 -w0)

# Quote arguments for remote execution
repo_arg_quoted=$(printf %q "$GITHUB_REPOSITORY")
ref_arg_quoted=$(printf %q "$GITHUB_REF_NAME")
env_file_b64_quoted=$(printf %q "$ENCODED_ENV_FILE")
# Use the DEBUG_LOGS env var directly
debug_flag_quoted=$(printf %q "$DEBUG_LOGS") # Pass 'true' or 'false'

# --- Execute the remote script --- 
# Arguments are already quoted
# Append '; exit $?' to the command to ensure the remote shell exits cleanly
remote_script_execution_command="bash -s -- $repo_arg_quoted $ref_arg_quoted $env_file_b64_quoted $debug_flag_quoted; exit $?"

echo "Executing remote script ($LOCAL_SCRIPT_PATH) via stdin pipe..."
# The SSHPASS variable is exported in this shell's environment if needed.

# Unified execution logic using stdin pipe
if cat "$LOCAL_SCRIPT_PATH" | $ssh_connect_cmd "$remote_script_execution_command"; then
    echo "Successfully executed remote script via stdin on ${user}@${ip}"
else
    echo "::error::Failed executing remote script via stdin on ${user}@${ip}" >&2
    # Unset SSHPASS if it was set (only in password mode)
    if [[ "$AUTH_MODE" == "password" ]]; then unset SSHPASS; fi
    exit 1
fi

# Unset SSHPASS if it was set (only in password mode) - after successful execution
if [[ "$AUTH_MODE" == "password" ]]; then
  unset SSHPASS
fi

# --- Disable verbose debugging if it was enabled ---
if [[ "$DEBUG_LOGS" == "true" ]]; then
  set +x
fi

echo "Deployment logic script finished successfully for server index $SERVER_INDEX."
# --- End of Deployment Logic Script ---
