# Server Toolbox PRO（Docker + 系统工具 + 插件库 + 急救菜单）

一套可在 Linux VPS/服务器上使用的 **一键安装 + 菜单化管理脚本集合**，主打：
- ✅ Docker 常用容器一键部署（53 套件，支持 Run/Compose）
- ✅ 热更新（版本号驱动，自动拉取最新模块/配置）
- ✅ 插件库（配置化，通用版）
- ✅ 系统工具（BBR/Swap/日志等）
- ✅ SSH 工具（改密/改端口/允许 root/重启 ssh）
- ✅ 防火墙（UFW 安全模式：自动检测 SSH 端口，防误封）
- ✅ 系统急救（DNS/网络/磁盘/Docker/日志）
- ✅ Fail2ban 防护中心（SSH 暴力破解封禁管理）

---

## 目录结构
Server Toolbox PRO  (Docker + System + SSH)
1) Docker 容器中心（53个容器 + Compose + 日志/进入/更新）
2) 系统工具（BBR/Swap/日志）
3) 常用插件（配置化安装）
4) 下载工具（aria2/rclone/yt-dlp等）
5) SSH 工具（改密/改端口/root登录/安全模式）
6) 防火墙（UFW 安全模式）
7) 反代工具（Caddy/NPM/Lucky等）
8) 系统急救菜单（DNS/网络/磁盘/Docker/日志）
9) 手动更新（从 GitHub 拉最新）
10) Fail2ban 防护中心（SSH暴力破解封禁）
0) 退出

---

## 适用系统

- ✅ Debian / Ubuntu（推荐）
- ✅ 其他常见发行版也尽量兼容（脚本内会尝试 apt/yum/dnf/apk）
- ✅ x86_64 / ARM64 均可（Docker 镜像本身是否支持 ARM 取决于镜像）

> 注意：某些容器镜像可能不提供 ARM 架构，请以容器官方说明为准。

---

## 一键安装（推荐）

> 安装完成会创建快捷命令：`toolbox`

```bash
curl -fsSL https://raw.githubusercontent.com/vinchi008/toolbox-pro/main/install.sh | bash




# Server Toolbox

快捷进入菜单
toolbox

一键安装：

```bash
curl -fsSL https://raw.githubusercontent.com/vinchi008/toolbox-pro/main/install.sh | bash
```
快捷进入菜单
```bash
toolbox
