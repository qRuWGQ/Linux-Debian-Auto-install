# Linux-Debian-Auto-install  

一键网络重装 Debian 12 纯净系统  

脚本运行要求：`Debian/Ubuntu` ｜ `Centos/Redhat`  

支持的引导方式和分区类型：`BIOS+MRB` ｜ `UEFI+GPT`  

目前测试通过的平台：
1. Dogyun  引导方式及分区：BIOS+MBR
2. vultr   引导方式及分区：UEFI+GPT
3. Aliyun  引导方式及分区：BIOS+MBR

其他自测，最好通过VNC控制台观察安装过程


### 一键脚本：
```shell
curl https://raw.githubusercontent.com/git-littlemo/Linux-Debian-Auto-install/main/Linux-Debian-AutoInstall.sh | bash
```
