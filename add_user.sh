#!/bin/bash

# --- V2Ray 多用户管理一体脚本（自动识别配置路径） ---
# 功能：
# 1. 自动安装 jq（如未安装）
# 2. 自动识别 V2Ray config.json 路径
# 3. 自动添加用户（UUID + 随机端口）
# 4. 自动生成 list_users.sh 和 delete_user.sh

# 自动寻找 config.json 路径
CONFIG=""
POSSIBLE_PATHS=(
  "/usr/local/etc/v2ray/config.json"
  "/etc/v2ray/config.json"
  "/usr/local/etc/xray/config.json"
  "/etc/xray/config.json"
)

for path in "${POSSIBLE_PATHS[@]}"; do
  if [ -f "$path" ]; then
    CONFIG="$path"
    break
  fi
done

if [ -z "$CONFIG" ]; then
  echo "❌ 未找到 config.json，请先安装并配置好 V2Ray/Xray"
  exit 1
fi

ADDRESS=$(curl -s ifconfig.me)

# 检查并自动安装 jq
echo "[🔍] 检查 jq 是否安装..."
if ! command -v jq &> /dev/null; then
  echo "[📦] 安装 jq..."
  if command -v yum &> /dev/null; then
    yum install -y jq || { echo "❌ 安装 jq 失败，请手动安装"; exit 1; }
  elif command -v apt &> /dev/null; then
    apt update && apt install -y jq || { echo "❌ 安装 jq 失败，请手动安装"; exit 1; }
  else
    echo "❌ 不支持的操作系统，请手动安装 jq"
    exit 1
  fi
fi

# 生成 UUID 和随机端口
UUID=$(cat /proc/sys/kernel/random/uuid)
PORT=$((20000 + RANDOM % 40000))

# 插入用户配置
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

# 尝试重启服务（兼容 v2ray 和 xray）
if systemctl restart v2ray &> /dev/null; then
  echo "🔄 已重启 v2ray 服务"
elif systemctl restart xray &> /dev/null; then
  echo "🔄 已重启 xray 服务"
else
  echo "⚠️ 找不到 v2ray/xray 服务，可能未正确安装"
fi

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
(systemctl restart v2ray 2>/dev/null || systemctl restart xray 2>/dev/null)
EOF
chmod +x /root/delete_user.sh

echo -e "\n🎉 管理工具已部署完毕："
echo "➡️ 添加用户：bash /root/add_user.sh"
echo "📄 查看所有用户：bash /root/list_users.sh"
echo "❌ 删除用户：bash /root/delete_user.sh"
echo "✅ 完成！"
