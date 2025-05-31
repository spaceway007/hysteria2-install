#!/bin/bash

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_content() {
    local color=$1
    local content=$2
    case "$color" in
        red) echo -e "${RED}${content}${NC}" ;;
        green) echo -e "${GREEN}${content}${NC}" ;;
        yellow) echo -e "${YELLOW}${content}${NC}" ;;
        skyBlue) echo -e "${BLUE}${content}${NC}" ;;
        *) echo -e "${content}" ;; # Default to no color
    esac
}

# --- Configuration ---
HYSTERIA_VERSION="v2.6.1" # 可以根据需要修改为最新版本
HYSTERIA_DIR="/opt/hysteria2"
HYSTERIA_CONFIG_FILE="${HYSTERIA_DIR}/config.json"
HYSTERIA_BINARY="${HYSTERIA_DIR}/hysteria2"
# Default Hysteria2 listening port (服务端实际监听的端口)
HYSTERIA_LISTEN_PORT="443" 
# Port Hopping Range (客户端连接范围，这些端口会被转发到 HYSTERIA_LISTEN_PORT)
PORT_HOPPING_START="20000"
PORT_HOPPING_END="30000"

# --- Functions ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo_content red "This script must be run as root."
       exit 1
    fi
}

install_dependencies() {
    echo_content green "---> Installing dependencies (curl, ca-certificates, iptables-persistent)..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y curl ca-certificates iptables-persistent || { echo_content yellow "Warning: iptables-persistent install failed. Rules might not persist after reboot."; }
    elif command -v yum &> /dev/null; then
        sudo yum install -y curl ca-certificates iptables-services || { echo_content yellow "Warning: iptables-services install failed. Rules might not persist after reboot."; }
        sudo systemctl enable iptables --now
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y curl ca-certificates iptables-services || { echo_content yellow "Warning: iptables-services install failed. Rules might not persist after reboot."; }
        sudo systemctl enable iptables --now
    else
        echo_content red "Unsupported OS for automatic dependency installation. Please install curl and iptables manually."
        exit 1
    fi
    echo_content green "---> Dependencies installed."
}

download_hysteria2() {
    echo_content green "---> Downloading Hysteria2 binary (${HYSTERIA_VERSION})..."
    sudo mkdir -p ${HYSTERIA_DIR} || { echo_content red "Failed to create directory ${HYSTERIA_DIR}."; exit 1; }
    
    local ARCH=""
    case $(uname -m) in
        "x86_64") ARCH="amd64" ;;
        "aarch64") ARCH="arm64" ;;
        "armv7l") ARCH="armv7" ;;
        *) echo_content red "Unsupported architecture: $(uname -m)."; exit 1 ;;
    esac

    local DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${HYSTERIA_VERSION}/hysteria-linux-${ARCH}"
    
    sudo curl -L -o ${HYSTERIA_BINARY} ${DOWNLOAD_URL} || { echo_content red "Failed to download Hysteria2 from ${DOWNLOAD_URL}."; exit 1; }
    sudo chmod +x ${HYSTERIA_BINARY} || { echo_content red "Failed to make Hysteria2 binary executable."; exit 1; }
    echo_content green "---> Hysteria2 binary downloaded and made executable."
}

generate_config() {
    echo_content green "---> Generating Hysteria2 config file..."
    read -r -p "Enter your domain (e.g., example.com) for Hysteria2 TLS (required): " DOMAIN
    if [[ -z "${DOMAIN}" ]]; then
        echo_content red "Domain is required for TLS. Exiting."
        exit 1
    fi

    # Generate a random password for clients
    CLIENT_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16)
    echo_content green "Generated Client Password: ${CLIENT_PASSWORD}"

    # Basic Hysteria2 config with password auth and ACME for TLS
    # Replace the cert/key paths with ACME logic (Let's Encrypt)
    sudo tee ${HYSTERIA_CONFIG_FILE} > /dev/null <<EOF
{
  "listen": ":${HYSTERIA_LISTEN_PORT}",
  "acme": {
    "domains": [
      "${DOMAIN}"
    ],
    "email": "your_email@example.com"  // Please change this email
  },
  "auth": {
    "mode": "password",
    "password": "${CLIENT_PASSWORD}"
  },
  "masquerade": {
    "type": "proxy",
    "proxy": {
      "url": "https://www.baidu.com",  // Default masquerade site
      "rewriteHost": true
    }
  },
  "alpn": "h3",
  "fastOpen": true
}
EOF
    echo_content green "---> Hysteria2 config generated at ${HYSTERIA_CONFIG_FILE}"
    echo_content yellow "Remember to replace 'your_email@example.com' in the config file with your actual email for ACME."
    echo_content yellow "Your Hysteria2 client password is: ${CLIENT_PASSWORD}"
    echo_content yellow "Your Hysteria2 listening port is: ${HYSTERIA_LISTEN_PORT}"
}

