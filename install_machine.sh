#!/usr/bin/env bash
# Install instructions:
# bash <(curl -Ls https://gist.githubusercontent.com/loohawe/3c970479774626b5d4949a756fd50aa5/raw/vps_install_nht.sh)

echo=echo
for cmd in echo /bin/echo; do
    $cmd >/dev/null 2>&1 || continue
    if ! $cmd -e "" | grep -qE '^-e'; then
        echo=$cmd
        break
    fi
done

# 设置颜色变量
CSI=$($echo -e "\033[")
CEND="${CSI}0m"
CDGREEN="${CSI}32m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"
CMAGENTA="${CSI}1;35m"
CCYAN="${CSI}1;36m"

# 输出函数
OUT_ALERT() { echo -e "${CYELLOW}$1${CEND}"; }
OUT_ERROR() { echo -e "${CRED}$1${CEND}"; }
OUT_INFO() { echo -e "${CCYAN}$1${CEND}"; }

# 通过ipinfo.io获取当前IP地址
OUT_INFO "获取当前IP地址信息..."
ip_info=$(curl -s --connect-timeout 5 https://ipinfo.io)
if [ $? -ne 0 ]; then
    OUT_ERROR "[错误] 无法获取IP地址信息，请检查网络连接后重试。"
    exit 1
fi

current_ip=$(echo "$ip_info" | grep -oP '"ip": "\K[^"]+')
if [ -z "$current_ip" ]; then
    OUT_ERROR "[错误] 无法解析IP地址信息，请检查网络连接后重试。"
    exit 1
fi

OUT_INFO "[成功] 网络连接正常，当前IP地址: ${CGREEN}${current_ip}${CCYAN}"

OUT_ALERT "[信息] 优化性能中！"

# 修改系统密码
OUT_INFO "设置系统密码..."
read -p "请输入新密码 (直接回车跳过): " password #-s hide input
echo ""
if [ -n "$password" ]; then
    echo "root:$password" | chpasswd
    OUT_INFO "系统密码已更新"
else
    OUT_INFO "未输入密码，跳过密码设置"
fi

# 获取域名参数
OUT_INFO "请输入域名前缀..."
read -p "请输入域名前缀: " domain_prefix

domain_suffix="loohawe.com"

# 设置服务密码
OUT_INFO "设置服务密码..."
read -p "请输入服务密码: " service_password
# 生成随机密码如果未输入, 则循环直到输入非空密码
while [ -z "$service_password" ]; do
    OUT_ERROR "服务密码不能为空，请重新输入。"
    read -p "请输入服务密码: " service_password
done
OUT_INFO "服务密码已设置"


# 设置主机名
OUT_INFO "设置主机名..."
read -p "请输入主机名 (默认随机生成): " hostname_input
if [ -z "$hostname_input" ]; then
    OUT_INFO "未输入主机名，跳过设置"
else
    hostname_new="$hostname_input"
    hostnamectl set-hostname $hostname_new
    echo "127.0.0.1 $hostname_new" >> /etc/hosts
    OUT_INFO "主机名已设置为: $hostname_new"
fi

# 配置VIM
OUT_INFO "配置VIM..."
cat << EOF > ~/.vimrc
syntax on
set tabstop=4
set expandtab
set nobackup
set mouse=a
set number

set termencoding=utf-8
set encoding=utf8
set fileencodings=utf8,ucs-bom,gbk,cp936,gb2312,gb18030
au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
EOF

# 设置时区
OUT_INFO "设置时区..."
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime || OUT_ERROR "设置时区失败"

# 安装基础软件包
OUT_INFO "安装基础软件包..."
apt install curl wget vim unzip haveged gpg ethtool net-tools sudo bc iperf3 jq lsof -y || OUT_ERROR "安装基础软件包失败"
systemctl enable haveged

# 配置Cloudflare DNS
OUT_INFO "配置Cloudflare DNS记录..."
zone_id="a9b03aaeb2188fe8d02260f0ce38b246"
read -p "请输入Cloudflare API Token: " cf_token

# 验证API Token和Zone ID
if [ -z "$cf_token" ] || [ -z "$zone_id" ]; then
    OUT_ERROR "Cloudflare API Token和Zone ID不能为空"
    exit 1
fi

# 定义需要创建的DNS记录
dns_records=(
    "${domain_prefix}-np.${domain_suffix}"
    "${domain_prefix}-hy.${domain_suffix}"
    "${domain_prefix}-tj.${domain_suffix}"
)

# 为每个域名创建或更新DNS记录
for domain in "${dns_records[@]}"; do
    OUT_INFO "处理域名: $domain"
    
    # 检查DNS记录是否存在
    record_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$domain&type=A" \
        -H "Authorization: Bearer $cf_token" \
        -H "Content-Type: application/json" | jq -r '.result[0].id // empty')
    
    if [ -n "$record_id" ] && [ "$record_id" != "null" ]; then
        # 更新现有记录
        OUT_INFO "更新现有DNS记录: $domain"
        response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
            -H "Authorization: Bearer $cf_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$current_ip\",\"ttl\":300}")
    else
        # 创建新记录
        OUT_INFO "创建新DNS记录: $domain"
        response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
            -H "Authorization: Bearer $cf_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$current_ip\",\"ttl\":300}")
    fi
    
    # 检查操作结果
    success=$(echo "$response" | jq -r '.success')
    if [ "$success" = "true" ]; then
        OUT_INFO "DNS记录处理成功: $domain -> $current_ip"
    else
        OUT_ERROR "DNS记录处理失败: $domain"
        echo "$response" | jq -r '.errors[]?.message // "未知错误"'
    fi
