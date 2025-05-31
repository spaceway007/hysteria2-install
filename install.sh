#!/bin/bash

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print content with color
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
HYSTERIA_VERSION="v2.6.1" # Hysteria2 binary version
HYSTERIA_DIR="/opt/hysteria2" # Installation directory
HYSTERIA_CONFIG_FILE="${HYSTERIA_DIR}/config.json" # Config file path
HYSTERIA_BINARY_NAME="hysteria2" # Binary filename
HYSTERIA_BINARY_PATH="${HYSTERIA_DIR}/${HYSTERIA_BINARY_NAME}" # Full binary path

# Default Hysteria2 listening port (服务端实际监听的端口)
HYSTERIA_LISTEN_PORT="443" 

# Port Hopping Range (客户端连接范围，这些端口会被转发到 HYSTERIA_LISTEN_PORT)
# You will be prompted to confirm/change these.
DEFAULT_HOPPING_START="20000"
DEFAULT_HOPPING_END="30000"
PORT_HOPPING_START=""
PORT_HOPPING_END=""

# --- Functions ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo_content red "This script must be run as root."
       exit 1
    fi
}

install_dependencies() {
    echo_content green "---> Installing dependencies (curl, ca-certificates, iptables-persistent/iptables-services)..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y curl ca-certificates iptables-persistent || { echo_content yellow "Warning: iptables-persistent install failed. Rules might not persist after reboot."; }
    elif command -v yum &> /dev/null; then
        sudo yum install -y curl ca-certificates iptables-services || { echo_content yellow "Warning: iptables-services install failed. Rules might not persist after reboot."; }
        sudo systemctl enable iptables --now 2>/dev/null || echo_content yellow "Warning: Failed to enable iptables service for persistence.";
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y curl ca-certificates iptables-services || { echo_content yellow "Warning: iptables-services install failed. Rules might not persist after reboot."; }
        sudo systemctl enable iptables --now 2>/dev/null || echo_content yellow "Warning: Failed to enable iptables service for persistence.";
    else
        echo_content red "Unsupported OS for automatic dependency installation. Please install curl and iptables manually."
        exit 1
    fi
    echo_content green "---> Dependencies installed."
}

download_hysteria2() {
    echo_content green "---> Downloading Hysteria2 binary (${HYSTERIA_VERSION})..."
    sudo mkdir -p ${HYSTERIA_DIR} || { echo_content red "Failed to create directory ${HYSTERIA_DIR}. Check permissions or disk space."; exit 1; }
    
    local ARCH=""
    local UNAME_M=$(uname -m)

    case "${UNAME_M}" in
        "x86_64") ARCH="amd64" ;;
        "aarch64") ARCH="arm64" ;;
        "armv7l") ARCH="armv7" ;;
        "i386"|"i686") ARCH="386" ;;
        *) echo_content red "Unsupported architecture: ${UNAME_M}. Please check Hysteria releases for compatible binaries."; exit 1 ;;
    esac

    local DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${HYSTERIA_VERSION}/hysteria-linux-${ARCH}"
    
    # Download the binary
    sudo curl -L -o ${HYSTERIA_BINARY_PATH} ${DOWNLOAD_URL} || { echo_content red "Failed to download Hysteria2 from ${DOWNLOAD_URL}. Check URL or network."; exit 1; }
    
    # Verify the downloaded file is an executable (ELF format)
    if ! file ${HYSTERIA_BINARY_PATH} | grep -q "ELF"; then
        echo_content red "Error: Downloaded file is not a valid executable for your system. It might be corrupted or for a wrong architecture."
        echo_content red "Your detected architecture: ${UNAME_M}, Script attempted to download: hysteria-linux-${ARCH}"
        echo_content red "Please check Hysteria's GitHub releases page to confirm binary naming for your architecture: https://github.com/apernet/hysteria/releases"
        sudo rm -f ${HYSTERIA_BINARY_PATH} # Clean up corrupted file
        exit 1
    fi

    sudo chmod +x ${HYSTERIA_BINARY_PATH} || { echo_content red "Failed to make Hysteria2 binary executable."; exit 1; }
    echo_content green "---> Hysteria2 binary downloaded and made executable."
}

