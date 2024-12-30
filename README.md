# Linux-Debian-Auto-install  

一键网络重装 Debian 12 纯净系统  

脚本开源透明，安装包均来自官方，可放心食用

脚本运行要求:   
> 系统: `Debian/Ubuntu` ｜ `Centos/Redhat`  
> 引导方式和分区表类型: `BIOS+MBR` ｜ `UEFI+GPT`  

功能一览:  
• 自动识别引导方式和分区表类型  
• APT源选择  
• 自动选择网卡或手动指定  
• ROOT密码设定  
• 目前暂时只支持amd64架构，后续会支持多架构  
• 默认使用的是当前系统安装的磁盘进行自动分区，后续会支持手动指定要使用的硬盘  
• 目前安装的系统是 Debian 12，后续会支持其他版本的系统

目前测试过的平台:  
| 平台 | 引导方式 | 分区表类型 |
| --- | --- | --- |
| Dogyun | BIOS | MBR |
| 阿里云轻量云服务器 | BIOS | MBR |
| 阿里云轻量云服务器 | BIOS | GPT |
| Vultr  | UEFI | GPT |

~~正常情况一般都支持，除非你的分区表类型比较阴间，使用的是：`Hybrid MBR 混合分区表`, 那本脚本暂时不支持，目前已知不支持的平台：`HostKvm`~~  
问题已得到解决，现在支持使用gpt分区+bios引导的系统了

其他自测，最好通过VNC控制台观察安装过程

### 下载脚本：
```shell
curl -O https://raw.githubusercontent.com/git-littlemo/Linux-Debian-Auto-install/main/Linux-Debian-AutoInstall.sh && chmod +x ./Linux-Debian-AutoInstall.sh
```  
### 执行
```shell
./Linux-Debian-AutoInstall.sh
```