done

OUT_INFO "DNS配置完成"

# Append linux host file
echo "$current_ip ${domain_prefix}-np.${domain_suffix}" >> /etc/hosts
echo "$current_ip ${domain_prefix}-hy.${domain_suffix}" >> /etc/hosts
echo "$current_ip ${domain_prefix}-tj.${domain_suffix}" >> /etc/hosts

# 配置DNS
OUT_INFO "安装SmartDNS..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="x86_64" ;;
    i386|i686) ARCH="x86" ;;
    aarch64) ARCH="aarch64" ;;
    arm*) ARCH="arm" ;;
    mips*) ARCH="mips" ;;
    *) echo "Unsupported architecture: $ARCH" && exit 1 ;;
esac

URL=$(curl -s https://api.github.com/repos/pymumu/smartdns/releases \
  | jq -r --arg ARCH "$ARCH" '.[0].assets[] | select(.name | endswith(".\($ARCH)-debian-all.deb")) | .browser_download_url')

curl -Lo /tmp/smartdns.deb "$URL"  || OUT_ERROR "安装SmartDNS失败"
sudo dpkg -i /tmp/smartdns.deb

cat << EOF > /etc/smartdns/smartdns.conf
log-level warn
bind 127.0.0.1:53
cache-persist yes
cache-checkpoint-time 21600
prefetch-domain yes
force-qtype-SOA 65
# 开启 IPV6
force-AAAA-SOA yes
# 双栈优选
dualstack-ip-selection yes
# 允许只返回 AAAA。系统层面设置 IPV4 优先，如果碰到 IPV6 延迟优秀的情况下，如果返回了 IPV4 地址则系统会使用 IPV4，失去了双栈测试的意义。
dualstack-ip-allow-force-AAAA yes
tcp-idle-time 300

address /${domain_prefix}-np.${domain_suffix}/$current_ip
address /${domain_prefix}-hy.${domain_suffix}/$current_ip
address /${domain_prefix}-tj.${domain_suffix}/$current_ip

server 1.1.1.1
server 8.8.8.8
EOF
systemctl enable smartdns
service smartdns restart

service systemd-resolved stop
systemctl disable systemd-resolved
rm /etc/resolv.conf && echo 'nameserver 127.0.0.1' > /etc/resolv.conf
chattr +i /etc/resolv.conf


