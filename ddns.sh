#!/bin/bash
# Cloudflare DDNS 一键部署脚本 - AWS 开机优化版

# 所有输出重定向到日志，便于调试
exec > >(tee -a /var/log/ddns-setup.log) 2>&1
set -x  # 打印每条命令，方便排错

# ========== 固定配置 ==========
CFKEY="9283f23fbac13705d7301e32919609e4f743a"
CFUSER="wukong8667@gmail.com"
CFZONE_NAME="cfcdndns.top"
CFRECORD_NAME="hk01.cfcdndns.top"
CRON_INTERVAL="* * * * *"   # 每分钟运行一次

# ========== 等待网络就绪（关键） ==========
echo "等待网络连接..."
for i in {1..30}; do
    if curl -s --max-time 2 http://ipv4.icanhazip.com >/dev/null 2>&1; then
        echo "网络已就绪"
        break
    fi
    echo "尝试 $i/30 ..."
    sleep 2
done

# ========== 安装依赖（忽略错误） ==========
echo "安装依赖..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y || true
    apt-get install -y wget curl cron || true
    systemctl enable cron || true
    systemctl start cron || true
elif command -v yum >/dev/null 2>&1; then
    yum install -y wget curl crontabs || true
    systemctl enable crond || true
    systemctl start crond || true
fi

# ========== 准备 DDNS 脚本 ==========
DDNS_SCRIPT="/root/cf-v4-ddns.sh"
echo "准备 DDNS 脚本..."

# 方法1：尝试下载官方脚本（允许失败）
wget -N --no-check-certificate -O "$DDNS_SCRIPT" \
    https://raw.githubusercontent.com/yulewang/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh 2>/dev/null || true

# 如果下载失败或文件为空，则使用内置脚本（更可靠）
if [ ! -s "$DDNS_SCRIPT" ]; then
    echo "下载失败，使用内置脚本"
    cat > "$DDNS_SCRIPT" <<'EOF'
#!/bin/bash
CFKEY="9283f23fbac13705d7301e32919609e4f743a"
CFUSER="wukong8667@gmail.com"
CFZONE_NAME="cfcdndns.top"
CFRECORD_NAME="hk01.cfcdndns.top"

# 获取当前公网 IP
IP=$(curl -s --max-time 10 http://ipv4.icanhazip.com)
[ -z "$IP" ] && IP=$(curl -s --max-time 10 http://api.ipify.org)
[ -z "$IP" ] && exit 1

# 获取 Zone ID
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" \
  -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json" \
  | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

[ -z "$ZONE_ID" ] && exit 1

# 获取 Record ID
RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$CFRECORD_NAME" \
  -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json" \
  | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

[ -z "$RECORD_ID" ] && exit 1

# 更新 DNS 记录
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$IP\",\"ttl\":120,\"proxied\":false}" \
  > /dev/null

echo "$(date): Updated $CFRECORD_NAME to $IP"
EOF
fi

chmod +x "$DDNS_SCRIPT"

# ========== 首次运行（允许失败，因为 DNS 记录可能还未创建） ==========
echo "首次尝试更新 DDNS..."
bash "$DDNS_SCRIPT" || echo "首次更新失败（可能 DNS 记录不存在），将继续设置定时任务"

# ========== 设置 crontab（确保每分钟运行） ==========
echo "设置定时任务..."
# 备份当前 crontab
crontab -l > /tmp/crontab.bak 2>/dev/null || true
# 删除旧的 DDNS 相关行
crontab -l 2>/dev/null | grep -v "$DDNS_SCRIPT" | crontab - 2>/dev/null || true
# 添加新任务
(crontab -l 2>/dev/null; echo "$CRON_INTERVAL $DDNS_SCRIPT >> /var/log/ddns.log 2>&1") | crontab -

# ========== 创建管理命令 ==========
cat > /usr/local/bin/ddns <<'EOF'
#!/bin/bash
case "$1" in
    status) echo "当前IP: $(curl -s ipv4.icanhazip.com)"; crontab -l | grep cf-v4-ddns.sh ;;
    update) /root/cf-v4-ddns.sh ;;
    stop) crontab -l | grep -v cf-v4-ddns.sh | crontab - ;;
    start) (crontab -l 2>/dev/null; echo "* * * * * /root/cf-v4-ddns.sh >> /var/log/ddns.log 2>&1") | crontab - ;;
    *) echo "用法: ddns {status|update|stop|start}" ;;
esac
EOF
chmod +x /usr/local/bin/ddns

# ========== 完成标记 ==========
echo "DDNS 部署完成" > /var/log/ddns_setup.done
echo "脚本执行完毕，时间: $(date)"
