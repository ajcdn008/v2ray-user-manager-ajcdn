#!/bin/bash

# --- V2Ray 多用户管理一体脚本 ---
# 功能：
# 1. 自动安装 jq（如未安装）
# 2. 自动添加用户（UUID + 随机端口）
# 3. 提供 list_users 和 delete_user 脚本

CONFIG="/usr/local/etc/v2ray/config.json"
ADDRESS=$(curl -s ifconfig.me)

# 安装 jq（如果未安装）
echo "[🔍] 检查 jq 是否安装..."
if ! command -v jq &> /dev/null; then
  echo "[📦] 安装 jq..."
  if command -v yum &> /dev/null; then
    yum install -y jq || { echo "❌ 安装失败，请手动安装 jq"; exit 1; }
  elif command -v apt &> /dev/null; then
    apt update && apt install -y jq || { echo "❌ 安装失败，请手动安装 jq"; exit 1; }
  else
    echo "❌ 不支持的操作系统，请手动安装 jq"
    exit 1
  fi
fi

# 添加用户逻辑
UUID=$(cat /proc/sys/kernel/random/uuid)
PORT=$((20000 + RANDOM % 40000))

jq --arg uuid "$UUID" --argjson port "$PORT" '
  .inbounds += [{
    "port": $port,
    "protocol": "vmess",
    "settings": {
      "clients": [{
        "id": $uuid,
        "alterId": 0
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "none"
    }
  }]' "$CONFIG" > /tmp/config_tmp.json && mv /tmp/config_tmp.json "$CONFIG"

systemctl restart v2ray

# 输出 VMess 链接
VMESS_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "User-$UUID",
  "add": "$ADDRESS",
  "port": "$PORT",
  "id": "$UUID",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": ""
}
EOF
)

VMESS_LINK="vmess://$(echo "$VMESS_JSON" | base64 -w 0)"
echo -e "\n✅ 成功添加新用户："
echo "UUID: $UUID"
echo "端口: $PORT"
echo -e "🔗 VMess 链接：\n$VMESS_LINK"

# 生成 list_users.sh
cat <<EOF > /root/list_users.sh
#!/bin/bash
jq -r '.inbounds[] | select(.protocol=="vmess") | "端口: \(.port)\nUUID: \(.settings.clients[0].id)\n----"' "$CONFIG"
EOF
chmod +x /root/list_users.sh

# 生成 delete_user.sh
cat <<EOF > /root/delete_user.sh
#!/bin/bash
read -p "请输入要删除的端口号: " PORT
jq 'del(.inbounds[] | select(.port == '"\$PORT"'))' "$CONFIG" > /tmp/config_tmp.json && mv /tmp/config_tmp.json "$CONFIG"
echo "✅ 已删除端口 \$PORT 的用户"
systemctl restart v2ray
EOF
chmod +x /root/delete_user.sh

echo -e "\n🎉 管理工具已部署完毕："
echo "➡️ 添加用户：bash /root/add_user.sh"
echo "📄 查看所有用户：bash /root/list_users.sh"
echo "❌ 删除用户：bash /root/delete_user.sh"
echo "✅ 完成！"
