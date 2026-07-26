#!/bin/bash
#
# sing-box 完整部署脚本：安装 -> 生成密钥 -> 配置服务端 -> 防火墙放行 -> 生成订阅
# 特点：幂等设计，已安装/已生成的内容会自动跳过，避免重复消耗流量
# 适用于 Debian/Ubuntu 系统，默认会自动安装必要依赖并生成可直接使用的订阅链接。
#
set -e

# 默认使用较保守的权限，避免生成文件被其他用户读取。
umask 077

# 版本与端口配置
# 这里的版本号和端口可根据实际环境自行调整。
# 也支持通过环境变量覆盖，方便一键部署时做轻量自定义。
SING_BOX_VERSION="1.13.14"
LISTEN_PORT="${LISTEN_PORT:-443}"
SUB_PORT="${SUB_PORT:-8443}"
# Hysteria2 基于 QUIC/UDP，与 VLESS+Reality(TCP) 互补，提供 UDP 代理能力。
HY2_PORT="${HY2_PORT:-8444}"
# Hysteria2 使用的域名（用于自签证书的 CN/SAN，客户端可设 insecure=1 或自行替换为真实证书）。
HY2_DOMAIN="${HY2_DOMAIN:-singbox.local}"
REALITY_SNI="${REALITY_SNI:-swdist.apple.com}"
SHOW_SECRETS="${SHOW_SECRETS:-0}"

# 状态目录与持久化文件
# 用于保存 UUID、Reality 密钥对、订阅 token 和部署详情，避免重复生成导致客户端配置失效。
STATE_DIR="/etc/sing-box"
STATE_FILE="${STATE_DIR}/keys.env"
SUB_STATE_FILE="${STATE_DIR}/sub_token.env"
DEPLOYMENT_INFO_FILE="${STATE_DIR}/deployment-info.txt"

echo "################################################"
echo "# 1. 安装 sing-box（如已是目标版本则跳过下载） #"
echo "################################################"

# 检查当前系统是否已安装目标版本的 sing-box。
# 这样脚本可以重复执行而不会反复下载安装，适合幂等部署。
CURRENT_VERSION=""
if command -v sing-box &> /dev/null; then
    CURRENT_VERSION=$(sing-box version 2>/dev/null | head -n1 | awk '{print $3}')
fi

if [ "$CURRENT_VERSION" == "$SING_BOX_VERSION" ]; then
    echo "✅ 已安装 sing-box $SING_BOX_VERSION，跳过下载。"
else
    echo "未检测到目标版本（当前: ${CURRENT_VERSION:-无}），开始安装 $SING_BOX_VERSION ..."
    curl -fsSL https://sing-box.app/install.sh | sh
fi

sing-box version

echo ""
echo "################################################"
echo "# 2. 生成/复用 UUID 和 Reality 密钥对           #"
echo "################################################"

# 保证状态目录存在，并优先复用已有密钥。
# 这样同一台服务器再次部署时，客户端配置不会因为 UUID/密钥变化而失效。
sudo install -d -m 700 "$STATE_DIR"

if [ -f "$STATE_FILE" ]; then
    echo "✅ 检测到已保存的密钥信息，复用现有 UUID/密钥，避免破坏已连通的客户端配置。"
    source "$STATE_FILE"
