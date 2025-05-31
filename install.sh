#!/bin/bash

set -e

echo "=== 🚀 Hysteria2 安装脚本开始 ==="

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo "❌ 请使用 root 用户运行此脚本"
   exit 1
fi

# 用户输入密码与起始端口
read -p "🔑 请输入用于连接的密码: " PASSWORD
read -p "📟 请输入初始监听端口 (推荐10000-60000): " INIT_PORT

# 检测网络接口
NET_IFACE=$(ls /sys/class/net | grep -v lo | grep -E '^en|^eth|^venet|^docker' | head -n 1)
if [[ -z "$NET_IFACE" ]]; then
    echo "❌ 未检测到有效网络接口，请检查 VPS 网络配置"
    exit 1
fi
echo "✅ 网络接口：$NET_IFACE"

# 安装依赖
apt update -y
apt install -y curl unzip cron

# 下载 hysteria2
BIN=/usr/local/bin/hysteria
if [[ ! -f "$BIN" ]]; then
    curl -Lo "$BIN" https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64
    chmod +x "$BIN"
    echo "✅ Hysteria2 安装成功"
else
    echo "📦 Hysteria2 已存在，跳过下载"
fi

# 创建配置文件目录
mkdir -p /etc/hysteria

# 写入初始端口到文件
echo "$INIT_PORT" > /etc/hysteria/port.txt

# 写入配置文件
cat > /etc/hysteria/config.yaml <<EOF
listen: :$INIT_PORT
auth:
  type: password
  password: $PASSWORD
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
EOF

# 写入 systemd 服务
cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=$BIN server -c /etc/hysteria/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 写入端口跳跃脚本
cat > /usr/local/bin/hysteria-port-hop.sh <<'EOL'
#!/bin/bash
set -e

CONFIG_FILE="/etc/hysteria/config.yaml"
PORT_FILE="/etc/hysteria/port.txt"

# 生成新端口
NEW_PORT=$((RANDOM % 20000 + 10000))

# 替换端口
sed -i "s/^listen: :.*/listen: :$NEW_PORT/" "$CONFIG_FILE"

# 保存当前端口
echo "$NEW_PORT" > "$PORT_FILE"

# 重启服务
systemctl restart hysteria
echo "$(date): 切换端口至 $NEW_PORT" >> /var/log/hysteria-port-hop.log
EOL

chmod +x /usr/local/bin/hysteria-port-hop.sh

# 添加到 crontab
(crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/hysteria-port-hop.sh") | crontab -

# 启动服务
systemctl daemon-reload
systemctl enable hysteria
systemctl restart hysteria

echo "🎉 安装完成！当前监听端口为：$INIT_PORT"
echo "🕑 将每10分钟自动切换端口，最新端口见：/etc/hysteria/port.txt"
