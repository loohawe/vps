#!/bin/bash
# Restore VPS script

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

# 获取备份目录参数
OUT_INFO "Input Backup Directory Path"
read -p "请输入备份目录路径: " backup_dir

restore_sing-box() {
    OUT_INFO "Restoring sing-box configuration and data..."

    sing_box_dir=${backup_dir}/sing-box
    sing_box_etc=${sing_box_dir}/etc
    sing_box_workdir=${sing_box_dir}/var

    # 恢复sing-box配置文件
    rsync -avz -e ssh ${sing_box_etc}/ ${host_ssh_config_name}:/etc/sing-box/ || { OUT_ERROR "恢复sing-box配置文件失败"; return 1; }
    # scp -r ${sing_box_etc}/* ${host_ssh_config_name}:/etc/sing-box/ || { OUT_ERROR "恢复sing-box配置文件失败"; return 1; }

    # 恢复sing-box工作目录
    rsync -avz -e ssh ${sing_box_workdir}/ ${host_ssh_config_name}:/var/lib/sing-box/ || { OUT_ERROR "恢复sing-box工作目录失败"; return 1; }

    OUT_INFO "sing-box restoration completed."
}

restore_smartdns() {
    OUT_INFO "Restoring smartdns configuration..."

    smartdns_dir=${backup_dir}/smartdns/etc

    # 恢复smartdns配置文件
    rsync -avz -e ssh ${smartdns_dir}/ ${host_ssh_config_name}:/etc/smartdns/ || { OUT_ERROR "恢复smartdns配置文件失败"; return 1; }

    OUT_INFO "smartdns restoration completed."
}

restore_ssh() {
    OUT_INFO "Restoring ssh configuration..."

    ssh_dir=${backup_dir}/ssh/etc

    # 恢复ssh配置文件
    rsync -avz -e ssh ${ssh_dir}/ ${host_ssh_config_name}:/etc/ssh/ || { OUT_ERROR "恢复ssh配置文件失败"; return 1; }

    OUT_INFO "ssh restoration completed."
}

# 遍历备份目录下的所有目录
for dir in ${backup_dir}/*; do
    # 获取dir目录路径中的最后一个component
    dir_name=${dir##*/}
    
    # 如果目录名为 sing-box，则跳转到对应的同步方法
    if [ "$dir_name" = "sing-box" ]; then
        # 检查方法是否存在，如果存在则调用
        if declare -f "restore_${dir_name}" > /dev/null; then
            restore_${dir_name}
        else
            OUT_ALERT "Method restore_${dir_name} not found, skipping..."
        fi
    # 如果目录名为 smartdns，则跳转到对应的同步方法
    elif [ "$dir_name" = "smartdns" ]; then
        if declare -f "restore_${dir_name}" > /dev/null; then
            restore_${dir_name}
        else
            OUT_ALERT "Method restore_${dir_name} not found, skipping..."
        fi
    # 如果目录名为 ssh，则跳转到对应的同步方法
    elif [ "$dir_name" = "ssh" ]; then
        if declare -f "restore_${dir_name}" > /dev/null; then
            restore_${dir_name}
        else
            OUT_ALERT "Method restore_${dir_name} not found, skipping..."
        fi
    else
        OUT_ALERT "No restoration method for directory: $dir_name, skipping..."
    fi
done