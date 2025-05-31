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

# --- Check for root privileges ---
if [[ $EUID -ne 0 ]]; then
   echo_content red "This script must be run as root."
   exit 1
fi

# --- Check for Docker installation ---
if ! command -v docker &> /dev/null; then
    echo_content red "Docker is not installed. Please install Docker first."
    echo_content yellow "You can usually install Docker by running: curl -fsSL https://get.docker.com | bash"
    exit 1
fi

echo_content green "---> Checking for existing H UI installation..."

# Check if h-ui container is running/exists
if [[ -z $(docker ps -a -q -f "name=^h-ui$") ]]; then
    echo_content skyBlue "---> H UI container not found, proceeding with fresh installation."
else
    echo_content skyBlue "---> H UI container detected, checking for updates."
    latest_version=$(curl -Ls "https://api.github.com/repos/jonssonyan/h-ui/releases/latest" | grep -oP '"tag_name": "\K[^"]+')
    current_version=$(docker exec h-ui ./h-ui -v 2>/dev/null | sed -n 's/.*version \([^\ ]*\).*/\1/p')

    if [[ "${latest_version}" == "${current_version}" ]]; then
        echo_content skyBlue "---> H UI is already the latest version (${current_version}). Exiting."
        exit 0
    else
        echo_content green "---> New version available (${latest_version}). Upgrading H UI from ${current_version}."
        docker rm -f h-ui || echo_content yellow "Failed to remove existing h-ui container, attempting to proceed."
        docker rmi jonssonyan/h-ui || echo_content yellow "Failed to remove existing h-ui image, attempting to proceed."
    fi
fi

echo_content green "---> Configuring H UI settings..."

read -r -p "Please enter the port of H UI (default: 8081): " h_ui_port
[[ -z "${h_ui_port}" ]] && h_ui_port="8081"
echo_content green "H UI Port set to: ${h_ui_port}"

read -r -p "Please enter the Time zone of H UI (default: Asia/Shanghai): " h_ui_timezone
[[ -z "${h_ui_timezone}" ]] && h_ui_timezone="Asia/Shanghai"
echo_content green "Time Zone set to: ${h_ui_timezone}"

# --- Network Interface Detection (Crucial Fix for venet0) ---
echo_content green "---> Detecting network interface for nftables configuration..."

# This line is the key fix for venet0
# It looks for interfaces starting with 'en', 'eth', or 'venet'
network_interface=$(ls /sys/class/net | grep -E '^en|^eth|^venet' | head -n 1)

if [[ -z "${network_interface}" ]]; then
    echo_content red "Error: No suitable network interface detected (checked for 'en', 'eth', 'venet')."
    echo_content red "Please ensure your VPS has a recognized network adapter."
    echo_content red "Use 'ip a' to verify your network interfaces."
    exit 1
else
    echo_content green "Detected network interface: ${network_interface}"
fi

# --- Check for nftables and configure if needed ---
echo_content green "---> Checking and configuring nftables for H UI..."

if ! command -v nft &> /dev/null; then
    echo_content yellow "nftables is not installed. Attempting to install nftables..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y nftables
    elif command -v yum &> /dev/null; then
        sudo yum install -y nftables
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y nftables
    else
        echo_content red "Could not find a suitable package manager to install nftables. Please install it manually."
        exit 1
    fi
fi

# Ensure nftables service is running and enabled
sudo systemctl enable nftables --now 2>/dev/null || echo_content yellow "Could not enable nftables service, please check manually."

# Define the nftables chain name from the error log
NFT_CHAIN_NAME="hui_porthopping"

# Check if the chain already exists to avoid errors on re-run
if ! sudo nft list chain inet ${NFT_CHAIN_NAME} prerouting &> /dev/null; then
    echo_content skyBlue "Adding nftables chain: ${NFT_CHAIN_NAME}"
    sudo nft add chain inet ${NFT_CHAIN_NAME} prerouting { type nat hook prerouting priority dstnat\; policy accept\; }
    if [[ $? -ne 0 ]]; then
        echo_content red "Error: Failed to add nftables chain '${NFT_CHAIN_NAME}'. Please check nftables configuration manually."
        exit 1
    else
        echo_content green "Successfully added nftables chain."
    fi
else
    echo_content skyBlue "nftables chain '${NFT_CHAIN_NAME}' already exists. Skipping creation."
fi

# You might need to add rules to jump to this chain or specific port forwarding if h-ui requires it.
# The original error was just chain creation, so we focus on that.
# If h-ui actually needs rules that use $network_interface, they would come here.
# Example (hypothetical):
# sudo nft add rule inet ${NFT_CHAIN_NAME} prerouting iifname ${network_interface} tcp dport 8081 counter jump hui_rules

echo_content green "---> Deploying H UI Docker container..."

# Run the H UI Docker container
docker run -d \
    --name h-ui \
    --network host \
    --restart unless-stopped \
    -e PUID=0 -e PGID=0 \
    -e TZ="${h_ui_timezone}" \
    -v /opt/h-ui/config:/config \
    -p "${h_ui_port}":8081 \
    jonssonyan/h-ui:latest

if [[ $? -ne 0 ]]; then
    echo_content red "Error: Failed to start H UI Docker container. Please check Docker logs for 'h-ui'."
    exit 1
else
    echo_content green "H UI deployed successfully!"
    echo_content green "You can access H UI at http://YOUR_VPS_IP:${h_ui_port}"
    echo_content yellow "Please allow a few moments for the container to fully start."
fi

echo_content green "---> Installation/Upgrade complete."
