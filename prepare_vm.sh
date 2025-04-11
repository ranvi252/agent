#!/bin/bash

set -e 

# Trap errors
trap 'echo "An error occurred. Exiting..."; exit 1' ERR

# Paths
HOST_PATH="/etc/hosts"
DNS_PATH="/etc/resolv.conf"
SYS_PATH="/etc/sysctl.conf"
PROF_PATH="/etc/profile"
SSH_PATH="/etc/ssh/sshd_config"
FAIL2BAN_JAIL_DIR="fail2ban/jail.d"
FAIL2BAN_SSHD_CONF="$FAIL2BAN_JAIL_DIR/sshd.conf"
COMPASSVPN_LOG_PATH="/var/log/compassvpn/"

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Variable to track OpenVZ detection
IS_OPENVZ=0

# Check Root Function
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Error: You must run this script as root!"
        exit 1
    fi
}

# Check if running on a supported system
check_system() {
    if [ ! -f /etc/os-release ]; then
        echo "Error: Could not detect system type."
        exit 1
    fi

    if ! grep -qi "ubuntu\|debian" /etc/os-release; then
        echo "Error: This script is only supported on Debian/Ubuntu systems."
        exit 1
    fi
}

# Check for OpenVZ virtualization
check_openvz() {
    if [ -f /proc/user_beancounters ]; then
        IS_OPENVZ=1
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "WARNING: OPENVZ DETECTED. THIS VIRTUALIZATION HAS KNOWN LIMITATIONS."
        echo "COMPASSVPN MAY NOT FUNCTION CORRECTLY."
        echo "IT IS RECOMMENDED TO USE OTHER DATACENTERS."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        sleep 3
    fi
}

# Fix Hosts file
fix_etc_hosts() { 
    if [ ! -f "$HOST_PATH" ]; then
        echo "Error: Hosts file not found at $HOST_PATH."
        return 1
    fi

    cp "$HOST_PATH" /etc/hosts.bak
    if [ $? -ne 0 ]; then
        echo "Error: Failed to backup hosts file."
        return 1
    fi

    if ! grep -q "$(hostname)" "$HOST_PATH"; then
        echo "127.0.1.1 $(hostname)" | sudo tee -a "$HOST_PATH" > /dev/null
        echo "Hosts file updated."
    fi
}

# Fix DNS Temporarily
fix_dns() {
    if [ ! -f "$DNS_PATH" ]; then
        echo "Error: resolv.conf file not found at $DNS_PATH."
        return 1
    fi

    cp "$DNS_PATH" /etc/resolv.conf.bak
    if [ $? -ne 0 ]; then
        echo "Error: Failed to backup resolv.conf file."
        return 1
    fi

    # Test DNS servers before applying
    local dns_servers=("1.1.1.2" "1.0.0.2" "127.0.0.53")
    for dns in "${dns_servers[@]}"; do
        if ! ping -c 1 -W 1 "$dns" >/dev/null 2>&1; then
            echo "Warning: DNS server $dns is not responding."
        fi
    done

    sed -i '/nameserver/d' "$DNS_PATH"
    for dns in "${dns_servers[@]}"; do
        echo "nameserver $dns" >> "$DNS_PATH"
    done

    echo "DNS settings updated."
}

# Set the server TimeZone to UTC
set_timezone() {
    if ! command_exists timedatectl; then
        echo "Error: timedatectl command not found."
        return 1
    fi

    sudo timedatectl set-timezone "UTC"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set timezone to UTC."
        return 1
    fi
    echo "Timezone set to UTC."
}

# Update & Install necessary packages
install_base_packages() {
    echo "Installing base packages..."
    apt-get update -qq
    apt-get install -yqq curl wget sudo coreutils iproute2 lsof
    echo "Base packages installed."
}

# SYSCTL Optimization
sysctl_optimizations() {
    if [ "$IS_OPENVZ" -eq 1 ]; then
        echo "Skipping sysctl optimizations due to OpenVZ detection."
        return 0
    fi

    if [ ! -f "$SYS_PATH" ]; then
        echo "Error: sysctl.conf file not found at $SYS_PATH."
        return 1
    fi

    cp "$SYS_PATH" /etc/sysctl.conf.bak
    if [ $? -ne 0 ]; then
        echo "Error: Failed to backup sysctl.conf."
        return 1
    fi

    echo "Optimizing network settings..."
    
    # Remove existing settings
    sed -i -e '/fs.file-max/d' \
        -e '/net.core.default_qdisc/d' \
        -e '/net.core.optmem_max/d' \
        -e '/net.core.rmem_max/d' \
        -e '/net.core.wmem_max/d' \
        -e '/net.ipv4.tcp_congestion_control/d' \
        -e '/net.ipv4.tcp_max_syn_backlog/d' \
        -e '/net.ipv4.tcp_fin_timeout/d' \
        -e '/net.core.netdev_max_backlog/d' \
        -e '/^#/d' \
        -e '/^$/d' \
        "$SYS_PATH"

    # Add new settings
    cat <<EOF >> "$SYS_PATH"
fs.file-max = 67108864
net.core.default_qdisc = fq
net.core.optmem_max = 262144
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_max_syn_backlog = 10240
net.ipv4.tcp_fin_timeout = 25
net.core.netdev_max_backlog = 32768
EOF

    # Apply settings
    sudo sysctl -p >/dev/null 2>&1
    echo "Network settings optimized."
}

