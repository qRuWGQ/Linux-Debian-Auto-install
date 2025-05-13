#!/bin/bash
set -u

declare os_type="unknown"
declare -A mirror_url=(
  [0]=ftp.debian.org
  [1]=mirrors.aliyun.com
  [2]=mirrors.163.com
  [3]=mirrors.tuna.tsinghua.edu.cn
  [4]=mirror.xtom.com.hk
  [5]=debian.csail.mit.edu
)

# 检查系统架构
function is_arch() {
  local -n conf=$1
  local arch=$(uname -m)

  case "$arch" in
  x86_64 | amd64)
    conf["arch"]="amd64"
    return 0
    ;;
  i386 | i686)
    conf["arch"]="i386"
    return 0
    ;;
  aarch64 | arm64)
    conf["arch"]="arm64"
    return 0
    ;;
  *)
    echo -e "\033[31m不支持当前架构:\033[0m ${arch}" >&2
    exit 1
    ;;
  esac
}

# 获取系统版本
function get_os() {
  local issue
  local version

  # 提取公共逻辑为函数
  function check_os() {
    local content=$1
    if grep -q -E -i "ubuntu" <<<"$content"; then
      echo "ubuntu"
    elif grep -q -E -i "debian" <<<"$content"; then
      echo "debian"
    elif grep -q -E -i "centos|red hat|redhat" <<<"$content"; then
      echo "centos"
    else
      echo "unknown"
    fi
  }

  if [[ -f /etc/redhat-os_type ]]; then
    os_type="centos"
  elif [[ -f /etc/debian_version ]]; then
    os_type="debian"
  elif [[ -f /etc/issue ]]; then
    issue=$(cat /etc/issue)
    os_type=$(check_os "$issue")
  elif [[ -f /proc/version ]]; then
    version=$(cat /proc/version)
    os_type=$(check_os "$version")
  fi

  if [[ "$os_type" == "unknown" ]]; then
    echo -e "\033[31m不支持当前系统:\033[0m ${os_type}" >&2
    exit 1
  else
    echo "$os_type"
  fi
}

# 网络配置
function gen_network_conf() {
  local -n conf=$1
  local net_interface
  local net_dns
  # 设置使用哪一个网口
  read -e -p "默认网口, 例如 eth0, 留空或 auto 将自动选择 : " -i "auto" net_interface
  read -e -p "DNS : " -i "8.8.8.8 1.1.1.1" net_dns

  conf["net_interface"]="$net_interface"
  conf["net_dns"]="$net_dns"

  # 获取默认网口名称
  if [[ ${conf["net_interface"]} == "auto" ]] || [[ -z ${conf["net_interface"]} ]]; then
    # 尝试通过路由获取网口名称
    conf["net_interface"]=$(ip -o -4 route get 1.1.1.1 2>/dev/null | awk '{print $5}')

    # 尝试通过默认路由获取网口名称
    if [[ -z ${conf["net_interface"]} ]]; then
      local default_route=$(ip route | grep default)
      if [ -z "$default_route" ]; then
        echo "无法判断默认网口，请手动填写网口名称"
        exit 1
      else
        conf["net_interface"]=$(echo "$default_route" | awk '{print $5}')
      fi
    fi
  else
    if ! ip link show ${conf["net_interface"]} >/dev/null 2>&1; then
      echo "错误：指定的网口 ${conf["net_interface"]} 不存在。"
      exit 1
    fi
  fi

  # 判断网络配置是dhcp或static
  is_dynamic=$(ip -o -4 addr show ${conf["net_interface"]} | grep "dynamic")
  if [[ "$is_dynamic" ]]; then
    conf["net_interface_type"]="dhcp"
  else
    conf["net_interface_type"]="static"
  fi

  # 获取IP地址
  conf["net_ipaddr"]=$(ip -o -4 addr show ${conf["net_interface"]} | awk '{print $4}' | cut -d'/' -f1)

  # 获取网关IP地址
  conf["net_gateway"]=$(ip route | grep default | awk '{print $3}')

  # 使用 ip 命令获取子网掩码（CIDR 格式）
  local prefix=$(ip -o -4 addr show ${conf["net_interface"]} 2>/dev/null | awk '{print $4}' | cut -d/ -f2)

  if [[ -z "$prefix" ]]; then
    echo "无法获取子网掩码" >&2
    exit 1
  fi

  # 转换 CIDR 前缀为点分十进制格式
  local mask=""
  local full=$((0xffffffff ^ ((1 << (32 - prefix)) - 1)))

  # 构建点分十进制格式
  for i in {3..0}; do
    local octet=$(((full >> (i * 8)) & 0xff))
    mask="$mask$octet"
    if [[ "$i" -gt 0 ]]; then
      mask="$mask."
    fi
  done

  # 设置子网掩码
  conf["net_subnet_mask"]="$mask"
}

