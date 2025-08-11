#!/bin/bash

# =========== 配置区(请按实际填写) ===================
CFKEY="9283f23fbac13705d7301e32919609e4f743a"
CFUSER="wukong8667@gmail.com"
CFZONE_NAME="cfcdndns.top"
CFRECORD_NAME="hk01.cfcdndns.top"
DDNS_PATH="/root/ddns.sh"
SERVICE_NAME="ddns"
SLEEP_SECOND=60      # 脚本运行间隔秒
# ====================================================

set -e

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

echo -e "${GREEN}====== Cloudflare DDNS 一键守护安装脚本(带参数注入) ======${NC}"

# 检查ddns.sh是否存在
if [[ ! -f "$DDNS_PATH" ]]; then
    echo -e "${RED}未找到 $DDNS_PATH！请先上传ddns.sh脚本到此路径。${NC}"
    exit 1
fi

chmod +x "$DDNS_PATH"

# 注入参数，如果你的ddns.sh写成 CFKEY= 这样，则会替换
echo -e "${GREEN}写入Cloudflare参数到ddns.sh...${NC}"
sed -i "s/^CFKEY=.*/CFKEY=\"$CFKEY\"/" "$DDNS_PATH"
sed -i "s/^CFUSER=.*/CFUSER=\"$CFUSER\"/" "$DDNS_PATH"
sed -i "s/^CFZONE_NAME=.*/CFZONE_NAME=\"$CFZONE_NAME\"/" "$DDNS_PATH"
sed -i "s/^CFRECORD_NAME=.*/CFRECORD_NAME=\"$CFRECORD_NAME\"/" "$DDNS_PATH"

# 检查参数是否真正写入
for key in CFKEY CFUSER CFZONE_NAME CFRECORD_NAME; do
    val=$(grep "^$key=" "$DDNS_PATH" | cut -d= -f2-)
    if [[ -z "$val" || "$val" == '""' ]]; then
        echo -e "${RED}参数 $key 注入不成功，请检查ddns.sh脚本结构！${NC}"
        exit 1
    fi
done

# 预运行检查
echo -e "${GREEN}预检测 ddns.sh 是否能正常运行...${NC}"
bash "$DDNS_PATH" > /tmp/ddns_test.log 2>&1 || true
if grep -qE "fail|错误|invalid|not found|Exception" /tmp/ddns_test.log; then
    echo -e "${YELLOW}检测日志有异常内容，请确认参数正确，以下为部分日志：${NC}"
    cat /tmp/ddns_test.log
else
    echo -e "${GREEN}ddns.sh 首次运行未发现明显错误。${NC}"
fi
rm -f /tmp/ddns_test.log

# 写systemd配置
echo -e "${GREEN}创建systemd服务...${NC}"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=自定义DDNS守护服务
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do bash $DDNS_PATH; sleep $SLEEP_SECOND; done'
Restart=always
RestartSec=10
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 2

echo
systemctl --no-pager status "$SERVICE_NAME" | head -20

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}\n✅ DDNS已安装&守护，服务名：$SERVICE_NAME，每$SLEEP_SECOND秒执行。\n"
    echo -e "${YELLOW}日志查看：  journalctl -u $SERVICE_NAME -f${NC}"
    echo -e "${YELLOW}最近日志：  journalctl -u $SERVICE_NAME -n 50 -e${NC}"
    echo -e "${YELLOW}重启服务：  systemctl restart $SERVICE_NAME${NC}"
    echo -e "${YELLOW}停止服务：  systemctl stop $SERVICE_NAME${NC}"
    echo -e "${YELLOW}禁用自启：  systemctl disable $SERVICE_NAME${NC}"
    echo -e "${GREEN}\n如脚本异常，请用上述日志命令结合ddns.sh排查！\n${NC}"
else
    echo -e "${RED}\n❌ 服务未正常启动，建议执行以下命令排查："
    echo "journalctl -u $SERVICE_NAME -n 50 -e"
    exit 1
fi