# Handle firewalld if installed
handle_firewalld() {
    if command_exists firewall-cmd; then
        echo "Removing firewalld..."
        systemctl stop firewalld
        systemctl disable firewalld
        apt-get purge -y firewalld
    fi
}

# Install UFW if not already installed
install_ufw() {
    if ! command_exists ufw; then
        echo "Installing UFW..."
        apt-get update -qq
        apt-get install -qqy ufw
        
        if ! command_exists ufw; then
            echo "Failed to install UFW."
            exit 1
        fi
    fi
}

# Find SSH port and store it in SSH_PORT variable
find_ssh_port() {
    # Default to port 22
    SSH_PORT=22
    
    if [ -e "$SSH_PATH" ]; then
        PORT_LINE=$(grep -oP '^Port\s+\K\d+' "$SSH_PATH" 2>/dev/null || echo "")
        
        if [ -n "$PORT_LINE" ]; then
            SSH_PORT="$PORT_LINE"
            echo "Detected SSH port: $SSH_PORT"
        fi
    fi
}

# Update fail2ban configuration for SSH
update_fail2ban_ssh() {
    # If SSH port is the default 22, no need to modify fail2ban config
    if [ "$SSH_PORT" = "22" ]; then
        return
    fi
    
    if [ -f "$FAIL2BAN_SSHD_CONF" ]; then
        # File exists, update the port in the action line
        if grep -q "action.*port=" "$FAIL2BAN_SSHD_CONF" >/dev/null 2>&1; then
            # Replace port 22 with the detected port
            sed -i "s/port=\"22\"/port=\"$SSH_PORT\"/g" "$FAIL2BAN_SSHD_CONF" 2>/dev/null
            sed -i "s/port=\"22,/port=\"$SSH_PORT,/g" "$FAIL2BAN_SSHD_CONF" 2>/dev/null
            sed -i "s/,22,/,$SSH_PORT,/g" "$FAIL2BAN_SSHD_CONF" 2>/dev/null
            sed -i "s/,22\"/,$SSH_PORT\"/g" "$FAIL2BAN_SSHD_CONF" 2>/dev/null
        else
            # If no port parameter found in action, add the action line with detected port
            if grep -q "^\[sshd\]" "$FAIL2BAN_SSHD_CONF" >/dev/null 2>&1; then
                # If sshd section exists but no port action
                sed -i "/^\[sshd\]/a action = iptables-multiport[name=sshd, port=\"$SSH_PORT\", protocol=tcp]" "$FAIL2BAN_SSHD_CONF" 2>/dev/null
            fi
        fi
    fi
    echo "Configured fail2ban for SSH port $SSH_PORT"
}

# Optimize UFW configuration
optimize_ufw() {
    if [ -f /etc/default/ufw ]; then
        sed -i 's+/etc/ufw/sysctl.conf+/etc/sysctl.conf+gI' /etc/default/ufw 2>/dev/null
    fi
}

# Configure UFW rules
configure_ufw() {
    # Reset any existing rules
    ufw --force reset >/dev/null 2>&1

    # Set default policies
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    # Allow ports
    ufw allow "$SSH_PORT/tcp" >/dev/null 2>&1
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 443/tcp >/dev/null 2>&1
    ufw allow 443/udp >/dev/null 2>&1
    ufw allow 2053/tcp >/dev/null 2>&1
    ufw allow 2053/udp >/dev/null 2>&1
    ufw allow 8443/tcp >/dev/null 2>&1
    ufw allow 8443/udp >/dev/null 2>&1
    ufw allow 9100/tcp >/dev/null 2>&1
    ufw allow 9100/udp >/dev/null 2>&1

    # Enable UFW
    echo "y" | ufw enable >/dev/null 2>&1
}

