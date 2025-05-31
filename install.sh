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
    case "<span class="math-inline">color" in
red\) echo \-e "</span>{RED}<span class="math-inline">\{content\}</span>{NC}" ;;
        green) echo -e "<span class="math-inline">\{GREEN\}</span>{content}<span class="math-inline">\{NC\}" ;;
yellow\) echo \-e "</span>{YELLOW}<span class="math-inline">\{content\}</span>{NC}" ;;
        skyBlue) echo -e "<span class="math-inline">\{BLUE\}</span>{content}<span class="math-inline">\{NC\}" ;;
\*\) echo \-e "</span>{content}" ;; # Default to no color
    esac
}

# Function to check for root privileges
check_root() {
    if [[ <span class="math-inline">EUID \-ne 0 \]\]; then
echo\_content red "This script must be run as root\."
exit 1
fi
\}
\# Function to check for Docker installation
check\_docker\(\) \{
if \! command \-v docker &\> /dev/null; then
echo\_content red "Docker is not installed\. Please install Docker first\."
echo\_content yellow "You can usually install Docker by running\: curl \-fsSL https\://get\.docker\.com \| bash"
exit 1
fi
\}
\# Function to get user input for H UI port
get\_h\_ui\_port\(\) \{
read \-r \-p "Please enter the port for H UI \(default\: 8081\)\: " h\_ui\_port\_input
\[\[ \-z "</span>{h_ui_port_input}" ]] && h_ui_port="8081" || h_ui_port="<span class="math-inline">\{h\_ui\_port\_input\}"
\# Basic port validation
if \! \[\[ "</span>{h_ui_port}" =~ ^[0-9]+$ ]] || (( h_ui_port < 1 )) || (( h_ui_port > 65535 )); then
        echo_content red "Invalid port number: ${h_ui_port}. Using default port 8081."
        h_ui_port="8081"
    fi
    echo_content green "H UI Port set to: <span class="math-inline">\{h\_ui\_port\}"
\}
\# Function to get user input for H UI timezone
get\_h\_ui\_timezone\(\) \{
read \-r \-p "Please enter the Time zone for H UI \(default\: Asia/Shanghai\)\: " h\_ui\_timezone\_input
\[\[ \-z "</span>{h_ui_timezone_input}" ]] && h_ui_timezone="Asia/Shanghai" || h_ui_timezone="${h_ui_timezone_input}"
    echo_content green "Time Zone set to: <span class="math-inline">\{h\_ui\_timezone\}"
\}
\# Main installation/upgrade logic
install\_or\_upgrade\_h\_ui\(\) \{
echo\_content green "\-\-\-\> Checking for existing H UI installation\.\.\."
local latest\_version\=""
local current\_version\=""
\# Attempt to fetch latest version from GitHub API
\# Using a more robust way to get the latest tag name
latest\_version\=</span>(curl -Ls "https://api.github.com/repos/jonssonyan/h-ui/releases/latest" | grep -oP '"tag_name": "\K[^"]+' | head -n 1)
    if [[ -z "${latest_version}" ]]; then
        echo_content yellow "Warning: Could not fetch the latest H UI version from GitHub. Proceeding without version check."
        latest_version="unknown" # Set a placeholder
    else
        echo_content skyBlue "Latest H UI version available: <span class="math-inline">\{latest\_version\}"
fi
\# Check if h\-ui container is running/exists
if docker ps \-a \-f "name\=^h\-ui</span>" &> /dev/null; then
        echo_content skyBlue "---> H UI container detected."
        # Get current running version from the container itself
        current_version=<span class="math-inline">\(docker exec h\-ui \./h\-ui \-v 2\>/dev/null \| sed \-n 's/\.\*version \\\(\[^\\ \]\*\\\)\.\*/\\1/p'\)
if \[\[ \-z "</span>{current_version}" ]]; then
             echo_content yellow "Warning: Could not determine current H UI version. Assuming upgrade is needed."
             current_version="unknown"
        else
            echo_content skyBlue "Current H UI version: <span class="math-inline">\{current\_version\}"
fi
if \[\[ "</span>{latest_version}" != "unknown" && "<span class="math-inline">\{latest\_version\}" \=\= "</span>{current_version}" ]]; then
            echo_content skyBlue "---> H UI is already the latest version (<span class="math-inline">\{current\_version\}\)\. Exiting\."
exit 0
else
echo\_content green "\-\-\-\> New version available or current version unknown\. Upgrading H UI\."
echo\_content yellow "Stopping and removing existing H UI container and image\.\.\."
docker stop h\-ui &\> /dev/null && docker rm h\-ui &\> /dev/null \|\| echo\_content yellow "Failed to stop/remove old h\-ui container\. Attempting to proceed\."
docker rmi jonssonyan/h\-ui &\> /dev/null \|\| echo\_content yellow "Failed to remove old h\-ui image\. Proceeding anyway\."
fi
else
echo\_content skyBlue "\-\-\-\> H UI container not found, proceeding with fresh installation\."
fi
echo\_content green "\-\-\-\> Configuring H UI settings\.\.\."
get\_h\_ui\_port
get\_h\_ui\_timezone
\# \-\-\- Network Interface Detection \(For informational purposes, nftables part is removed\) \-\-\-
echo\_content green "\-\-\-\> Detecting primary network interface\.\.\."
\# Robustly detect network interfaces like 'en', 'eth', or 'venet'\.
network\_interface\=</span>(ip -o link show | awk -F': ' '{print <span class="math-inline">2\}' \| grep \-E '^en\|^eth\|^venet' \| head \-n 1\)
if \[\[ \-z "</span>{network_interface}" ]]; then
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
    sudo mkdir -p /opt/h-ui/config