get_user_config() {
    echo_content green "---> Gathering Hysteria2 configuration details..."

    read -r -p "Enter your domain (e.g., example.com) for Hysteria2 TLS (required): " DOMAIN
    if [[ -z "${DOMAIN}" ]]; then
        echo_content red "Domain is required for TLS. Exiting."
        exit 1
    fi

    read -r -p "Enter your email for Let's Encrypt certificates (e.g., your@example.com, required): " EMAIL
    if [[ -z "${EMAIL}" ]]; then
        echo_content red "Email is required for Let's Encrypt. Exiting."
        exit 1
    fi

    read -r -p "Enter Hysteria2 server listening port (default: ${HYSTERIA_LISTEN_PORT}): " listen_port_input
    [[ -z "${listen_port_input}" ]] || HYSTERIA_LISTEN_PORT="${listen_port_input}"
    if ! [[ "${HYSTERIA_LISTEN_PORT}" =~ ^[0-9]+$ ]] || (( HYSTERIA_LISTEN_PORT < 1 )) || (( HYSTERIA_LISTEN_PORT > 65535 )); then
        echo_content red "Invalid listening port. Using default ${HYSTERIA_LISTEN_PORT}."
        HYSTERIA_LISTEN_PORT="443"
    fi
    echo_content green "Hysteria2 listening port set to: ${HYSTERIA_LISTEN_PORT}"


    read -r -p "Enter port hopping START port (default: ${DEFAULT_HOPPING_START}): " hopping_start_input
    [[ -z "${hopping_start_input}" ]] && PORT_HOPPING_START="${DEFAULT_HOPPING_START}" || PORT_HOPPING_START="${hopping_start_input}"
    
    read -r -p "Enter port hopping END port (default: ${DEFAULT_HOPPING_END}): " hopping_end_input
    [[ -z "${hopping_end_input}" ]] && PORT_HOPPING_END="${DEFAULT_HOPPING_END}" || PORT_HOPPING_END="${hopping_end_input}"

    if ! [[ "${PORT_HOPPING_START}" =~ ^[0-9]+$ ]] || ! [[ "${PORT_HOPPING_END}" =~ ^[0-9]+$ ]] || (( PORT_HOPPING_START < 1 )) || (( PORT_HOPPING_END > 65535 )) || (( PORT_HOPPING_START >= PORT_HOPPING_END )); then
        echo_content red "Invalid port hopping range. Using default ${DEFAULT_HOPPING_START}-${DEFAULT_HOPPING_END}."
        PORT_HOPPING_START="${DEFAULT_HOPPING_START}"
        PORT_HOPPING_END="${DEFAULT_HOPPING_END}"
    fi
    echo_content green "Port hopping range set to: ${PORT_HOPPING_START}-${PORT_HOPPING_END}"

    # Generate a random password for clients
    CLIENT_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16)
    echo_content green "Generated Client Password: ${CLIENT_PASSWORD}"
}

generate_config_file() {
    echo_content green "---> Generating Hysteria2 config file..."
    
    sudo tee ${HYSTERIA_CONFIG_FILE} > /dev/null <<EOF
{
  "listen": ":${HYSTERIA_LISTEN_PORT}",
  "acme": {
    "domains": [
      "${DOMAIN}"
    ],
    "email": "${EMAIL}"
  },
  "auth": {
    "mode": "password",
    "password": "${CLIENT_PASSWORD}"
  },
  "masquerade": {
    "type": "proxy",
    "proxy": {
      "url": "https://www.baidu.com",  // Default masquerade site, can be changed
      "rewriteHost": true
    }
  },
  "alpn": "h3",
  "fastOpen": true
}
EOF
    echo_content green "---> Hysteria2 config generated at ${HYSTERIA_CONFIG_FILE}"
}

