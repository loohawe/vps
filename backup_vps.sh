#!/bin/bash
# Backup VPS script

# set -ex

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

# 获取域名参数
OUT_INFO "Input Host SSH Config Name"
read -p "请输入主机名: " host_ssh_config_name

backup_dir=${HOME}/Downloads/${host_ssh_config_name}-backup-0
while [[ -d "$backup_dir" ]]; do
    # Extract the number at the end and increment it
    if [[ "$backup_dir" =~ -([0-9]+)$ ]]; then
        num=${BASH_REMATCH[1]}
        ((num++))
        backup_dir="${backup_dir%-*}-${num}"
    fi
done

mkdir -p ${backup_dir} || { OUT_ERROR "创建备份目录失败"; exit 1; }

sing_box_dir=${backup_dir}/sing-box
mkdir -p ${sing_box_dir} || { OUT_ERROR "创建sing-box备份目录失败"; exit 1; }

sing_box_etc=${sing_box_dir}/etc
mkdir -p ${sing_box_etc} || { OUT_ERROR "创建sing-box配置备份目录失败"; exit 1; }
# rsync -avz -e ssh ${host_ssh_config_name}:/etc/sing-box/ ${sing_box_etc}/ || { OUT_ERROR "备份sing-box配置文件失败"; exit 1; }
scp -r ${host_ssh_config_name}:/etc/sing-box/* ${sing_box_etc}/ || { OUT_ERROR "备份sing-box配置文件失败"; exit 1; }

sing_box_workdir=${sing_box_dir}/var
mkdir -p ${sing_box_workdir} || { OUT_ERROR "创建sing-box工作目录备份目录失败"; exit 1; }
# rsync -avz -e ssh ${host_ssh_config_name}:/var/lib/sing-box/ ${sing_box_workdir}/ || { OUT_ERROR "备份sing-box工作目录失败"; exit 1; }
scp -r ${host_ssh_config_name}:/var/lib/sing-box/* ${sing_box_workdir}/ || { OUT_ERROR "备份sing-box工作目录失败"; exit 1; }

OUT_INFO "备份完成，备份文件位于: ${backup_dir}"
