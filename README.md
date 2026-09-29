# Server Toolbox PRO

面向 Linux VPS / 服务器的菜单化管理工具。目标是：**不需要记命令，也能完成常见服务器管理、排障和工具安装。**

## 核心功能

- Docker 容器中心：53 个常用容器，支持 Run / Compose、日志、进入容器、状态查看等
- 插件中心：42 个常用 Linux / 运维工具，按用途分类、搜索、状态检测、安装、升级、运行、卸载
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

V1.1.0 同时修正了热更新仓库地址，并避免网络检查失败时把异常内容误判成“发现新版本”。

> 部分第三方工具会调用其官方安装脚本或 Docker 镜像。执行前可以在插件详情里查看用途和风险等级。
