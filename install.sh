#!/usr/bin/env bash

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# System Required: CentOS 7+/Ubuntu 18+/Debian 10+
# Version: v0.0.1
# Description: One click Install Hysteria2 Panel server
# Author: jonssonyan <https://jonssonyan.com>
# Github: https://github.com/jonssonyan/h-ui

ECHO_TYPE="echo -e"

REGEX_VERSION="^v([0-9]{1,}\.){2}[0-9]{1,}$"

random_6_characters() {
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 6
}

yellow() {
    ${ECHO_TYPE} "\\033[33m$1\\033[0m"
}

green() {
    ${ECHO_TYPE} "\\033[32m$1\\033[0m"
}

red() {
    ${ECHO_TYPE} "\\033[31m$1\\033[0m"
}

skyBlue() {
    ${ECHO_TYPE} "\\033[36m$1\\033[0m"
}

echo_content() {
    case $1 in
    "red")
        ${ECHO_TYPE} "\\033[31m$2\\033[0m"
        ;;
    "green")
        ${ECHO_TYPE} "\\033[32m$2\\033[0m"
        ;;
    "yellow")
        ${ECHO_TYPE} "\\033[33m$2\\033[0m"
        ;;
    "skyBlue")
        ${ECHO_TYPE} "\\033[36m$2\\033[0m"
        ;;
    *)
        ${ECHO_TYPE} "$2"
        ;;
    esac
}

# Copy from https://github.com/johnrosen1/vpstool/blob/main/vpstool.sh
check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -Eqi "debian|raspbian" /etc/issue; then
        release="debian"
    elif grep -Eqi "ubuntu" /etc/issue; then
        release="ubuntu"
    elif grep -Eqi "centos|red hat|redhat" /etc/lsb-release; then
        release="centos"
    elif grep -Eqi "debian|raspbian" /proc/version; then
        release="debian"
    elif grep -Eqi "ubuntu" /proc/version; then
        release="ubuntu"
    else
        release=""
    fi
    arch=$(uname -m)
    return 0
}

check_root() {
    if [[ $(id -u) != 0 ]]; then
        echo_content red "Please run this script as root!"
        exit 1
    fi
}

# Check if the port is available (for host system before Docker maps)
check_port_occupancy() {
    local port=$1
    netstat -tuln | grep -q ":$port "
}

dependency_install() {
    # Removed nftables as it's not needed for Docker container's internal firewall
    local depends=(curl systemd jq)
    if [[ "${release}" == "centos" ]]; then
        for i in "${depends[@]}"; do
            rpm -qa | grep "$i" &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo_content green "Installing $i"
                yum install -y "$i"
            fi
        done
    else
        for i in "${depends[@]}"; do
            dpkg -s "$i" &>/dev/null
            if [[ $? -ne 0 ]]; then
                echo_content green "Installing $i"
                apt-get update -y
                apt-get install -y "$i"
            fi
        done
    fi
}

install_docker() {
    if ! command -v docker &>/dev/null; then
        echo_content green "Docker not found, installing..."
        curl -fsSL https://get.docker.com | bash
        if [[ $? -ne 0 ]]; then
            echo_content red "Docker installation failed!"
            exit 1
        fi
        systemctl enable docker
        systemctl start docker
        echo_content green "Docker installed successfully!"
    fi
}

generate_random_passwords() {
    username=$(random_6_characters)
    password=$(random_6_characters)
    connect_password="${username}.${password}"
}

run_docker_container() {
    local h_ui_port=$1
    local h_ui_time_zone=$2
    local ssh_local_forwarded_port=$3
    local username=$4
    local password=$5
    local connect_password=$6
    local version=$7

    echo_content green "Pulling H-UI Docker image..."
    # Ensure the correct image tag if a specific version is requested, otherwise use latest
    local docker_image="jonssonyan/h-ui:${version}"
    if [[ "${version}" == "latest" ]]; then
        docker_image="jonssonyan/h-ui:latest"
    fi

    docker pull "${docker_image}"
    if [[ $? -ne 0 ]]; then
        echo_content red "Failed to pull Docker image: ${docker_image}"
        exit 1
    fi

    echo_content green "Stopping existing H-UI container if any..."
    docker stop h-ui-panel &>/dev/null
    docker rm h-ui-panel &>/dev/null

    echo_content green "Running H-UI Docker container..."
    docker run -d \
        --name h-ui-panel \
        --restart unless-stopped \
        -p "${h_ui_port}":"${h_ui_port}" \
        -p "${ssh_local_forwarded_port}":"${ssh_local_forwarded_port}" \
        -e TZ="${h_ui_time_zone}" \
        -e HUI_PORT="${h_ui_port}" \
        -e HUI_USERNAME="${username}" \
        -e HUI_PASSWORD="${password}" \
        -e HUI_CONNECT_PASSWORD="${connect_password}" \
        -e HUI_SSH_LOCAL_FORWARDED_PORT="${ssh_local_forwarded_port}" \
        "${docker_image}"

    if [[ $? -ne 0 ]]; then
        echo_content red "Failed to start H-UI Docker container!"
        exit 1
    fi
    echo_content green "H-UI Docker container started successfully!"
}

uninstall_h_ui() {
    echo_content red "Stopping and removing H-UI Docker container..."
    docker stop h-ui-panel &>/dev/null
    docker rm h-ui-panel &>/dev/null
    echo_content green "H-UI Docker container uninstalled successfully!"
}

reset_h_ui() {
    uninstall_h_ui
    install_h_ui
}

