#!/bin/bash
set -e

# Define SSH configuration path
SSH_PATH="/etc/ssh/sshd_config"
FAIL2BAN_JAIL_DIR="fail2ban/jail.d"
FAIL2BAN_SSHD_CONF="$FAIL2BAN_JAIL_DIR/sshd.conf"

# Define logging function to reduce verbosity
log() {
    echo "$1"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "This script must be run as root."
        exit 1
    fi
}

# Check if the system is Debian/Ubuntu
check_debian_ubuntu() {
    if ! command_exists apt-get; then
        log "This script is intended for Ubuntu/Debian systems only."
        exit 1
    fi
}

# Handle firewalld if installed
handle_firewalld() {
    if command_exists firewall-cmd; then
        log "Removing firewalld..."
        systemctl stop firewalld
        systemctl disable firewalld
        apt-get purge -y firewalld
    fi
}

# Install UFW if not already installed
install_ufw() {
    if ! command_exists ufw; then
        log "Installing UFW..."
        apt-get update -qq
        apt-get install -qqy ufw
        
        if ! command_exists ufw; then
            log "Failed to install UFW. Please check your system."
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
            log "Detected SSH port: $SSH_PORT"
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
    log "Configured fail2ban for SSH port $SSH_PORT"
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
    log "UFW status:"
    ufw status
}

main() {
    log "Setting up firewall..."
    check_root
    sleep 0.5
    check_debian_ubuntu
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
    show_ufw_status
    sleep 0.5
    log "Firewall setup completed."
}

# Execute main function
main 