# 生成boot相关配置
function gen_boot_conf() {
  local -n conf=$1
  local boot_partition
  local boot_device
  local boot_partition_s
  local all_disk
  local for_index

  # 获取 /boot 目录所在分区（例如 /dev/sda1）
  boot_partition=$(df /boot | awk 'NR==2 {print $1}')

  # 获取 /boot 目录所在磁盘（例如 /dev/sda）
  conf["boot_device"]=${boot_partition%[0-9]*}

  # 检查 /boot 是否被单独挂载
  if grep -q " /boot " /proc/mounts; then
    # /boot 是单独挂载的分区
    conf["grub_root_path"]="/"
  else
    # /boot 不是单独挂载的，而是根文件系统的一部分
    conf["grub_root_path"]="/boot/"
  fi

  # 获取所有磁盘
  all_disk=$(fdisk -l 2>/dev/null | grep "^Disk /" | awk '{print $2}' | sed 's/://g')

  # 获取 /boot 目录所在磁盘的所有分区
  boot_partition_s=$(lsblk -o NAME -n ${conf["boot_device"]} | sed 's/[^[:alnum:]]//g')

  # /boot 所在磁盘索引
  conf["boot_disk_index"]=0

  # /boot 所在分区索引
  conf["boot_partition_index"]=0

  # for 循环索引
  for_index=0

  # 遍历所有磁盘，获得 /boot 所在磁盘索引
  for i in $all_disk; do
    if [[ "$i" == ${conf["boot_device"]} ]]; then
      conf["boot_disk_index"]="$for_index"
      break
    fi
    ((for_index++))
  done

  # for 循环索引
  for_index=0

  # 遍历 /boot 目录所在磁盘的所有分区，获得 /boot 所在分区索引
  for i in $boot_partition_s; do
    if [[ "/dev/$i" == "$boot_partition" ]]; then
      conf["boot_partition_index"]="$for_index"
      break
    fi

    ((for_index++))
  done
}