configure_firewall() {
    echo_content green "---> Configuring firewall (iptables) for Hysteria2 and port hopping..."
    echo_content yellow "Warning: iptables rules for port hopping depend on OpenVZ kernel compatibility."
    echo_content yellow "If Hysteria2 cannot connect, firewall rules might be the issue."

    # Enable IP forwarding (crucial for proxy)
    sudo sysctl -w net.ipv4.ip_forward=1 || { echo_content yellow "Warning: Failed to enable IPv4 forwarding. Traffic might not pass."; }
    echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-ip-forward.conf > /dev/null
    sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf

    # Get the primary IP address of the VPS for DNAT
    # Prioritize venet0 as it's an OpenVZ environment
    local VPS_PUBLIC_IP=$(ip a show venet0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    if [[ -z "${VPS_PUBLIC_IP}" ]]; then
        # Fallback if venet0 not found or no IP, try getting from default route
        VPS_PUBLIC_IP=$(ip route get 1.1.1.1 | awk '{print $NF}' | head -n 1)
    fi

    if [[ -z "${VPS_PUBLIC_IP}" ]]; then
        echo_content red "Error: Could not determine VPS public IP address for NAT rules. Manual intervention required."
        echo_content red "Please set MASQUERADE and DNAT rules manually if this script fails here."
        exit 1
    else
        echo_content green "Detected VPS Public IP for NAT: ${VPS_PUBLIC_IP}"
    fi

    # --- Clear specific existing iptables rules for this setup to avoid conflicts ---
    echo_content yellow "Warning: Removing existing iptables rules related to Hysteria2 setup to avoid conflicts."
    # Flush existing Hysteria2 related rules if they exist
    sudo iptables -t nat -D PREROUTING -p udp -m udp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j DNAT --to-destination ${VPS_PUBLIC_IP}:${HYSTERIA_LISTEN_PORT} 2>/dev/null
    sudo iptables -t nat -D PREROUTING -p tcp -m tcp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j DNAT --to-destination ${VPS_PUBLIC_IP}:${HYSTERIA_LISTEN_PORT} 2>/dev/null
    sudo iptables -t nat -D POSTROUTING -o venet0 -j MASQUERADE 2>/dev/null || sudo iptables -t nat -D POSTROUTING -o $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | head -n 1) -j MASQUERADE 2>/dev/null

    sudo iptables -D INPUT -p udp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT 2>/dev/null
    sudo iptables -D INPUT -p tcp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT 2>/dev/null
    sudo iptables -D INPUT -p udp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT 2>/dev/null
    sudo iptables -D INPUT -p tcp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT 2>/dev/null
    sudo iptables -D FORWARD -p udp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT 2>/dev/null
    sudo iptables -D FORWARD -p tcp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT 2>/dev/null
    sudo iptables -D FORWARD -p udp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT 2>/dev/null
    sudo iptables -D FORWARD -p tcp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT 2>/dev/null


    # --- Add new iptables rules ---
    echo_content skyBlue "Adding iptables rules for Hysteria2 and port hopping..."

    # Allow Hysteria2 listen port (UDP & TCP for QUIC fallback) in INPUT and FORWARD chains
    sudo iptables -A INPUT -p udp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT
    sudo iptables -A FORWARD -p udp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT
    sudo iptables -A FORWARD -p tcp --dport ${HYSTERIA_LISTEN_PORT} -j ACCEPT

    # Allow incoming traffic on port hopping range (UDP & TCP for QUIC fallback) in INPUT and FORWARD chains
    sudo iptables -A INPUT -p udp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT
    sudo iptables -A FORWARD -p udp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT
    sudo iptables -A FORWARD -p tcp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j ACCEPT

    # Implement Port Hopping (DNAT) rules for the specified range
    echo_content skyBlue "Configuring iptables DNAT rules for port hopping..."
    sudo iptables -t nat -A PREROUTING -p udp -m udp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j DNAT --to-destination ${VPS_PUBLIC_IP}:${HYSTERIA_LISTEN_PORT}
    sudo iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${PORT_HOPPING_START}:${PORT_HOPPING_END} -j DNAT --to-destination ${VPS_PUBLIC_IP}:${HYSTERIA_LISTEN_PORT}

    # SNAT/MASQUERADE rule for outgoing traffic (essential for forwarding)
    echo_content skyBlue "Configuring iptables MASQUERADE for outgoing traffic..."
    # Prioritize venet0 as it's an OpenVZ environment
    if ip a show venet0 &> /dev/null; then
        sudo iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
    else
        # Fallback to eth/enX interfaces
        local OUT_INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | head -n 1)
        if [[ -n "${OUT_INTERFACE}" ]]; then
            sudo iptables -t nat -A POSTROUTING -o ${OUT_INTERFACE} -j MASQUERADE
        else
            echo_content yellow "Warning: Could not determine primary outgoing interface for MASQUERADE. Please configure manually if needed."
            echo_content yellow "Skipping MASQUERADE rule. Network forwarding might fail."
        fi
    fi

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
ExecStart=${HYSTERIA_BINARY_PATH} -c ${HYSTERIA_CONFIG_FILE} server
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

echo_content green "--- Starting Hysteria2 Installation for OpenVZ with Port Hopping ---"

# Step 1: Install Dependencies
install_dependencies

# Step 2: Download Hysteria2 Binary
download_hysteria2

# Step 3: Get User Configuration Details
get_user_config # This step will prompt for domain, email, ports, and generate client password

# Step 4: Generate Hysteria2 Config File
generate_config_file

# Step 5: Configure Firewall (iptables for port hopping)
configure_firewall

# Step 6: Setup Systemd Service
setup_systemd_service

echo_content green "==================================================="
echo_content green "Hysteria2 Installation Complete!"
echo_content green "Please allow a few minutes for ACME (Let's Encrypt) certificate issuance to complete."
echo_content green "If service fails, check 'sudo journalctl -u hysteria2 -f' for logs."
echo_content green ""
echo_content skyBlue "--- Your Hysteria2 Client Configuration Details ---"
echo_content green "Server Domain: ${DOMAIN}"
echo_content green "Listen Port: ${HYSTERIA_LISTEN_PORT}"
echo_content green "Client Password: ${CLIENT_PASSWORD}"
echo_content green "Port Hopping Range (Client connects to any of these): ${PORT_HOPPING_START}-${PORT_HOPPING_END}"
echo_content green "--- IMPORTANT: Ensure your VPS provider's firewall/security groups allow traffic on:"
echo_content green "- TCP/UDP Port ${HYSTERIA_LISTEN_PORT}"
echo_content green "- TCP/UDP Ports ${PORT_HOPPING_START}-${PORT_HOPPING_END}"
echo_content green "==================================================="