# Setup CompassVPN log directory
setup_compassvpn_logs() {
    echo "Setting up CompassVPN log directory..."

    # Create the log directory if it doesn't exist
    if [ ! -d "$COMPASSVPN_LOG_PATH" ]; then
        echo "Creating CompassVPN log directory at $COMPASSVPN_LOG_PATH."
        mkdir -p "$COMPASSVPN_LOG_PATH"
    fi

    # Set appropriate permissions (777 for directory)
    echo "Setting permissions for $COMPASSVPN_LOG_PATH."
    chmod 777 "$COMPASSVPN_LOG_PATH" # Removed trailing dot

    # Set ownership to root:root (standard for system logs)
    echo "Setting ownership for $COMPASSVPN_LOG_PATH."
    chown root:root "$COMPASSVPN_LOG_PATH" # Removed trailing dot

    # Create log files
    echo "Creating log files..."
    touch "$COMPASSVPN_LOG_PATH/nginx_access.log"
    touch "$COMPASSVPN_LOG_PATH/nginx_error.log"
    touch "$COMPASSVPN_LOG_PATH/xray_access.log"
    touch "$COMPASSVPN_LOG_PATH/xray_error.log"
    touch "$COMPASSVPN_LOG_PATH/xray.log"

    # Set log file permissions
    echo "Setting log file permissions to 777..."
    chmod 777 "$COMPASSVPN_LOG_PATH/nginx_access.log"
    chmod 777 "$COMPASSVPN_LOG_PATH/nginx_error.log"
    chmod 777 "$COMPASSVPN_LOG_PATH/xray_access.log"
    chmod 777 "$COMPASSVPN_LOG_PATH/xray_error.log"
    chmod 777 "$COMPASSVPN_LOG_PATH/xray.log"

    echo "CompassVPN log directory and files setup completed successfully."
}

# Process fail2ban filter with NGINX_PATH
process_fail2ban_filter() {
    local filter_file="fail2ban/filter.d/nginx-bad-request.conf"
    local nginx_path
    
    if [ ! -f "$filter_file" ]; then
        echo "Error: nginx-bad-request.conf not found at $filter_file."
        return 1
    fi
    
    # Get NGINX_PATH from env_file
    nginx_path=$(grep -oP '^NGINX_PATH=\K.*' env_file)
    
    if [ -z "$nginx_path" ]; then
        echo "Warning: NGINX_PATH not found in env_file. Using default value."
        nginx_path="default"
    fi
    
    echo "Setting NGINX_PATH to $nginx_path in nginx-bad-request.conf"
    
    # Replace NGINX_PATH in the filter
    sed -i "s|NGINX_PATH|$nginx_path|g" "$filter_file"
}

# Check if required ports are in use
check_required_ports() {
    local ports_to_check=("80" "443" "2053" "8443")
    local conflict_found=0

    echo "Checking required ports: ${ports_to_check[*]}..."

    for port in "${ports_to_check[@]}"; do
        echo "Checking if port $port is in use..."
        # Use ss to check for listening sockets on the current TCP port
        local listening_process
        listening_process=$(ss -tlpn "sport = :$port" | grep LISTEN || true)

        if [ -n "$listening_process" ]; then
            conflict_found=1
            echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            echo "!! ERROR: Port $port is already in use by the following process: "
            # Attempt to extract process information more reliably
            local pid
            pid=$(echo "$listening_process" | grep -oP 'pid=\K\d+')
            if [ -n "$pid" ]; then
                local process_name
                process_name=$(ps -p "$pid" -o comm=)
                echo "!! PID: $pid, Name: $process_name "
            else
                 # Fallback to showing the ss output if PID extraction fails
                echo "!! $listening_process "
            fi
            echo "!! Please stop this process manually before running the script again. "
            echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            exit 1
        fi
    done

    if [ "$conflict_found" -eq 0 ]; then
        echo "All required ports (${ports_to_check[*]}) are free."
    fi
}

# Main execution
echo
echo "Preparing the VM..."
echo

check_root
sleep 0.5

check_system
sleep 0.5

install_base_packages
sleep 0.5

check_openvz
sleep 0.5

check_required_ports
sleep 0.5

fix_etc_hosts
sleep 0.5

fix_dns
sleep 0.5

set_timezone
sleep 0.5

# Conditionally run sysctl optimizations
sysctl_optimizations
sleep 0.5

handle_firewalld
sleep 0.5

install_ufw
sleep 0.5

find_ssh_port
sleep 0.5

update_fail2ban_ssh
sleep 0.5

optimize_ufw
sleep 0.5

configure_ufw
sleep 0.5

setup_compassvpn_logs
sleep 0.5

process_fail2ban_filter
sleep 0.5

echo
echo "VM is ready for bootstraping."
echo
exit 0
