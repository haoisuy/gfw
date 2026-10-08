#!/bin/bash
# VLESS + Reality 一键安装脚本
# 适用于 CentOS / Ubuntu / Debian

set -e

echo "========================================="
echo "  VLESS + Reality 一键安装脚本"
echo "========================================="

# 检测系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "无法识别系统类型"
    exit 1
fi

echo "系统: $OS"

# 安装依赖
echo "[1/6] 安装依赖..."
case "$OS" in
    centos|rhel|rocky|almalinux)
        yum install -y curl wget unzip nginx -q
        ;;
    ubuntu|debian)
        apt-get update -qq
        apt-get install -y curl wget unzip nginx -qq
        ;;
esac

# 安装 Xray
echo "[2/6] 安装 Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 生成 UUID 和密钥
echo "[3/6] 生成 UUID 和密钥..."
UUID=$(cat /proc/sys/kernel/random/uuid)
KEYS=$(/usr/local/x-ray/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)

# 写入配置
echo "[4/6] 配置 Xray..."
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {"id": "${UUID}", "flow": "xtls-rprx-vision"}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": [
            "www.microsoft.com",
            "www.apple.com"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ]
}
EOF

# 启动 Xray
echo "[5/6] 启动 Xray..."
systemctl enable xray
systemctl restart xray

# 配置 nginx 订阅服务
echo "[6/6] 配置订阅服务..."
mkdir -p /usr/share/nginx/html

# 生成 Clash 配置（ClashX Pro 格式）
cat > /usr/share/nginx/html/clash << EOF
port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - 8.8.8.8
    - 1.1.1.1
proxies:
  - name: "VLESS-Reality"
    type: vless
    server: $(curl -s ifconfig.me)
    port: 443
    uuid: ${UUID}
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: www.microsoft.com
    client-fingerprint: chrome
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: "${SHORT_ID}"
proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - VLESS-Reality
      - DIRECT
rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF

# 生成 Base64 订阅（兼容 Shadowrocket / v2rayN 等）
V2RAY_LINK="vless://${UUID}@$(curl -s ifconfig.me):443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-Reality"
echo -n "$V2RAY_LINK" | base64 > /usr/share/nginx/html/sub

# 启动 nginx
systemctl enable nginx 2>/dev/null || true
systemctl restart nginx 2>/dev/null || systemctl start nginx 2>/dev/null || true

# 输出配置信息
SERVER_IP=$(curl -s ifconfig.me)
echo ""
echo "========================================="
echo "  ✅ 安装完成！"
echo "========================================="
echo ""
echo "服务器 IP: ${SERVER_IP}"
echo "UUID: ${UUID}"
echo "Public Key: ${PUBLIC_KEY}"
echo "Short ID: ${SHORT_ID}"
echo ""
echo "========================================="
echo "  📡 ClashX Pro 订阅地址："
echo "  http://${SERVER_IP}/clash"
echo "========================================="
echo ""
echo "========================================="
echo "  📡 Shadowrocket 订阅地址："
echo "  http://${SERVER_IP}/sub"
echo "========================================="
echo ""
echo "保存以下信息（重要）："
echo "${UUID}|${PUBLIC_KEY}|${SHORT_ID}|${SERVER_IP}" > /root/xray_info.txt