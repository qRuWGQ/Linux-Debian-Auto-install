#!/bin/bash

clear

echo ''
echo ''
echo '=========================='
echo '=====Debian12 自动安装脚本====='
echo '=========================='
echo ''
echo ''

if [[ -f /etc/redhat-release ]]; then
  release="centos"
elif cat /etc/issue | grep -q -E -i "debian"; then
  release="debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
  release="ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
  release="centos"
elif cat /proc/version | grep -q -E -i "debian"; then
  release="debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
  release="ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
  release="centos"
  fi

[[ ${release} != "debian" ]] && [[ ${release} != "ubuntu" ]] && [[ ${release} != "centos" ]] && echo -e "${Error} 本脚本不支持当前系统 ${release} !" && exit 1

if [[ "${release}" == "centos" ]]; then
    yum -y install wget
elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
    apt-get -y install wget
fi

# 获取 /boot 目录所在分区（例如 /dev/sda1）
boot_partition=$(df /boot | awk 'NR==2 {print $1}')

# 获取 /boot 目录所在磁盘（例如 /dev/sda）
boot_device=$(echo $boot_partition | sed 's/[0-9]*$//')

# 获取所有磁盘
disks=$(lsblk -d -n -o NAME,TYPE | grep ' disk' | awk '{print $1}')

# 获取 /boot 所在磁盘的所有分区
partition=$(lsblk -o NAME -n $boot_device | sed 's/[^[:alnum:]]//g')

# 初始化磁盘编号和启动分区的位置
boot_disk_number=0
boot_partition_number=0

# 初始化计数器
disk_counter=0

# 遍历每个磁盘，判断 /boot 目录所在磁盘编号
for disk in $disks; do
    device="/dev/$disk"

    if [ "$device" = "$boot_device" ]; then
        boot_disk_number=$disk_counter
        break
    fi

    disk_counter=$((disk_counter + 1))
done

# 初始化计数器
disk_counter=0

# 遍历 /boot 所在磁盘的所有分区，判断 /boot 目录所在分区编号
for disk in $partition; do
    device="/dev/$disk"
    
    if [ "$device" = "$boot_partition" ]; then
        boot_partition_number=$disk_counter
        break
    fi
    
    disk_counter=$((disk_counter + 1))
done

# 检测分区表类型
partition_table_type=$(fdisk -l $boot_device 2>/dev/null | grep 'Disklabel type' | awk '{print $3}')

if [ "$partition_table_type" = "gpt" ]; then
    # 对于GPT分区表的处理
    if [ $boot_partition_number -eq 0 ]; then
        partition="hd$boot_disk_number"
    else
        partition="hd$boot_disk_number,gpt$boot_partition_number"
    fi
    preseed_cfg="https://raw.githubusercontent.com/git-littlemo/Linux-Debian-Auto-install/main/preseed-GPT.cfg"
else
    # 对于MBR分区表的原有处理
    if [ $boot_partition_number -eq 0 ]; then
        partition="hd$boot_disk_number"
    else
        partition="hd$boot_disk_number,msdos$boot_partition_number"
    fi
    preseed_cfg="https://raw.githubusercontent.com/git-littlemo/Linux-Debian-Auto-install/main/preseed-MBR.cfg"
fi

# 判断 /boot 目录是否挂在在根目录
boot_mout_dir=$(findmnt -n -o TARGET $boot_partition)

if [ "$boot_mout_dir" = "/boot" ]; then
    boot_mout_dir="/"
else
    boot_mout_dir="/boot/"
fi

rm -fr /boot/debian-netboot-install

mkdir /boot/debian-netboot-install

wget -P /boot/debian-netboot-install https://mirror.xtom.com.hk/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz

wget -P /boot/debian-netboot-install https://mirror.xtom.com.hk/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux

interface=$1

# 如果没有提供网络接口名称，将其设置为 'auto'
if [[ -z "$interface" ]]; then
    interface="auto"
fi

cat > /etc/grub.d/40_custom << EOF
#!/bin/sh
exec tail -n +3 \$0
# This file provides an easy way to add custom menu entries.  Simply type the
# menu entries you want to add after this comment.  Be careful not to change
# the 'exec tail' line above.
menuentry 'debian-netboot-install' {
set root=$partition
linux ${boot_mout_dir}debian-netboot-install/linux auto=true priority=critical netcfg/choose_interface=$interface preseed/url=$preseed_cfg
initrd ${boot_mout_dir}debian-netboot-install/initrd.gz
}
EOF

sed -i '/^GRUB_TIMEOUT/d' /etc/default/grub

if [[ "${release}" == "centos" ]]; then
  grub2-mkconfig -o /etc/grub2.cfg
  grub2-reboot "debian-netboot-install"
elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
  update-grub
  grub-reboot "debian-netboot-install"
fi

echo ''
echo ''
echo ''
echo "配置完成，手动重启机器后开始自动安装，建议等待15-30分钟后尝试连接。"
echo "如果要查看安装进度，可以连接VNC"
echo "SSH端：22，密码：123456abcd"
echo ''
echo ''
