#!/bin/bash

clear

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

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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

# Run initial checks
check_root
check_system

# Fix Hosts file
fix_etc_hosts() { 
    if [ ! -f "$HOST_PATH" ]; then
        echo "Error: Hosts file not found at $HOST_PATH."
        return 1
    fi

    cp "$HOST_PATH" /etc/hosts.bak || {
        echo "Error: Failed to backup hosts file."
        return 1
    }

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

    cp "$DNS_PATH" /etc/resolv.conf.bak || {
        echo "Error: Failed to backup resolv.conf file."
        return 1
    }

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

    sudo timedatectl set-timezone "UTC" || {
        echo "Error: Failed to set timezone to UTC."
        return 1
    }
    echo "Timezone set to UTC."
}

# Update & Upgrade & Remove & Clean
complete_update() {
    if ! command_exists apt; then
        echo "Error: apt command not found. This script is for Debian/Ubuntu systems."
        return 1
    fi

    echo "Updating system packages..."
    
    # Update package lists
    sudo apt -q update >/dev/null 2>&1 || {
        echo "Error: Failed to update package lists."
        return 1
    }

    # Upgrade packages
    sudo apt -y upgrade >/dev/null 2>&1 || {
        echo "Error: Failed to upgrade packages."
        return 1
    }

    # Full upgrade
    sudo apt -y full-upgrade >/dev/null 2>&1 || {
        echo "Error: Failed to perform full upgrade."
        return 1
    }

    # Clean up
    sudo apt -y autoremove >/dev/null 2>&1
    sudo apt -y -q autoclean >/dev/null 2>&1
    sudo apt -y clean >/dev/null 2>&1

    echo "System update completed."
}

# SYSCTL Optimization
sysctl_optimizations() {
    if [ ! -f "$SYS_PATH" ]; then
        echo "Error: sysctl.conf file not found at $SYS_PATH."
        return 1
    fi

    cp "$SYS_PATH" /etc/sysctl.conf.bak || {
        echo "Error: Failed to backup sysctl.conf."
        return 1
    }

    echo "Optimizing network settings..."
    
    # Remove existing settings
    sed -i -e '/fs.file-max/d' \
        -e '/net.core.default_qdisc/d' \
        -e '/net.core.optmem_max/d' \
        -e '/net.core.rmem_max/d' \
        -e '/net.core.wmem_max/d' \
        -e '/net.core.rmem_default/d' \
        -e '/net.core.wmem_default/d' \
        -e '/net.ipv4.tcp_rmem/d' \
        -e '/net.ipv4.tcp_wmem/d' \
        -e '/net.ipv4.tcp_congestion_control/d' \
        -e '/net.ipv4.tcp_fin_timeout/d' \
        -e '/net.ipv4.tcp_mem/d' \
        -e '/net.ipv4.udp_mem/d' \
        -e '/net.unix.max_dgram_qlen/d' \
        -e '/^#/d' \
        -e '/^$/d' \
        "$SYS_PATH"

    # Add new settings
    cat <<EOF >> "$SYS_PATH"
# Network Optimization Settings
fs.file-max = 67108864
net.core.default_qdisc = fq
net.core.optmem_max = 262144
net.core.rmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_max = 33554432
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 16384 1048576 33554432
net.ipv4.tcp_wmem = 16384 1048576 33554432
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fin_timeout = 25
net.ipv4.tcp_mem = 65536 1048576 33554432
net.ipv4.udp_mem = 65536 1048576 33554432
net.unix.max_dgram_qlen = 256
EOF

    # Apply settings
    sudo sysctl -p >/dev/null 2>&1 || {
        echo "Error: Failed to apply sysctl settings."
        return 1
    }
    
    echo "Network settings optimized."
}

# System Limits Optimizations
limits_optimizations() {
    if [ ! -f "$PROF_PATH" ]; then
        echo "Error: profile file not found at $PROF_PATH."
        return 1
    fi

    echo "Optimizing system limits..."
    
    # Remove existing limits
    sed -i '/ulimit -c/d' "$PROF_PATH"
    sed -i '/ulimit -d/d' "$PROF_PATH"
    sed -i '/ulimit -f/d' "$PROF_PATH"
    sed -i '/ulimit -i/d' "$PROF_PATH"
    sed -i '/ulimit -l/d' "$PROF_PATH"
    sed -i '/ulimit -m/d' "$PROF_PATH"
    sed -i '/ulimit -n/d' "$PROF_PATH"
    sed -i '/ulimit -q/d' "$PROF_PATH"
    sed -i '/ulimit -s/d' "$PROF_PATH"
    sed -i '/ulimit -t/d' "$PROF_PATH"
    sed -i '/ulimit -u/d' "$PROF_PATH"
    sed -i '/ulimit -v/d' "$PROF_PATH"
    sed -i '/ulimit -x/d' "$PROF_PATH"

    # Add new limits
    cat <<EOF >> "$PROF_PATH"
# System Limits
ulimit -c unlimited
ulimit -d unlimited
ulimit -f unlimited
ulimit -i unlimited
ulimit -l unlimited
ulimit -m unlimited
ulimit -n 1048576
ulimit -q unlimited
ulimit -s -H 65536
ulimit -s 32768
ulimit -t unlimited
ulimit -u unlimited
ulimit -v unlimited
ulimit -x unlimited
EOF

    echo "System limits optimized."
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
            echo "Failed to install UFW. Please check your system."
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
            else
                # If no sshd section, create it
                mkdir -p "$FAIL2BAN_JAIL_DIR" >/dev/null 2>&1
                cat > "$FAIL2BAN_SSHD_CONF" << EOF
[sshd]
enabled = true
filter = sshd
action = iptables-multiport[name=sshd, port="$SSH_PORT", protocol=tcp]
maxretry = 3
findtime = 600
bantime = 86400
EOF
            fi
        fi
    else
        # File doesn't exist, create it with the project's format
        mkdir -p "$FAIL2BAN_JAIL_DIR" >/dev/null 2>&1
        cat > "$FAIL2BAN_SSHD_CONF" << EOF
[sshd]
enabled = true
filter = sshd
action = iptables-multiport[name=sshd, port="$SSH_PORT", protocol=tcp]
maxretry = 3
findtime = 600
bantime = 86400
EOF
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

# Display UFW status
show_ufw_status() {
    echo "UFW status:"
    ufw status
}

# Main execution
echo "Starting system optimization and security configuration..."

# System optimization
{
    fix_etc_hosts || echo "Failed to fix hosts file."
    sleep 0.5
    fix_dns || echo "Failed to fix DNS."
    sleep 0.5
    set_timezone || echo "Failed to set timezone."
    sleep 0.5
    complete_update || echo "Failed to update system."
    sleep 0.5
    sysctl_optimizations || echo "Failed to optimize sysctl."
    sleep 0.5
    limits_optimizations || echo "Failed to optimize system limits."
    sleep 0.5
} || {
    echo "Some system optimization operations failed. Check the logs above for details."
    echo 
    exit 1
}

echo "System optimization completed."
sleep 0.5

# UFW setup
{
    echo "Setting up firewall..."
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
    show_ufw_status
    sleep 0.5
} || {
    echo "Some firewall setup operations failed. Check the logs above for details."
    echo
    exit 1
}

echo "Firewall setup completed."
sleep 0.5

echo "VM is ready for bootstraping."
exit 0
sleep 1
