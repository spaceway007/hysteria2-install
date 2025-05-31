#!/bin/bash

set -e

echo "=== 🚀 Hysteria2 安装脚本开始 ==="

# 检测网络接口（排除 lo）
NET_IFACE=$(ls /sys/class/net | grep -v lo | grep -E '^en|^eth|^venet|^docker' | head -n 1)
if [[ -z "$NET_IFACE" ]]; then
    echo "❌ 未检测到有效网络接口，请检查 VPS 网络配置"
    exit 1
fi
echo "✅ 网络接口：$NET_IFACE"

# 安装必要工具
apt update -y
apt install -y curl sudo unzip

# 安装 hysteria2
HYSTERIA_BIN="/usr/local/bin/hysteria"
if [[ ! -f "$HYSTERIA_BIN" ]]; then
    echo "⬇️ 正在下载 Hysteria2 最新版本..."
    curl -Lo "$HYSTERIA_BIN" https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64
    chmod +x "$HYSTERIA_BIN"
    echo "✅ Hysteria2 安装成功"
else
    echo "📦 Hysteria2 已存在，跳过下载"
fi

# 创建配置文件夹
mkdir -p /etc/hysteria

# 生成随机端口用于端口跳跃
RAND_PORT=$((RANDOM % 10000 + 10000))
echo "⚡ 随机监听端口已生成：$RAND_PORT"

# 写入配置文件
cat > /etc/hysteria/config.yaml <<EOF
listen: :$RAND_PORT
auth:
  type: password
  password: your-password
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
EOF

# 写入 systemd 服务文件
cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=$HYSTERIA_BIN server -c /etc/hysteria/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 尝试添加 nftables 端口跳跃（跳过失败）
if command -v nft &>/dev/null; then
    echo "🎯 检测到 nftables，尝试创建端口跳跃规则..."
    nft list table inet hui_porthopping &>/dev/null || nft add table inet hui_porthopping || true
    nft list chain inet hui_porthopping prerouting &>/dev/null || \
        nft add chain inet hui_porthopping prerouting '{ type nat hook prerouting priority dstnat; policy accept; }' || echo "⚠️ 无法添加 nft prerouting 链（OpenVZ 可能不支持 NAT）"
else
    echo "⚠️ nftables 未安装或不兼容，跳过端口跳跃防火墙规则设置（不影响主程序）"
fi

# 启动并设置开机启动
echo "🚀 启动并设置 Hysteria2 开机自启..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable hysteria
systemctl restart hysteria

echo "🎉 安装完成！监听端口：$RAND_PORT"
echo "👉 请在客户端使用该端口连接，并根据需要更改 /etc/hysteria/config.yaml"