# 生成preseed配置
function gen_preseed_conf() {
  local -n conf=$1
  local partition_table_type
  local boot_method
  local partman
  local network_static
  local preseed

  # 检测分区表类型
  partition_table_type=$(fdisk -l ${conf["boot_device"]} 2>/dev/null | grep 'Disklabel type' | awk '{print $3}')

  conf["grub_root"]="hd${conf["boot_disk_index"]}"

  if [[ ${conf["boot_partition_index"]} -ge 1 ]]; then
    conf["grub_root"]+=",${conf["boot_partition_index"]}"
  fi

  if [[ "$partition_table_type" = "gpt" ]]; then
    # 判断是否是UEFI引导
    if [ -d "/sys/firmware/efi/efivars" ]; then
      read -r -d '' boot_method <<'EOF'
d-i partman-partitioning/choose_label select gpt
d-i partman-partitioning/default_label string gpt
d-i partman-auto/choose_recipe select boot-root
d-i partman-auto/expert_recipe string                   \
boot-root ::                                            \
        512 512 1024 free                               \
                $iflabel{ gpt }                         \
                $reusemethod{ }                         \
                method{ efi } format{ }                 \
        .                                               \
        512 512 1024 ext4                               \
                $primary{ } $bootable{ }                \
                method{ format } format{ }              \
                use_filesystem{ } filesystem{ ext4 }    \
                mountpoint{ /boot }                     \
        .                                               \
        1000 10000 1000000000 ext4                      \
                method{ format } format{ }              \
                use_filesystem{ } filesystem{ ext4 }    \
                mountpoint{ / }                         \
        .                                               \
        512 1024 200% linux-swap                        \
                method{ swap } format{ }                \
        .
EOF
    else
      read -r -d '' boot_method <<'EOF'
d-i partman-partitioning/choose_label select gpt
d-i partman-partitioning/default_label string gpt
d-i partman-auto/choose_recipe select boot-root
d-i partman-auto/expert_recipe string                   \
boot-root ::                                            \
        1 1 1 free                                      \
                method{ bios_grub }                     \
        .                                               \
        512 512 1024 ext4                               \
                $primary{ } $bootable{ }                \
                method{ format } format{ }              \
                use_filesystem{ } filesystem{ ext4 }    \
                mountpoint{ /boot }                     \
        .                                               \
        1000 10000 1000000000 ext4                      \
                method{ format } format{ }              \
                use_filesystem{ } filesystem{ ext4 }    \
                mountpoint{ / }                         \
        .                                               \
        512 1024 200% linux-swap                        \
                method{ swap } format{ }                \
        .
EOF
    fi

  else
    read -r -d '' boot_method <<'EOF'
d-i partman-auto/choose_recipe select boot-root
d-i partman-auto/expert_recipe string                         \
      boot-root ::                                            \
              512 512 1024 ext4                               \
                      $primary{ } $bootable{ }                \
                      method{ format } format{ }              \
                      use_filesystem{ } filesystem{ ext4 }    \
                      mountpoint{ /boot }                     \
              .                                               \
              1000 10000 1000000000 ext4                      \
                      method{ format } format{ }              \
                      use_filesystem{ } filesystem{ ext4 }    \
                      mountpoint{ / }                         \
              .                                               \
              512 1024 200% linux-swap                        \
                      method{ swap } format{ }                \
              .
EOF

  fi

  read -r -d '' partman <<EOF
d-i partman-auto/method string regular
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true
${boot_method}
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
EOF

  # 判断网络模式是否为static
  network_static=""
  if [[ ${conf["net_interface_type"]} == "static" ]]; then
    read -r -d '' network_static <<EOF
d-i netcfg/disable_autoconfig boolean true
d-i netcfg/dhcp_failed note
d-i netcfg/dhcp_options select Configure network manually
d-i netcfg/get_ipaddress string ${conf["net_ipaddr"]}
d-i netcfg/get_netmask string ${conf["net_subnet_mask"]}
d-i netcfg/get_gateway string ${conf["net_gateway"]}
d-i netcfg/confirm_static boolean true
EOF
  fi

  read -r -d '' preseed <<EOF
# 低内存模式
d-i lowmem/low boolean true
d-i lowmem/insufficient boolean true

# 语言和地区
d-i debian-installer/locale string en_US.UTF-8
d-i debian-installer/country string US
d-i debian-installer/language string en
d-i keyboard-configuration/xkb-keymap select us

# 设置时区
d-i clock-setup/utc boolean true
d-i time/zone string Asia/Hong_Kong

# 网络设置
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string debian
d-i netcfg/get_nameservers string ${conf["net_dns"]}
${network_static}

# 网络控制台模块
#d-i anna/choose_modules string network-console
#d-i preseed/early_command string anna-install network-console
# 设置网络控制台的密码，默认用户名： installer
#d-i network-console/password password 123456
#d-i network-console/password-again password 123456

# 设置镜像源
d-i mirror/country string manual
d-i mirror/http/hostname string ${conf["mirror_domain"]}
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

# 分区设置
d-i partman-auto/disk string ${conf["boot_device"]}
${partman}

# 设置root用户密码
d-i passwd/root-login boolean true
d-i passwd/root-password-crypted password ${conf["root_pass"]}
d-i passwd/make-user boolean false

# 配置apt和软件选择
tasksel tasksel/first multiselect standard
d-i pkgsel/include string openssh-server build-essential
d-i apt-setup/non-free boolean true
d-i apt-setup/contrib boolean true
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/cdrom/set-next boolean false
d-i apt-setup/cdrom/set-failed boolean false

popularity-contest popularity-contest/participate boolean false

# 安装GRUB引导加载程序
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string ${conf["boot_device"]}

# 安装完成后执行命令
d-i preseed/late_command string \
  in-target sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config ; \
  in-target systemctl restart ssh.service

# 重启通知
d-i finish-install/reboot_in_progress note
EOF

  cd /root/initrd || { echo "打开目录 /root/initrd 失败，脚本结束"; exit 1; }
  echo
  echo
  echo '解包中...'
  gzip -d initrd.gz && cpio -idmu <initrd && echo '解包完成'
  rm -fr initrd
  echo
  echo '生成 pressed 配置并写入'
  echo "$preseed" > /root/initrd/preseed.cfg
  echo
  echo '重新归档压缩中...'
  find . | cpio -H newc --create | gzip -9 >"${conf["mirror_dir"]}"/initrd.gz && echo '归档压缩完成'
}

