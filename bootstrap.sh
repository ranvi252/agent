#!/usr/bin/bash
set -e

source env_file

# Function to check if a command exists
command_not_exists() {
    ! command -v "$1" >/dev/null 2>&1
}

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi
sleep 1

# Prepare the VM
./prepare_vm.sh
sleep 1

# Install Docker
if command_not_exists docker; then
    echo "Docker is not installed"
    curl -fsSL https://get.docker.com | sh
else
    echo "Docker is installed"
fi
sleep 1

file_path="env_file"
if [ -f $file_path ]; then
    echo "'$file_path' exists."
else
    echo "'$file_path' file does not exist. use env_file.example as template"
    exit;
fi
sleep 1

# Generate unique identifier
identifier=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 10)
if [ $? -ne 0 ]; then
    echo "Error: Failed to generate unique identifier."
    exit 1
fi

echo "Creating a new identifier and appending to the env_file..."
echo "" >> ./env_file
echo "IDENTIFIER=$identifier" >> ./env_file
echo "Added identifier: $identifier"

# setup redeploy cron
./setup_cron.sh $REDEPLOY_INTERVAL
sleep 1

docker compose up -d --build