else
    echo "未检测到已保存的密钥，首次生成..."
    UUID=$(sing-box generate uuid)
    KEYPAIR_OUTPUT=$(sing-box generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYPAIR_OUTPUT" | grep PrivateKey | awk '{print $2}')
    PUBLIC_KEY=$(echo "$KEYPAIR_OUTPUT" | grep PublicKey | awk '{print $2}')
    SHORT_ID=$(openssl rand -hex 8)

    # 将生成的凭据持久化到配置文件，后续脚本执行时可直接复用。
    sudo tee "$STATE_FILE" > /dev/null << EOF
UUID=${UUID}
PRIVATE_KEY=${PRIVATE_KEY}
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
EOF
    sudo chmod 600 "$STATE_FILE"
    echo "✅ 密钥已生成并保存到 $STATE_FILE（下次运行会自动复用）"
fi

if [ "$SHOW_SECRETS" = "1" ]; then
    echo "UUID:        $UUID"
    echo "PrivateKey:  $PRIVATE_KEY"
    echo "PublicKey:   $PUBLIC_KEY"
    echo "ShortID:     $SHORT_ID"
else
    echo "ℹ️  默认安全模式下，完整密钥详情不会直接打印到终端。"
fi

echo ""
echo "################################################"
echo "# 2b. 生成/复用 Hysteria2 密码与自签证书         #"
echo "################################################"

# Hysteria2 是基于 QUIC 的代理协议，原生支持 UDP，与 VLESS+Reality(TCP) 互补。
# 这里生成一个随机密码，并使用 openssl 自签一张证书（客户端可设 insecure=1 跳过验证）。
HY2_STATE_FILE="${STATE_DIR}/hy2.env"
HY2_CERT_DIR="${STATE_DIR}/hy2_certs"

if [ -f "$HY2_STATE_FILE" ]; then
    echo "✅ 检测到已保存的 Hysteria2 配置，复用现有密码与证书。"
    source "$HY2_STATE_FILE"
else
    echo "未检测到 Hysteria2 配置，首次生成..."
    HY2_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-22)
    sudo install -d -m 700 "$HY2_CERT_DIR"
    # 生成自签证书（包含 SAN，避免部分客户端严格校验）。
    sudo openssl ecparam -genkey -name prime256v1 -out "${HY2_CERT_DIR}/key.pem" 2>/dev/null \
        || sudo openssl genrsa -out "${HY2_CERT_DIR}/key.pem" 2048
    sudo openssl req -new -x509 -days 3650 \
        -key "${HY2_CERT_DIR}/key.pem" \
        -out "${HY2_CERT_DIR}/cert.pem" \
        -subj "/CN=${HY2_DOMAIN}" \
        -addext "subjectAltName=DNS:${HY2_DOMAIN}" 2>/dev/null
    sudo chmod 600 "${HY2_CERT_DIR}/key.pem"

    sudo tee "$HY2_STATE_FILE" > /dev/null << EOF
HY2_PASSWORD=${HY2_PASSWORD}
HY2_DOMAIN=${HY2_DOMAIN}
EOF
    sudo chmod 600 "$HY2_STATE_FILE"
    echo "✅ Hysteria2 密码与自签证书已生成并保存"
fi

if [ "$SHOW_SECRETS" = "1" ]; then
    echo "HY2 Password: $HY2_PASSWORD"
    echo "HY2 Domain:   $HY2_DOMAIN"
else
    echo "ℹ️  Hysteria2 密码详情默认不打印（设置 SHOW_SECRETS=1 可查看）。"
fi

echo ""
echo "################################################"
echo "# 3. 写入服务端配置                             #"
echo "################################################"

