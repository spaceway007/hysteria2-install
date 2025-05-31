#!/bin/bash

set -e

echo "🔧 Hysteria2 安装脚本（适用于 OpenVZ 且支持端口跳跃）"

# 设置 Hysteria 版本
VERSION="v2.6.1"
ARCH="amd64"
HYSTERIA_TARBALL="hysteria-linux-${ARCH}.tar.gz"
HYSTERIA_URL="https://github.com/apernet/hysteria/releases/download/${VERSION}/${HYSTERIA_TARBALL}"
INSTALL_DIR="/usr/local/bin"

# 安装依赖
echo "---> Installing dependencies (curl, ca-certificates, iptables-persistent/iptables-services)..."
apt-get update
apt-get install -y curl ca-certificates iptables-persistent

# 下载并解压 Hysteria2
echo "---> 正在下载 Hysteria2 可执行文件..."
cd /tmp
curl -LO "$HYSTERIA_URL"
tar -xvzf "$HYSTERIA_TARBALL"

# 移动并赋予权限
chmod +x hysteria
mv hysteria "$INSTALL_DIR/hysteria"

# 创建配置目录
mkdir -p /etc/hysteria

# 生成配置文件
cat > /etc/hysteria/config.yaml <<CONFIG
listen: :443
tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem
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
After=networ
