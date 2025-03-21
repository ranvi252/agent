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

# Set up UFW firewall
echo "Preparing the VM..."
./prepare_vm.sh
sleep 1


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

identifier=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 10)

echo "creating a new identifier and append to the env_file"
echo "IDENTIFIER=$identifier" >> ./env_file

# setup redeploy cron
./setup_cron.sh $REDEPLOY_INTERVAL
sleep 1

docker compose up -d --build
