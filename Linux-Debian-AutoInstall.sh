#!/bin/bash

clear
set -u

echo
echo
echo '==========================='
echo '====Debian12 自动安装脚本===='
echo '==========================='
echo
echo

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
#disks=$(lsblk -d -n -o NAME,TYPE | grep ' disk' | awk '{print $1}')
disks=$(fdisk -l 2>/dev/null | grep "^Disk /" | awk '{print $2}' | sed 's/://g')

# 获取 /boot 目录所在磁盘的所有分区
partition=$(lsblk -o NAME -n $boot_device | sed 's/[^[:alnum:]]//g')

# 初始化磁盘编号和启动分区的位置
boot_disk_number=0
boot_partition_number=0

# 初始化计数器
disk_counter=0

# 遍历每个磁盘，判断 /boot 目录所在磁盘编号
for i in $disks; do
  device="/dev/$i"

  if [ "$device" = "$boot_device" ]; then
    boot_disk_number=$disk_counter
    break
  fi

  disk_counter=$((disk_counter + 1))
done

# 初始化计数器
disk_counter=0

# 遍历 /boot 目录所在磁盘的所有分区，判断 /boot 目录所在分区编号
for i in $partition; do
  device="/dev/$i"
  
  if [ "$device" = "$boot_partition" ]; then
    boot_partition_number=$disk_counter
    break
  fi
  
  disk_counter=$((disk_counter + 1))
done

# 判断 /boot 目录所在分区的挂载目录
boot_mout_dir=$(findmnt -n -o TARGET $boot_partition)
if [ "$boot_mout_dir" = "/boot" ]; then
  boot_mout_dir="/"
else
  boot_mout_dir="/boot/"
fi

mirror_list=(
  [0]=ftp.debian.org
  [1]=mirrors.tuna.tsinghua.edu.cn
  [2]=debian.csail.mit.edu
  [3]=mirror.xtom.com.hk
)

# 设置使用哪一个网卡
read -e -p "默认网口, auto 自动选择 : " -i "auto" interface
read -e -p "DNS : " -i "8.8.8.8 1.1.1.1" dnsaddr

if [ "$interface" = "auto" ] || [ -z "$interface" ]; then
  default_route=$(ip route | grep default)
  if [ -z "$default_route" ]; then
    echo "无法判断默认胃口，请手动填写网口名称"
    exit 1
  else
    interface=$(echo $default_route | awk '{print $5}')
  fi
else
  if ! ip link show "$interface" > /dev/null 2>&1; then
    echo "错误：网卡 $interface 不存在。"
    exit 1
  fi
fi

# 子网掩码转换
function cidr_to_mask() {
    local cidr=$1
    local mask=$(( (1 << 32) - (1 << (32 - cidr)) ))
    echo "$(( (mask >> 24) & 255 )).$(( (mask >> 16) & 255 )).$(( (mask >> 8) & 255 )).$(( mask & 255 ))"
}

#判断网络配置是dhcp或static，并获取ip和子网掩码
IP_METHOD=$(ip addr show "$interface" | grep "dynamic")
if [ ! -z "$IP_METHOD" ]; then
  interface_type="dhcp"
else
  interface_type="static"
  # 获取IP地址
  IP_ADDRESS=$(ip addr show $interface | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
  # 获取子网掩码
  SUBNET_MASK_CIDR=$(ip addr show $interface | grep 'inet ' | awk '{print $2}' | cut -d'/' -f2)
  SUBNET_MASK=$(cidr_to_mask $SUBNET_MASK_CIDR)
  # 获取网关IP地址
  GATEWAY=$(ip route | grep default | awk '{print $3}')
fi

echo
echo
echo '========选择下载和APT镜像源========='
echo "0. 默认 官方源      ${mirror_list[0]}"
echo "1. 中国 清华大学    ${mirror_list[1]}"
echo "2. 美国 麻省理工大学 ${mirror_list[2]}"
echo "3. 香港 中国无法访问 ${mirror_list[3]}"
echo

read -e -p "选择镜像源 [0-3] : " -i "0" mirror_index

mirror_domain=${mirror_list[mirror_index]}

debian_install_dir="/boot/debian-netboot-install"
rm -fr $debian_install_dir && mkdir -p $debian_install_dir
rm -fr ~/initrd && mkdir ~/initrd
wget -P ~/initrd https://${mirror_domain}/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz
wget -P $debian_install_dir https://${mirror_domain}/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux

echo
echo

echo '设置ROOT密码'
function set_root_pass() {
  root_pass=$(openssl passwd -6)
  if [ $? -eq 0 ]; then
    echo '密码设置成功'
    echo
    echo
  else
    echo
    echo '两次输入的密码不一致，重新输入'
    set_root_pass
  fi
}
set_root_pass

#function set_console_pass() {
#  read -e -p "临时SSH控制台密码 : " netconsole_pass
#  if [[ -z "$netconsole_pass" || ${#netconsole_pass} -lt 6 ]]; then
#    echo "密码为空或小于6位数…"
#    set_console_pass
#  fi
#}

#set_console_pass

# 生成preseed.cfg配置
wget -O preseed.sh https://raw.githubusercontent.com/git-littlemo/Linux-Debian-Auto-install/main/preseed.sh && source ./preseed.sh

# 解压initrd.gz，并生成preseed.cfg文件
cd ~/initrd
echo
echo
echo '解包中...'
gzip -d initrd.gz && cpio -idmu < initrd && echo '解包完成'
echo
echo '创建 pressed.cfg 文件并导入'
rm -fr initrd
cat <<EOF > ~/initrd/preseed.cfg
$preseed
EOF
echo
echo '重新归档压缩中...'
find . | cpio -H newc --create | gzip -9 > $debian_install_dir/initrd.gz && echo '归档压缩完成'
echo
echo

# 自定义启动项
cat <<EOF > /etc/grub.d/40_custom
#!/bin/sh
exec tail -n +3 \$0
# This file provides an easy way to add custom menu entries.  Simply type the
# menu entries you want to add after this comment.  Be careful not to change
# the 'exec tail' line above.
menuentry 'debian-netboot-install' {
set root=${partition}
linux ${boot_mout_dir}debian-netboot-install/linux auto=true priority=critical
initrd ${boot_mout_dir}debian-netboot-install/initrd.gz
}
EOF

# 删除启动项等待时间
sed -i '/^GRUB_TIMEOUT/d' /etc/default/grub

# 更新grub配置和选择下一次的启动项
if [[ "${release}" == "centos" ]]; then
  grub2-mkconfig -o /etc/grub2.cfg
  grub2-reboot "debian-netboot-install"
elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
  update-grub
  grub-reboot "debian-netboot-install"
fi

echo
echo
echo "配置完成，手动重启机器后开始自动安装，建议等待15-30分钟后尝试连接。注：带宽较慢或性能很差的机器可能需要更长时间！"
echo "如果要查看安装进度请连接VNC"
echo "某些环境下不一定能完全自动安装成功，可以通过VNC控制台进行手动操作下一步进行安装"
echo
echo
echo "SSH端口：22"
echo
echo