check_h_ui_running() {
    if docker ps --format '{{.Names}}' | grep -q "h-ui-panel"; then
        return 0 # Running
    else
        return 1 # Not running
    fi
}

get_h_ui_status() {
    if check_h_ui_running; then
        echo_content green "H-UI Docker container is running."
    else
        echo_content red "H-UI Docker container is not running."
    fi
    echo_content yellow "Last 20 lines of logs for h-ui-panel:"
    docker logs h-ui-panel --tail 20
    echo_content yellow "To follow logs in real-time, run: docker logs -f h-ui-panel"
}

update_h_ui() {
    uninstall_h_ui
    install_h_ui "$1"
}

init_var() {
    h_ui_port=8081
    h_ui_time_zone=Asia/Shanghai
    ssh_local_forwarded_port=8082
    translation_file_content=""
    translation_file_base_url="https://raw.githubusercontent.com/jonssonyan/h-ui/refs/heads/main/local/"
    translation_file="en.json"
}

translation() {
    # Determine the system's preferred language
    local lang=$(locale | grep LANG | cut -d'=' -f2 | cut -d'.' -f1)

    case "$lang" in
    zh_CN | zh_SG)
        translation_file="zh_CN.json"
        ;;
    esac

    # Download translation file
    if [[ -n "$translation_file" ]]; then
        translation_file_content=$(curl -fsSL "${translation_file_base_url}${translation_file}")
        if [[ $? -ne 0 ]]; then
            echo_content red "Failed to download translation file. Using default English."
            translation_file_content=""
        fi
    fi
}

get_translation() {
    local key=$1
    if [[ -n "$translation_file_content" ]]; then
        local value=$(echo "$translation_file_content" | jq -r --arg key "$key" '.[$key]')
        if [[ "$value" != "null" ]]; then
            echo "$value"
            return 0
        fi
    fi
    echo "$key" # Fallback to key if translation not found
}

select_language() {
    clear
    echo_content red "=============================================================="
    echo_content skyBlue "Please select language"
    echo_content yellow "1. English (Default)"
    echo_content yellow "2. 简体中文"
    echo_content red "=============================================================="
    read -p "Enter your choice (1-2): " choice
    case $choice in
    1)
        translation_file="en.json"
        ;;
    2)
        translation_file="zh_CN.json"
        ;;
    *)
        translation_file="en.json"
        ;;
    esac
    translation
}

install_h_ui() {
    local install_version=$1
    check_root
    check_sys
    dependency_install
    install_docker

    if [[ -z "${install_version}" ]]; then
        install_version="latest"
    fi

    echo_content green "$(get_translation "H-UI Panel Port"): ${h_ui_port}"
    echo_content green "$(get_translation "H-UI Time Zone"): ${h_ui_time_zone}"
    echo_content green "$(get_translation "SSH Local Forwarded Port"): ${ssh_local_forwarded_port}"

    generate_random_passwords
    run_docker_container "${h_ui_port}" "${h_ui_time_zone}" "${ssh_local_forwarded_port}" "${username}" "${password}" "${connect_password}" "${install_version}"

    clear
    echo_content red "=============================================================="
    echo_content green "$(get_translation "H-UI Panel installed successfully!")"
    echo_content green "$(get_translation "Panel URL"): http://$(curl -s ip.sb):${h_ui_port}"
    echo_content green "$(get_translation "Login Username"): ${username}"
    echo_content green "$(get_translation "Login Password"): ${password}"
    echo_content green "$(get_translation "Connection Password"): ${connect_password}"
    echo_content green "$(get_translation "SSH Local Forwarded Port"): ${ssh_local_forwarded_port}"
    echo_content yellow "注意：对于 OpenVZ 虚拟化，请确保您的 VPS 提供商允许 ${h_ui_port} 和 ${ssh_local_forwarded_port} 端口的流量通过！您可能需要在 VPS 控制面板中配置防火墙规则。"
    echo_content red "=============================================================="
}

main() {
    init_var
    select_language

    case $1 in
    "install")
        install_h_ui "$2"
        ;;
    "uninstall")
        uninstall_h_ui
        ;;
    "reset")
        reset_h_ui
        ;;
    "status")
        get_h_ui_status
        ;;
    "update")
        update_h_ui "$2"
        ;;
    *)
        echo_content red "=============================================================="
        echo_content skyBlue "$(get_translation "Usage"):"
        echo_content yellow "  bash <(curl -fsSL https://raw.githubusercontent.com/jonssonyan/h-ui/main/install.sh) install [version] - $(get_translation "Install H-UI Panel")"
        echo_content yellow "  bash <(curl -fsSL https://raw.githubusercontent.com/jonssonyan/h-ui/main/install.sh) uninstall - $(get_translation "Uninstall H-UI Panel")"
        echo_content yellow "  bash <(curl -fsSL https://raw.githubusercontent.com/jonssonyan/h-ui/main/install.sh) reset - $(get_translation "Reset H-UI Panel (Uninstall and Reinstall)")"
        echo_content yellow "  bash <(curl -fsSL https://raw.githubusercontent.com/jonssonyan/h-ui/main/install.sh) status - $(get_translation "Get H-UI Panel status")"
        echo_content yellow "  bash <(curl -fsSL https://raw.githubusercontent.com/jonssonyan/h-ui/main/install.sh) update [version] - $(get_translation "Update H-UI Panel")"
        echo_content red "=============================================================="
        ;;
    esac
}

main "$@"
