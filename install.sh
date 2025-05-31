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

# 获取第一个有效的网卡（排除 lo 和 docker）
NET_IFACE=$(ls /sys/class/net | grep -Ev '^(lo|docker0)$' | head -n 1)
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

# 创建 NAT hook（如果支持）
if grep -q nat /proc/net/ip_tables_names || modprobe nf_nat &>/dev/null; then
    echo "检查 NAT 支持，尝试添加 prerouting 链..."
    if ! nft list chain inet hui_porthopping prerouting &>/dev/null; then
        if ! nft add chain inet hui_porthopping prerouting '{ type nat hook prerouting priority dstnat; policy accept; }'; then
            echo "⚠️ 警告：无法创建 NAT prerouting hook，可能当前环境不支持（容器或内核不兼容），跳过该步骤"
        else
            echo "✅ 已成功添加 NAT prerouting hook"
        fi
    else
        echo "nftables prerouting 规则已存在"
    fi
else
    echo "系统未启用 NAT，跳过 NAT hook 创建"
fi

# 下载并安装 Hysteria2
HYSTERIA_URL="https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64"
INSTALL_DIR="/usr/local/bin"

echo "正在下载安装 Hysteria2..."
curl -L "$HYSTERIA_URL" -o "$INSTALL_DIR/hysteria"
chmod +x "$INSTALL_DIR/hysteria"

# 创建配置目录和默认配置
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

echo ""
echo "🎉 Hysteria2 安装完成！"
echo "👉 配置文件位于：/etc/hysteria/config.yaml"
echo "👉 服务名称：hysteria"
