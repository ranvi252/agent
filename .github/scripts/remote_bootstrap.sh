#!/bin/bash
# --- Start of Remote Script ---
# Executed on the remote server via SSH

# Exit immediately if a command exits with a non-zero status.
set -e
# Print each command before executing it (for debugging).
# set -x # Commented out for production

# Ensure prerequisite commands exist
if ! command -v git &> /dev/null; then echo "::error::git command not found. Install git."; exit 1; fi
if ! command -v base64 &> /dev/null; then echo "::error::base64 command not found. Install base64."; exit 1; fi

# Set PATH explicitly in case the remote non-interactive shell has a minimal one
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin

# Define Repo Details (Read from command-line arguments $1 and $2)
GITHUB_REPOSITORY_ARG="$1"
GITHUB_REF_NAME_ARG="$2"

if [[ -z "$GITHUB_REPOSITORY_ARG" ]] || [[ -z "$GITHUB_REF_NAME_ARG" ]]; then
  echo "::error::Repository name (arg 1) or branch name (arg 2) argument missing."
  exit 1
fi

REPO_URL="https://github.com/${GITHUB_REPOSITORY_ARG}.git"
REPO_NAME=$(basename "${GITHUB_REPOSITORY_ARG}")
REPO_DIR="./$REPO_NAME" # Clone/update into a directory named after the repo
BRANCH_NAME="${GITHUB_REF_NAME_ARG}" # Use the branch passed as an argument

echo "Working with branch: $BRANCH_NAME in dir $REPO_DIR for repo $REPO_URL"

# Always remove the directory if it exists to ensure a fresh clone
echo "Removing existing repository directory $REPO_DIR if it exists..."
rm -rf "$REPO_DIR"

# Always clone the repository
echo "Cloning repository..."
git clone --branch "$BRANCH_NAME" "$REPO_URL" "$REPO_DIR" || { echo "::error::Git clone failed"; exit 1; }
cd "$REPO_DIR" || { echo "::error::Could not cd into $REPO_DIR"; exit 1; }

# Create the env_file using the Base64 encoded content passed as argument $3
ENV_FILE_B64_ARG="$3"
# echo "DEBUG Remote: Received ENV_FILE_B64_ARG length is ${#ENV_FILE_B64_ARG}" # Commented out debug output
echo "Writing env_file..."
if [[ -n "$ENV_FILE_B64_ARG" ]]; then
    # Decode the Base64 argument and write to ./env_file
    printf "%s" "$ENV_FILE_B64_ARG" | base64 -d > ./env_file || { echo "::error::Failed to base64 decode or write env_file"; exit 1; }
    echo "env_file written from argument."
else
    # If the argument was empty (likely because the secret was empty), create an empty file
    echo "::warning::ENV_FILE_B64 argument (arg 3) not set or empty. Creating empty env_file."
    :> ./env_file
fi

# Check for bootstrap.sh, make it executable, and run it
if [ -f ./bootstrap.sh ]; then
  echo "Making bootstrap.sh executable..."
  chmod +x ./bootstrap.sh || { echo "::error::Failed to chmod bootstrap.sh"; exit 1; }
  echo "Running ./bootstrap.sh..."
  # Execute the bootstrap script
  ./bootstrap.sh || { echo "::error::bootstrap.sh failed"; exit 1; }
  echo "bootstrap.sh finished successfully."
else
  # Error if bootstrap.sh is not found in the repository root
  echo "::error::bootstrap.sh not found in $REPO_DIR"; exit 1;
fi
# --- End of Remote Script ---

echo "Remote script completed."
