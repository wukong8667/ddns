#!/bin/bash

# =========== 配置区(请按实际填写) ===================
CFKEY="9283f23fbac13705d7301e32919609e4f743a"
CFUSER="wukong8667@gmail.com"
CFZONE_NAME="cfcdndns.top"
CFRECORD_NAME="hk01.cfcdndns.top"

DDNS_PATH="/root/ddns.sh"
CRON_EXPRESSION="*/1 * * * *"
# ===================================================

set -e

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

echo -e "${GREEN}========= DDNS Cron Setup ==========${NC}"

# 检查 ddns.sh 是否存在
if [[ ! -f "$DDNS_PATH" ]]; then
    echo -e "${RED}未找到 $DDNS_PATH！请确保 ddns.sh 已上传到此路径。${NC}"
    exit 1
fi

chmod +x "$DDNS_PATH"

# 注入参数
echo -e "${GREEN}写入 Cloudflare 参数到 ddns.sh...${NC}"
sed -i "s/^CFKEY=.*/CFKEY=\"$CFKEY\"/" "$DDNS_PATH"
sed -i "s/^CFUSER=.*/CFUSER=\"$CFUSER\"/" "$DDNS_PATH"
sed -i "s/^CFZONE_NAME=.*/CFZONE_NAME=\"$CFZONE_NAME\"/" "$DDNS_PATH"
sed -i "s/^CFRECORD_NAME=.*/CFRECORD_NAME=\"$CFRECORD_NAME\"/" "$DDNS_PATH"

# 检查参数是否真的写入
for key in CFKEY CFUSER CFZONE_NAME CFRECORD_NAME; do
    val=$(grep "^$key=" "$DDNS_PATH" | cut -d= -f2-)
    if [[ -z "$val" || "$val" == '""' ]]; then
        echo -e "${RED}参数 $key 注入失败，请检查 ddns.sh 脚本内容！${NC}"
        exit 1
    fi
done

# 检查是否安装了 cron
if ! command -v cron &> /dev/null; then
    echo -e "${YELLOW}cron 未安装，正在安装...${NC}"
    # 根据 Linux 发行版的不同，安装命令可能不同
    if [[ -f /etc/debian_version ]]; then
        apt update && apt install -y cron
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y cronie
    else
        echo -e "${RED}无法识别的操作系统，手动安装 cron!${NC}"
        exit 1
    fi
fi

# 确保 cron 服务已经启动
if ! systemctl is-active --quiet cron; then
    echo -e "${YELLOW}启动 cron 服务...${NC}"
    systemctl start cron
    systemctl enable cron
fi

# 设置 crontab 任务
(crontab -l 2>/dev/null; echo "$CRON_EXPRESSION $DDNS_PATH >/dev/null 2>&1") | crontab -

echo
echo -e "${GREEN}===============================${NC}"
echo -e "${GREEN}DDNS 已通过 cron 实现每分钟定时更新${NC}"
