# Linux-Debian-Auto-install  

一键网络重装 Debian 12 纯净系统  

脚本运行要求：  
> 系统：`Debian/Ubuntu` ｜ `Centos/Redhat`  
> 引导方式和分区类型：`BIOS+MRB` ｜ `UEFI+GPT`  

理论来说大部分系统都支持的，除非你的机器比较阴间：`BIOS+GPT`, 那本脚本暂时不支持。

目前测试过的平台：
1. Dogyun  引导方式及分区：BIOS+MBR
2. vultr   引导方式及分区：UEFI+GPT
3. Aliyun  引导方式及分区：BIOS+MBR

其他自测，最好通过VNC控制台观察安装过程


### 一键脚本：
```shell
curl https://raw.githubusercontent.com/git-littlemo/Linux-Debian-Auto-install/main/Linux-Debian-AutoInstall.sh | bash
```