configure_firewall() {
    echo_content green "---> Configuring firewall (iptables) for Hysteria2 and port hopping..."

    # Enable IP forwarding
    sudo sysctl -w net.ipv4.ip_forward=1 || { echo_content yellow "Warning: Failed to enable IPv4 forwarding. Traffic might not pass."; }
    echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-ip-forward.conf > /dev/null
    sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf

    # Clear existing iptables rules for simplicity (might affect other services!)
    # echo_content yellow "Warning: Flushing ALL iptables rules. This might disrupt other services!"
    # sudo iptables -F
    # sudo iptables -X
    # sudo iptables -t nat -F
    # sudo iptables -t nat -X
    # sudo iptables -t mangle -F
    # sudo iptables -t mangle -X
    # sudo iptables -t raw -F
    # sudo iptables -t raw -X
    # sudo iptables -P INPUT ACCEPT
    # sudo iptables -P FORWARD ACCEPT
    # sudo iptables -P OUTPUT ACCEPT

    # Allow Hysteria2 listen port (UDP & TCP for QUIC fallback)
    echo_content skyBlue "Allowing Hysteria2 listen port: ${HYSTERIA_LISTEN_PORT} (UDP/TCP)"
    sudo iptables -A INPUT -p udp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT
    sudo iptables -A FORWARD -p udp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT
    sudo iptables -A FORWARD -p tcp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT

    # Allow incoming traffic on port hopping range (UDP & TCP for QUIC fallback)
    echo_content skyBlue "Allowing port hopping range: ${PORT_HOPPING_START}-${PORT_HOPPING_END} (UDP/TCP)"
    sudo iptables -A INPUT -p udp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT
    sudo iptables -A FORWARD -p udp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT
    sudo iptables -A FORWARD -p tcp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT


    # Implement Port Hopping (DNAT) rules for the specified range
    echo_content skyBlue "Configuring iptables DNAT rules for port hopping..."
    # Get the primary IP address of the VPS (using venet0 if available)
    # This is crucial for OpenVZ where IP is bound to venet0
    VPS_IP=$(ip a show venet0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    if [[ -z "${VPS_IP}" ]]; then
        # Fallback if venet0 is not found, try to get from default route
        VPS_IP=$(ip route get 1.1.1.1 | awk '{print $NF}' | head -n 1)
    fi

    if [[ -z "${VPS_IP}" ]]; then
        echo_content red "Error: Could not determine VPS public IP address for NAT rules. Manual intervention required."
        exit 1
    else
        echo_content green "Detected VPS IP for NAT: ${VPS_IP}"
    fi

    # DNAT rule for UDP
    sudo iptables -t nat -A PREROUTING -p udp -m udp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j DNAT --to-destination ${VPS_IP}:${HYSTERIA_LISTEN_PORT}
    # DNAT rule for TCP
    sudo iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j DNAT --to-destination ${VPS_IP}:${HYSTERIA_LISTEN_PORT}

    # SNAT/MASQUERADE rule for outgoing traffic (essential for forwarding)
    echo_content skyBlue "Configuring iptables MASQUERADE for outgoing traffic..."
    sudo iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE || sudo iptables -t nat -A POSTROUTING -o $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | head -n 1) -j MASQUERADE

    # Save iptables rules to ensure persistence after reboot
    echo_content green "---> Saving iptables rules..."
    if command -v netfilter-persistent &> /dev/null; then
        sudo netfilter-persistent save
    elif command -v iptables-save &> /dev/null; then
        sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
        # For CentOS/RHEL with iptables-services
        if command -v systemctl &> /dev/null && systemctl is-active iptables &> /dev/null; then
             sudo systemctl enable iptables --now
        fi
    else
        echo_content yellow "Warning: Could not find tool to save iptables rules. Rules might not persist after reboot."
    fi
    echo_content green "---> Firewall configuration complete."
}

setup_systemd_service() {
    echo_content green "---> Setting up Systemd service for Hysteria2..."
    sudo tee /etc/systemd/system/hysteria2.service > /dev/null <<EOF
[Unit]
Description=Hysteria2 Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${HYSTERIA_DIR}
ExecStart=${HYSTERIA_BINARY} -c ${HYSTERIA_CONFIG_FILE} server
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload || { echo_content red "Failed to reload systemd daemon."; exit 1; }
    sudo systemctl enable hysteria2 || { echo_content red "Failed to enable hysteria2 service."; exit 1; }
    sudo systemctl start hysteria2 || { echo_content red "Failed to start hysteria2 service. Check logs: journalctl -u hysteria2 -f"; exit 1; }
    echo_content green "---> Hysteria2 Systemd service created and started."
    echo_content green "You can check service status with: sudo systemctl status hysteria2"
    echo_content green "You can view logs with: sudo journalctl -u hysteria2 -f"
}

# --- Main Script Execution ---
check_root
install_dependencies
download_hysteria2
generate_config # This step will prompt for domain and display client password
configure_firewall # This will set up iptables rules for port hopping
setup_systemd_service

echo_content green "==================================================="
echo_content green "Hysteria2 Installation Complete!"
echo_content green "Server IP: Your VPS Public IP (e.g., from ip a)"
echo_content green "Listen Port: ${HYSTERIA_LISTEN_PORT}"
echo_content green "Port Hopping Range: ${PORT_HOPPING_START}-${PORT_HOPPING_END}"
echo_content green "Client Password: ${CLIENT_PASSWORD}" # This variable comes from generate_config
echo_content green "Domain: ${DOMAIN}"
echo_content green "==================================================="
echo_content green "Please ensure your VPS provider's firewall/security groups allow TCP/UDP traffic on:"
echo_content green "- Port ${HYSTERIA_LISTEN_PORT}"
echo_content green "- Ports ${PORT_HOPPING_START}-${PORT_HOPPING_END} (for port hopping)"
echo_content green "The ACME (Let's Encrypt) certificate issuance might take a moment to complete after service start."
echo_content green "If the service fails, check 'sudo journalctl -u hysteria2 -f' for logs."