# 配置网站
OUT_INFO "配置网站..."
mkdir -p /var/www/html && cd /var/www/html
wget https://github.com/browserify/browserify-website/archive/gh-pages.zip || OUT_ERROR "下载网站文件失败"
unzip gh-pages.zip
mv -f browserify-website-gh-pages/* ./
rm -rf gh-pages.zip browserify-website-gh-pages

# 安装sing-box
OUT_INFO "安装sing-box..."
ARCH_RAW=$(uname -m)
case "${ARCH_RAW}" in
    'x86_64')    ARCH='amd64';;
    'x86' | 'i686' | 'i386')     ARCH='386';;
    'aarch64' | 'arm64') ARCH='arm64';;
    'armv7l')   ARCH='armv7';;
    's390x')    ARCH='s390x';;
    *)          OUT_ERROR "不支持的架构: ${ARCH_RAW}"; exit 1;;
esac

VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases \
    | grep tag_name \
    | cut -d ":" -f2 \
    | sed 's/\"//g;s/\,//g;s/\ //g;s/v//' \
    | head -1)

curl -Lo /tmp/sing-box.deb "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box_${VERSION}_linux_${ARCH}.deb"
sudo dpkg -i /tmp/sing-box.deb

systemctl enable sing-box || OUT_ERROR "启用sing-box服务失败"

# 创建sing-box配置
cat << EOF > /etc/sing-box/config.json || OUT_ERROR "创建sing-box配置失败"
{
    "log":
    {
        "disabled": false,
        "level": "error",
        "timestamp": true
    },
    "dns": {
        "strategy": "prefer_ipv4",
        "disable_cache": false,
        "servers": [
            {
                "type": "udp",
                "server": "127.0.0.1"
            }
        ]
    },
    "inbounds": [
        {
            "type": "naive",
            "tag": "naive_in",
            "listen": "::",
            "listen_port": 443,
            "tcp_fast_open": true,
            "users": [
                {
                "username": "koneey",
                "password": "${service_password}"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "${domain_prefix}-np.${domain_suffix}",
                "acme": {
                    "domain": ["${domain_prefix}-np.${domain_suffix}"],
                    "email": "me@loohawe.com",
                    "data_directory": "acme",
                    "provider": "letsencrypt"
                }
            }
        },
        {
            "type": "hysteria2",
            "tag": "hy2_in",
            "listen": "::",
            "listen_port": 443,
            "up_mbps": 100,
            "down_mbps": 1000,
            "users": [
                {
                    "name": "it-is-not-a-username",
                    "password": "${service_password}"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "${domain_prefix}-hy.${domain_suffix}",
                "alpn": [
                    "h3"
                ],
                "acme": {
                    "domain": ["${domain_prefix}-hy.${domain_suffix}"],
                    "email": "me@loohawe.com",
                    "data_directory": "acme",
                    "provider": "letsencrypt"
                }
            },
            "masquerade": "https://news.ycombinator.com/",
            "brutal_debug": false
        },
        {
            "type": "trojan",
            "tag": "trojan_in",
            "listen": "::",
            "listen_port": 443,
            "tcp_fast_open": true,
            "users": [
                {
                    "name": "stinging",
                    "password": "${service_password}"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "${domain_prefix}-tj.${domain_suffix}",
                "acme": {
                    "domain": ["${domain_prefix}-tj.${domain_suffix}"],
                    "email": "me@loohawe.com",
                    "data_directory": "acme",
                    "provider": "letsencrypt"
                }
            },
            "multiplex": {
                "enabled": true
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct-out"
        }
    ],
    "route": {
        "rules": [
            {
                "inbound": [
                    "naive_in", 
                    "hy2_in", 
                    "trojan_in"
                ],
                "action": "route",
                "outbound": "direct-out"
            },
            {
                "action": "route",
                "outbound": "direct-out"
            }
        ]
    }
}

EOF

service sing-box restart

# Open BBR
OUT_INFO "打开 BBR"
tee /etc/systemd/system/bbr-tcp.service >/dev/null <<'UNIT'
[Unit]
Description=Enable TCP BBR congestion control
DefaultDependencies=no
After=local-fs.target
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
# Ensure the kernel module is present (harmless if already built-in)
ExecStart=/sbin/modprobe tcp_bbr
# Set fq qdisc and BBR congestion control
ExecStart=/usr/sbin/sysctl -w net.core.default_qdisc=fq
ExecStart=/usr/sbin/sysctl -w net.ipv4.tcp_congestion_control=bbr
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now bbr-tcp.service

OUT_INFO "[信息] 优化完毕！"

# Naive Proxy 配置提示
OUT_INFO "Naive Proxy 配置:"
OUT_INFO "服务器地址: https://koneey:${service_password}@${domain_prefix}-np.${domain_suffix}:20443"

# Sing-Box Outbunds 配置提示
OUT_INFO "Sing-Box Outbunds 配置:"
cat << EOF
{
    "type": "hysteria2",
    "tag": "out_${hostname_input}_hy",
    "server": "${domain_prefix}-hy.${domain_suffix}",
    "server_port": 443,
    "up_mbps": 100,
    "down_mbps": 1000,
    "password": "${service_password}",
    "tls": {
        "enabled": true,
        "disable_sni": false
    },
    "brutal_debug": false
},
{
    "type": "trojan",
    "tag": "out_${hostname_input}_tj",
    "server": "${domain_prefix}-tj.${domain_suffix}",
    "server_port": 443,
    "password": "${service_password}",
    "network": "tcp"
}
EOF

# Surge 配置提示
OUT_INFO "Surge 配置提示:"
cat << EOF
[Proxy]
hy_${hostname_input} = hysteria2, ${domain_prefix}-hy.${domain_suffix}:10443, password=${service_password}, download-bandwidth=1000, block-quic=on
tj_${hostname_input} = trojan, ${domain_prefix}-tj.${domain_suffix}:18080, username=stinging, password=${service_password}, block-quic=on
EOF

# 询问是否需要重启系统
read -p "是否需要立即重启系统？(y/n): " restart_choice
if [[ $restart_choice == "y" || $restart_choice == "Y" ]]; then
    OUT_INFO "系统将在3秒后重启..."
    sleep 3
    reboot
else
    OUT_INFO "系统不会重启，您可以稍后手动重启。"
fi

exit 0