# 写入 sing-box 的服务端配置文件：使用 VLESS + Reality 方案。
# 其中 UUID、私钥和 ShortID 由上一步生成并复用。
sudo tee /etc/sing-box/config.json > /dev/null << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": ${LISTEN_PORT},
      "users": [
        {
          "uuid": "${UUID}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${REALITY_SNI}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    },
    {
      "type": "hysteria2",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [
        {
          "password": "${HY2_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${HY2_CERT_DIR}/cert.pem",
        "key_path": "${HY2_CERT_DIR}/key.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

sudo chmod 600 /etc/sing-box/config.json
sudo sing-box check -c /etc/sing-box/config.json
echo "✅ 配置文件语法检查通过"

echo ""
echo "################################################"
echo "# 3b. 开启 BBR 拥塞控制（幂等）                  #"
echo "################################################"

# BBR 是 TCP 拥塞控制算法，对 VLESS+Reality(TCP) 和订阅服务有明显加速效果。
# Hysteria2 走 QUIC/UDP，不直接受 tcp_congestion_control 影响，但 fq qdisc 对 UDP 也有益。
# 这里采用幂等写法：先检查是否已配置，避免重复追加到 sysctl.conf。
ensure_sysctl() {
    local key=$1
    local value=$2
    if sudo grep -qE "^\s*${key}\s*=" /etc/sysctl.conf; then
        # 已存在则更新为期望值（用 sed 原地替换该行，避免重复条目）。
        sudo sed -i -E "s|^\s*${key}\s*=.*|${key}=${value}|" /etc/sysctl.conf
    else
        echo "${key}=${value}" | sudo tee -a /etc/sysctl.conf > /dev/null
    fi
}

ensure_sysctl "net.core.default_qdisc" "fq"
ensure_sysctl "net.ipv4.tcp_congestion_control" "bbr"
sudo sysctl -p > /dev/null

# 验证是否生效。
CURRENT_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
echo "✅ 当前 qdisc: $CURRENT_QDISC，TCP 拥塞控制: $CURRENT_CC"

echo ""
echo "################################################"
echo "# 4. 启动/重启 sing-box 服务                    #"
echo "################################################"

# 让 sing-box 在系统启动时自动运行，并应用最新配置。
sudo systemctl enable sing-box
sudo systemctl restart sing-box
sleep 1
sudo systemctl status sing-box --no-pager | head -5

echo ""
echo "################################################"
echo "# 5. 防火墙放行 (ufw + iptables 持久化)          #"
echo "################################################"

# 为 sing-box 的监听端口和订阅服务端口放行流量，避免客户端或订阅访问被阻断。
# ufw
if command -v ufw &> /dev/null; then
    sudo ufw allow ${LISTEN_PORT}/tcp 2>/dev/null || true
    sudo ufw allow ${SUB_PORT}/tcp 2>/dev/null || true
    # Hysteria2 基于 QUIC，必须放行 UDP。
    sudo ufw allow ${HY2_PORT}/udp 2>/dev/null || true
    echo "✅ ufw 规则已添加（如 ufw 未启用则无影响）"
fi

# iptables（幂等：先检查规则是否已存在，不存在才插入）
# 这样脚本多次执行也不会重复增加相同规则。
add_iptables_rule_if_missing() {
    local port=$1
    local proto=${2:-tcp}
    if ! sudo iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
        sudo iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT
        echo "✅ 已添加 iptables 规则：放行 $proto 端口 $port"
    else
        echo "✅ iptables 规则已存在：$proto 端口 $port，跳过"
    fi
}

add_iptables_rule_if_missing ${LISTEN_PORT}
add_iptables_rule_if_missing ${SUB_PORT}
# Hysteria2 走 QUIC/UDP，单独放行 UDP 端口。
add_iptables_rule_if_missing ${HY2_PORT} udp

if ! command -v netfilter-persistent &> /dev/null; then
    echo "安装 iptables-persistent..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
fi
sudo netfilter-persistent save
echo "✅ iptables 规则已持久化保存"

echo ""
echo "⚠️  提醒：云平台安全组/NSG 需要单独在控制台放行以下端口："
echo "    - ${LISTEN_PORT}/tcp  (VLESS+Reality)"
echo "    - ${SUB_PORT}/tcp     (订阅服务)"
echo "    - ${HY2_PORT}/udp    (Hysteria2 / QUIC)"
echo "    服务器内部防火墙放行不代表云平台外层也放行。"

echo ""
echo "################################################"
echo "# 6. 安装 Nginx（如已安装则跳过）                #"
echo "################################################"

# Nginx 用于提供订阅文件的 HTTP 下载服务，后续将把订阅内容暴露到指定端口。

if command -v nginx &> /dev/null; then
    echo "✅ Nginx 已安装，跳过安装步骤。"
else
    sudo apt update
    sudo apt install -y nginx
fi

echo ""
echo "################################################"
echo "# 7. 生成/复用订阅 token 并写入订阅文件          #"
echo "################################################"

# 获取服务器公网 IP，作为订阅内容中的连接地址。
SERVER_IP=$(curl -s ifconfig.me)

if [ -f "$SUB_STATE_FILE" ]; then
    echo "✅ 检测到已保存的订阅 token，复用现有链接。"
    source "$SUB_STATE_FILE"
else
    SUB_TOKEN=$(openssl rand -hex 16)
    sudo tee "$SUB_STATE_FILE" > /dev/null << EOF
SUB_TOKEN=${SUB_TOKEN}
EOF
    sudo chmod 600 "$SUB_STATE_FILE"
    echo "✅ 订阅 token 已生成并保存"
fi

# 生成通用的 VLESS 链接，并将其编码为 base64，适配大多数客户端。
VLESS_URI="vless://${UUID}@${SERVER_IP}:${LISTEN_PORT}?encryption=none&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#my-vless-reality"

# 生成 Hysteria2 链接（基于 QUIC/UDP）。
# insecure=1 表示跳过自签证书校验，方便快速使用；如使用真实证书可去掉该参数。
HY2_URI="hysteria2://${HY2_PASSWORD}@${SERVER_IP}:${HY2_PORT}?sni=${HY2_DOMAIN}&insecure=1#my-hysteria2"

# 多节点订阅：将两条链接按行拼接后整体 base64 编码。
ENCODED=$(printf "%s\n%s" "$VLESS_URI" "$HY2_URI" | base64 -w 0)

# 将订阅内容写入 Nginx 目录，后续通过 HTTP 地址下载。
sudo mkdir -p /var/www/sub
echo "$ENCODED" | sudo tee /var/www/sub/${SUB_TOKEN}.txt > /dev/null
echo "✅ 通用订阅（V2Box/v2rayNG等，base64格式）已生成"

# 将部署详情保存到本地文件，默认不在终端直接暴露敏感信息。
# 如需查看完整内容，可在运行时设置 SHOW_SECRETS=1。
sudo tee "$DEPLOYMENT_INFO_FILE" > /dev/null << EOF
SERVER_IP=${SERVER_IP}
UUID=${UUID}
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
VLESS_URI=${VLESS_URI}
HY2_PASSWORD=${HY2_PASSWORD}
HY2_DOMAIN=${HY2_DOMAIN}
HY2_URI=${HY2_URI}
SUB_URL_TXT=http://${SERVER_IP}:${SUB_PORT}/${SUB_TOKEN}.txt
SUB_URL_YAML=http://${SERVER_IP}:${SUB_PORT}/${SUB_TOKEN}.yaml
EOF
sudo chmod 600 "$DEPLOYMENT_INFO_FILE"

# Clash / Clash Box (Mihomo内核) 专用订阅，格式必须是完整 YAML，不能用 base64。
# 这份内容适用于支持 Mihomo 的客户端，便于直接导入代理配置。
sudo tee /var/www/sub/${SUB_TOKEN}.yaml > /dev/null << YAMLEOF
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info

proxies:
  - name: "my-vless-reality"
    type: vless
    server: ${SERVER_IP}
    port: ${LISTEN_PORT}
    uuid: ${UUID}
    network: tcp
    tls: true
    udp: true
    servername: ${REALITY_SNI}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
  - name: "my-hysteria2"
    type: hysteria2
    server: ${SERVER_IP}
    port: ${HY2_PORT}
    password: ${HY2_PASSWORD}
    sni: ${HY2_DOMAIN}
    skip-cert-verify: true

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - my-vless-reality
      - my-hysteria2

rules:
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
YAMLEOF
echo "✅ Clash/Clash Box 专用订阅（YAML格式）已生成"

echo ""
echo "################################################"
echo "# 8. 配置 Nginx 订阅站点（幂等）                 #"
echo "################################################"

# 配置 Nginx 监听订阅端口，并将 /var/www/sub 暴露为可下载目录。
# 这样可以通过 HTTP 地址直接访问订阅文件。
sudo tee /etc/nginx/sites-available/sub > /dev/null << NGINXEOF
server {
    listen ${SUB_PORT};
    server_name _;

    location / {
        root /var/www/sub;
        autoindex off;
    }
}
NGINXEOF

# 删除旧的符号链接（若存在），重新建立软链以启用站点（幂等）
sudo rm -f /etc/nginx/sites-enabled/sub
sudo ln -s /etc/nginx/sites-available/sub /etc/nginx/sites-enabled/sub

# 校验 Nginx 配置语法
sudo nginx -t
# 重启 Nginx 使订阅站点生效并设置开机自启
sudo systemctl restart nginx
sudo systemctl enable nginx

echo ""
echo "======================================================"
echo "✅ 全部完成！"
echo "======================================================"
echo ""
echo "服务器 IP:        $SERVER_IP"
echo "UUID:             $UUID"
echo "PublicKey:        $PUBLIC_KEY"
echo "ShortID:          $SHORT_ID"
echo "伪装域名 (SNI):    $REALITY_SNI"
echo ""
echo "Hysteria2 密码:    $HY2_PASSWORD"
echo "Hysteria2 域名:    $HY2_DOMAIN"
echo ""
echo "--- VLESS+Reality 链接 (TCP) ---"
echo "$VLESS_URI"
echo ""
echo "--- Hysteria2 链接 (QUIC/UDP) ---"
echo "$HY2_URI"
echo ""
echo "--- 通用订阅链接（V2Box / v2rayNG / NekoBox 等） ---"
echo "http://${SERVER_IP}:${SUB_PORT}/${SUB_TOKEN}.txt"
echo ""
echo "--- Clash / Clash Box 专用订阅链接（YAML格式） ---"
echo "http://${SERVER_IP}:${SUB_PORT}/${SUB_TOKEN}.yaml"
echo ""
echo "⚠️  请妥善保管以上链接，不要发给不信任的人。"
echo "⚠️  别忘了去云平台控制台放行以下端口："
echo "    ${LISTEN_PORT}/tcp  (VLESS+Reality)"
echo "    ${SUB_PORT}/tcp     (订阅服务)"
echo "    ${HY2_PORT}/udp    (Hysteria2 / QUIC)"
echo "======================================================"