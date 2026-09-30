# Server Toolbox PRO

面向 Linux VPS / 服务器的菜单化管理工具。目标是：**不需要记命令，也能完成常见服务器管理、排障和工具安装。**

## 核心功能

- Docker 容器中心：53 个常用容器，支持 Run / Compose、日志、进入容器、状态查看等
- 插件中心：42 个常用 Linux / 运维工具，按用途分类、搜索、状态检测、安装、升级、运行、卸载
- 命令工具中心：把常用 Linux 命令包装成人话菜单，覆盖端口、进程、服务、DNS/HTTPS、文件、网络、日志和用户信息
- 系统工具：系统更新、资源信息、BBR、Swap、时区、主机名、监听端口
- SSH 工具：改密、改端口、root 登录、安全模式
- 防火墙：UFW 安全开启、放行/关闭端口、规则查看
- 反代工具：Caddy / Nginx Proxy Manager 等
- Fail2ban：SSH 防暴力破解、封禁、解封、白名单
- 下载工具：aria2、rclone、yt-dlp 等
- 系统急救：DNS、网络、磁盘、Docker、APT、日志、备份恢复
- 热更新：版本号驱动，从 GitHub 更新核心、模块和配置

## 插件中心 V1.1.0

插件中心不再一次列出所有命令，而是按“你想做什么”来找工具。

主要分类：

- 基础工具：jq、git、tree、unzip、zstd
- 系统监控：btop、htop、glances、fastfetch
- 磁盘与性能：ncdu、iotop、smartmontools、fio、sysbench
- 网络诊断：mtr、traceroute、nmap、iperf3、iftop、nload、vnstat、lsof、socat、netcat、dig
- 终端与文件：tmux、screen、Midnight Commander、fzf、ripgrep
- 下载与传输：rsync、rclone、aria2、yt-dlp
- Docker 工具：ctop、lazydocker
- 备份工具：restic、borgbackup
- 安全检查：Lynis
- 远程组网：Tailscale、WireGuard、DDNS-GO

菜单支持：

```text
============== 插件中心 ==============
插件：42 个 / 已安装：N / 未安装：N

1) 推荐插件
2) 按分类浏览
3) 搜索插件
4) 全部插件
5) 已安装插件
6) 未安装插件
7) 一键安装推荐插件
0) 返回
```

每个插件进入详情后可以看到用途、当前状态、风险级别和项目地址，并按支持情况执行安装、升级、运行或卸载。

## 命令工具中心 V1.2.0

这一版继续贯彻“不需要先会 Linux 命令”的目标。进入命令工具中心后按任务选择：

```text
1) 端口 / 网络连接
2) 进程管理
3) systemd 服务管理
4) 域名 / DNS / HTTPS
5) 文件 / 磁盘
6) 网络诊断
7) 日志中心
8) 系统 / 用户信息

S) 搜索我要做的事
H) 查看最近执行命令
0) 返回
```

目前支持的高频操作包括：

- 查看所有监听端口、查询指定端口对应的进程和 Docker 映射
- 查看 TCP/UDP 连接和连接统计、测试远程端口
- CPU/内存 Top 进程、搜索进程、PID 详情、TERM/KILL 分级结束进程
- systemd 服务状态、启动、停止、重启、自启、取消自启、服务日志
- DNS A/AAAA/MX/TXT/NS 查询、完整 DNS 响应
- TLS/HTTPS 证书主题、签发者、有效期、指纹检查
- 网站 Header 和重定向链检查
- 磁盘容量、inode、目录大小、大文件、文件名搜索、文本搜索、最近修改文件
- 公网 IPv4/IPv6、网卡地址、路由、Ping、MTR/Traceroute、DNS 基础诊断
- 系统错误、启动日志、内核日志、SSH 日志、Docker 日志
- 系统概览、当前登录、登录历史、失败登录、sudo/wheel 用户
- 每次执行前显示真实 Linux 命令，并保留本机最近命令历史

停止服务、结束进程等修改型操作均要求确认；结束进程默认先发送 TERM，仅在用户再次确认后才使用 KILL。

## 主菜单

```text
1) Docker 容器中心
2) 系统工具
3) 插件中心
4) 下载工具
5) SSH 工具
6) 防火墙
7) 反代工具
8) 系统急救菜单
9) 手动更新
10) Fail2ban 防护中心
11) 命令工具中心
0) 退出
```

## 支持系统

- Debian / Ubuntu：推荐
- RHEL 系：尽量兼容 dnf / yum
- Alpine：部分插件支持 apk
- x86_64 / ARM64：核心脚本支持；具体第三方工具仍取决于上游

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/sockc/toolbox-pro/main/install.sh | bash
```

安装完成后：

```bash
toolbox
```

## 更新

进入 Toolbox 主菜单选择：

```text
9) 手动更新
```

V1.2.0 新增命令工具中心；V1.1.0 的插件中心、热更新地址修正和版本检查保护继续保留。

> 部分第三方工具会调用其官方安装脚本或 Docker 镜像。执行前可以在插件详情里查看用途和风险等级。