# 设置镜像
function set_mirror() {
  local -n conf=$1
  local index

  echo
  echo
  echo '========选择镜像源========='
  echo
  echo "0. 默认 官方源"
  echo "1. 中国 阿里云"
  echo "2. 中国 网易"
  echo "3. 中国 清华大学"
  echo "4. 香港 Xtom 注：中国无法访问"
  echo "5. 美国 麻省理工"
  echo

  read -e -p "选择镜像源 [0-5] : " -i "0" index

  conf["mirror_domain"]=${mirror_url[$index]}

  conf["mirror_dir"]="/boot/debian-netboot-install"
  rm -fr ${conf["mirror_dir"]} && mkdir -p ${conf["mirror_dir"]}
  rm -fr /root/initrd && mkdir /root/initrd

  local down_url="https://${conf["mirror_domain"]}/debian/dists/bookworm/main/installer-${conf["arch"]}/current/images/netboot/debian-installer/${conf["arch"]}"

  wget -P /root/initrd "${down_url}/initrd.gz" || { echo "下载 initrd.gz 失败，重试或更换镜像源"; exit 1; }
  wget -P ${conf["mirror_dir"]} "${down_url}/linux" || { echo "下载 linux 失败，重试或更换镜像源"; exit 1; }
}

function gen_root_pass() {
  local -n conf=$1
  echo '设置ROOT密码'
  echo '屏幕不会显示输入内容，输入后回车再重复一次'
  conf["root_pass"]=$(openssl passwd -6)
  if [ $? -eq 0 ]; then
    echo '密码设置成功'
    return 0
  else
    echo
    echo '两次输入的密码不一致，重新输入'
    gen_root_pass
  fi
}

# 更新grub
function up_grub() {
  local -n conf=$1

  # 自定义启动项
  cat <<EOF >/etc/grub.d/40_custom
#!/bin/sh
exec tail -n +3 \$0
# This file provides an easy way to add custom menu entries.  Simply type the
# menu entries you want to add after this comment.  Be careful not to change
# the 'exec tail' line above.
menuentry 'debian-netboot-install' {
set root=${conf["grub_root"]}
linux ${conf["grub_root_path"]}debian-netboot-install/linux auto=true priority=critical
initrd ${conf["grub_root_path"]}debian-netboot-install/initrd.gz
}
EOF

  # 删除启动项等待时间
  sed -i '/^GRUB_TIMEOUT/d' /etc/default/grub

  # 更新grub配置和选择下一次的启动项
  if [[ "${os_type}" == "centos" ]]; then
    grub2-mkconfig -o /etc/grub2.cfg
    grub2-reboot "debian-netboot-install"
  elif [[ "${os_type}" == "debian" || "${os_type}" == "ubuntu" ]]; then
    update-grub
    grub-reboot "debian-netboot-install"
  fi
}

#function set_console_pass() {
#  read -e -p "临时SSH控制台密码 : " netconsole_pass
#  if [[ -z "$netconsole_pass" || ${#netconsole_pass} -lt 6 ]]; then
#    echo "密码为空或小于6位数…"
#    set_console_pass
#  fi
#}
#set_console_pass

# 启动函数
function start() {
  clear

  echo
  echo
  echo '==========================='
  echo '====Debian12 自动安装脚本===='
  echo '==========================='
  echo
  echo

  declare -A config

  is_arch config

  local os_type=$(get_os)

  case "$os_type" in
  debian | ubuntu)
    apt install -y wget
    ;;
  centos)
    yum install -y wget
    ;;
  esac

  echo

  gen_network_conf config

  gen_boot_conf config

  echo
  gen_root_pass config

  set_mirror config

  gen_preseed_conf config

  up_grub config

  echo
  echo
  echo "配置完成，手动重启机器后开始自动安装，建议等待15-30分钟后尝试连接。"
  echo
  echo "注意：带宽较慢或性能较差的机器可能需要更长时间！"
  echo
  echo "如果要查看安装进度请连接VNC"
  echo
  echo "某些环境不一定能完全自动安装成功，如果长时间未能登录SSH，自行前往VNC控制台进行查看或操作"
  echo
  echo
  echo "SSH端口：22"
  echo
  echo "自行输入：reboot 进行重启，后续等待自动安装即可"
  echo
}

start
