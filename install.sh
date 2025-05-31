#!/bin/bash
set -e

echo "=== Installing Hysteria2 ==="

# 检测系统版本
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
else 
    echo "无法识别系统"
    exit 1 
fi

# 获取第一个非 lo 的网卡
NET_IFACE=$(ls /sys/class/net | grep -v lo | head -n 1)
if [ -z "$NET_IFACE" ]; then
    echo "未能找到有效的网络接口"
    exit 1
fi

echo "使用网络接口: $NET_IFACE"

# 检查并安装 nftables
if ! command -v nft &>/dev/null; then
    echo "安装 nftables..."
    apt update && apt install -y nftables
fi

# 启用并启动 nftables
echo "启动 nftables 服务..."
systemctl enable nftables
systemctl start nftables

# 创建 nft 表
if ! nft list table inet hui_porthopping &>/dev/null; then
    nft add table inet hui_porthopping || {
        echo "创建 nft 表 hui_porthopping 失败"
        exit 1
    }
fi

# 检查并添加 NAT hook
if grep -q nat /proc/net/ip_tables_names || modprobe nf_nat &>/dev/null; then
    echo "已启用 NAT，检查 prerouting 规则..."

    if ! nft list chain inet hui_porthopping prerouting &>/dev/null; then
        nft add chain inet hui_porthopping prerouting '{ type nat hook prerouting priority dstnat; policy accept; }' || {
            echo "创建 nft prerouting 失败"
            exit 1
        }
    else
        echo "nftables prerouting 规则已存在"
    fi
else
    echo "未找到 NAT 支持，跳过 prerouting 配置"
fi

# 下载并安装 Hysteria2
HYSTERIA_URL="https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64"
INSTALL_DIR="/usr/local/bin"

echo "正在下载安装 Hysteria2..."
curl -L "$HYSTERIA_URL" -o "$INSTALL_DIR/hysteria"
chmod +x "$INSTALL_DIR/hysteria"

# 创建配置目录和文件
mkdir -p /etc/hysteria

cat > /etc/hysteria/config.yaml <<CONFIG
listen: :443
acme:
  domains:
    - your.domain.com
  email: your@email.com
auth:
  type: password
  password: your-password
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
CONFIG

# 创建 systemd 服务
cat > /etc/systemd/system/hysteria.service <<SERVICE
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

# 启动服务
echo "正在启动 Hysteria 服务..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable hysteria
systemctl start hysteria

echo "Hysteria2 安装完成！"
echo "配置文件位于 /etc/hysteria/config.yaml"
