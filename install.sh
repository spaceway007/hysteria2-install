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
    esal
}

# Function to check for root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo_content red "This script must be run as root."
       exit 1
    fi
}

# Function to check for Docker installation
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo_content red "Docker is not installed. Please install Docker first."
        echo_content yellow "You can usually install Docker by running: curl -fsSL https://get.docker.com | bash"
        exit 1
    fi
}

# Function to get user input for H UI port - MODIFIED DEFAULT TO 8080
get_h_ui_port() {
    read -r -p "Please enter the port for H UI (default: 8080): " h_ui_port_input
    [[ -z "${h_ui_port_input}" ]] && h_ui_port="8080" || h_ui_port="${h_ui_port_input}"
    # Basic port validation
    if ! [[ "${h_ui_port}" =~ ^[0-9]+$ ]] || (( h_ui_port < 1 )) || (( h_ui_port > 65535 )); then
        echo_content red "Invalid port number: ${h_ui_port}. Using default port 8080."
        h_ui_port="8080"
    fi
    echo_content green "H UI Port set to: ${h_ui_port}"
}

# Function to get user input for H UI timezone
get_h_ui_timezone() {
    read -r -p "Please enter the Time zone for H UI (default: Asia/Shanghai): " h_ui_timezone_input
    [[ -z "${h_ui_timezone_input}" ]] && h_ui_timezone="Asia/Shanghai" || h_ui_timezone="${h_ui_timezone_input}"
    echo_content green "Time Zone set to: ${h_ui_timezone}"
}

# Main installation/upgrade logic
install_or_upgrade_h_ui() {
    echo_content green "---> Checking for existing H UI installation..."

    local latest_version=""
    local current_version=""

    # Attempt to fetch latest version from GitHub API
    latest_version=$(curl -Ls "https://api.github.com/repos/jonssonyan/h-ui/releases/latest" | grep -oP '"tag_name": "\K[^"]+' | head -n 1)
    if [[ -z "${latest_version}" ]]; then
        echo_content yellow "Warning: Could not fetch the latest H UI version from GitHub. Proceeding without version check."
        latest_version="unknown" # Set a placeholder if API call fails
    else
        echo_content skyBlue "Latest H UI version available: ${latest_version}"
    fi

    # Check if h-ui container is running/exists
    if docker ps -a -f "name=^h-ui$" &> /dev/null; then
        echo_content skyBlue "---> H UI container detected."
        # Get current running version from the container itself
        current_version=$(docker exec h-ui ./h-ui -v 2>/dev/null | sed -n 's/.*version \([^\ ]*\).*/\1/p')
        if [[ -z "${current_version}" ]]; then
             echo_content yellow "Warning: Could not determine current H UI version. Assuming upgrade is needed."
             current_version="unknown"
        else
            echo_content skyBlue "Current H UI version: ${current_version}"
        fi

        if [[ "${latest_version}" != "unknown" && "${latest_version}" == "${current_version}" ]]; then
            echo_content skyBlue "---> H UI is already the latest version (${current_version}). Exiting."
            exit 0
        else
            echo_content green "---> New version available or current version unknown. Upgrading H UI."
            echo_content yellow "Stopping and removing existing H UI container and image..."
            docker stop h-ui &> /dev/null && docker rm h-ui &> /dev/null || echo_content yellow "Failed to stop/remove old h-ui container. Attempting to proceed."
            docker rmi jonssonyan/h-ui &> /dev/null || echo_content yellow "Failed to remove old h-ui image. Proceeding anyway."
        fi
    else
        echo_content skyBlue "---> H UI container not found, proceeding with fresh installation."
    fi

    echo_content green "---> Configuring H UI settings..."
    get_h_ui_port # Call function to get port (now defaults to 8080)
    get_h_ui_timezone

    # --- Network Interface Detection (For informational purposes, nftables part is removed) ---
    echo_content green "---> Detecting primary network interface..."
    # Robustly detect network interfaces like 'en', 'eth', or 'venet'.
    network_interface=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth|^venet' | head -n 1)

    if [[ -z "${network_interface}" ]]; then
        echo_content yellow "Warning: No common network interface detected (checked for 'en', 'eth', 'venet')."
        echo_content yellow "H UI might still work if your network is configured differently, but please verify with 'ip a'."
    else
        echo_content green "Detected primary network interface: ${network_interface}"
    fi

    # --- nftables configuration section has been removed to bypass OpenVZ kernel limitations ---
    echo_content yellow "---> Skipping nftables configuration due to potential OpenVZ kernel limitations."
    echo_content yellow "If H UI's advanced features (e.g., port hopping) require specific nftables rules, they might not work."
    echo_content yellow "Your existing Hysteria instance (if any) should still function independently."

    echo_content green "---> Deploying H UI Docker container..."

    # Ensure /opt/h-ui/config directory exists for volume mapping
    sudo mkdir -p /opt/h-ui/config || { echo_content red "Error: Failed to create config directory /opt/h-ui/config. Check permissions or disk space."; exit 1; }

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
        echo_content red "Error: Failed to start H UI Docker container."
        echo_content red "Please check Docker logs for 'h-ui' using 'docker logs h-ui'."
        echo_content red "Common issues: Port ${h_ui_port} already in use on host, or insufficient resources."
        exit 1
    else
        echo_content green "H UI deployed successfully!"
        echo_content green "Please allow a few moments for the container to fully start."
        echo_content green "You can access H UI at http://YOUR_VPS_IP:${h_ui_port}"
        echo_content yellow "Remember to replace 'YOUR_VPS_IP' with your actual VPS public IP address."
        echo_content yellow "If you cannot access, check your VPS provider's firewall/security group settings for port ${h_ui_port}."
        echo_content yellow "If you encounter 'not authentication' error after accessing, ensure Hysteria2 backend's authentication matches H UI settings."
    fi

    echo_content green "--- Hysteria UI Installation/Upgrade Complete ---"
}

# --- Script Entry Point ---
check_root
check_docker
install_or_upgrade_h_ui
