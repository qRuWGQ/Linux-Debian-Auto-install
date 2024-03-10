#!/bin/bash

clear

set -e
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

echo
echo
echo '========选择APT镜像源========='
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

# 生成preseed.cfg配置
wget -O preseed.sh https://raw.githubusercontent.com/git-littlemo/Linux-Debian-Auto-install/dev/preseed.sh && source ./preseed.sh

# 解压initrd.gz，并生成preseed.cfg文件
cd ~/initrd
gzip -d < initrd.gz | cpio -id
cat <<'EOF' > ~/initrd/preseed.cfg
$preseed
EOF
rm -fr initrd.gz
find . | cpio -H newc --create | gzip -9 > $debian_install_dir/initrd.gz

# 设置使用哪一个网卡
read -e -p "网卡名称, 默认auto自动设置 : " -i "auto" interface
# 如果留空，将其设置为 'auto'
if [[ -z "$interface" ]]; then
  interface="auto"
fi

# 自定义启动项
cat <<EOF > /etc/grub.d/40_custom
#!/bin/sh
exec tail -n +3 \$0
# This file provides an easy way to add custom menu entries.  Simply type the
# menu entries you want to add after this comment.  Be careful not to change
# the 'exec tail' line above.
menuentry 'debian-netboot-install' {
set root=${partition}
linux ${boot_mout_dir}debian-netboot-install/linux auto=true priority=critical netcfg/choose_interface=$interface
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
echo "配置完成，手动重启机器后开始自动安装，建议等待15分钟后尝试连接。"
echo "如果要查看安装进度，可以连接VNC"
echo "SSH端：22，密码：123456abcd"
echo
echo
