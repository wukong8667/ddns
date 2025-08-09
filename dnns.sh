#!/bin/bash

# ======= 配置区, 请只修改等号后内容 =======
CFKEY="9283f23fbac13705d7301e32919609e4f743a"
CFUSER="wukong8667@gmail.com"
CFZONE_NAME="cfcdndns.top"
CFRECORD_NAME="hk01.cfcdndns.top"
# ========== 配置区结束 =========

set -e

GREEN='\033[32m'
RED='\033[31m'
NC='\033[0m'

echo -e "${GREEN}======= Cloudflare DDNS 一键安装 =======${NC}"

# ======= 自动安装 wget curl ===============
check_and_install() {
    pkg="$1"
    if ! command -v "$pkg" &>/dev/null; then
        echo "正在安装 $pkg..."
        if command -v apt &>/dev/null; then apt update && apt install -y "$pkg";
        elif command -v yum &>/dev/null; then yum install -y "$pkg";
        else
            echo -e "${RED}不支持自动安装$pkg，请手动安装！${NC}"; exit 1
        fi
    fi
}

check_and_install wget
check_and_install curl

# ===== 自动安装 cron/crontab（防止相关报错） =====
if ! command -v crontab &>/dev/null; then
    echo "正在自动安装 cron/crontab..."
    if command -v apt &>/dev/null; then
        apt update && apt install -y cron
        systemctl enable cron || true
        systemctl start cron || true
    elif command -v yum &>/dev/null; then
        yum install -y cronie
        systemctl enable crond || true
        systemctl start crond || true
    else
        echo -e "${RED}未知系统，请手动安装cron/crontab！${NC}"
        exit 1
    fi
fi

# 下载脚本
cd /root || exit 1
wget -N --no-check-certificate https://raw.githubusercontent.com/yulewang/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh

if [ ! -f /root/cf-v4-ddns.sh ]; then
    echo -e "${RED}Cloudflare 动态DNS脚本下载失败，请检查网络！${NC}"
    exit 1
fi

chmod +x /root/cf-v4-ddns.sh

# 自动填充参数
sed -i "s/^CFKEY=.*/CFKEY=${CFKEY}/" /root/cf-v4-ddns.sh
sed -i "s/^CFUSER=.*/CFUSER=${CFUSER}/" /root/cf-v4-ddns.sh
sed -i "s/^CFZONE_NAME=.*/CFZONE_NAME=${CFZONE_NAME}/" /root/cf-v4-ddns.sh
sed -i "s/^CFRECORD_NAME=.*/CFRECORD_NAME=${CFRECORD_NAME}/" /root/cf-v4-ddns.sh

echo -e "${GREEN}参数已写入脚本，正在测试运行...${NC}"
bash /root/cf-v4-ddns.sh

# 定时任务
if ! (crontab -l 2>/dev/null | grep -q "/root/cf-v4-ddns.sh"); then
    (crontab -l 2>/dev/null; echo "*/1 * * * * /root/cf-v4-ddns.sh >/dev/null 2>&1") | crontab -
    echo -e "${GREEN}已添加定时任务，每分钟自动更新！${NC}"
else
    echo -e "${GREEN}定时任务已存在。${NC}"
fi

echo -e "${GREEN}Cloudflare DDNS 一键完成！请在Cloudflare控制台检查。${NC}"
