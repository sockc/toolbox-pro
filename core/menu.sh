#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/server-toolbox"
source "${INSTALL_DIR}/core/common.sh"
need_root

# 🔥 热更新
auto_hot_update

run_mod() {
  local rel="$1"
  fetch_if_missing "config/containers.json"
  fetch_if_missing "config/plugins.json"
  fetch_if_missing "$rel"
  bash "${INSTALL_DIR}/${rel}"
}

while true; do
  clear
  echo "=============================================="
  echo "   Server Toolbox PRO  (Docker + System + SSH)"
  echo "=============================================="
  echo "1) Docker 容器中心（50个容器 + Compose + 日志/进入/更新）"
  echo "2) 系统工具（BBR/Swap/日志）"
  echo "3) 常用插件（配置化安装）"
  echo "4) 下载工具（aria2/rclone/yt-dlp等）"
  echo "5) SSH 工具（改密/改端口/root登录/安全模式）"
  echo "6) 防火墙（开关/放行/关闭/查看）"
  echo "7) 反代工具（Caddy/NPM）"
  echo "8) 系统急救菜单（DNS/网络/磁盘/Docker/日志）"
  echo "9) 手动更新（从 GitHub 拉最新）"
  echo "0) 退出"
  echo
  read -r -p "请输入选项 [0-6/9]: " c

  case "$c" in
    1) run_mod "modules/docker/docker.sh" ;;
    2) run_mod "modules/system/system.sh" ;;
    3) run_mod "modules/plugins/plugins.sh" ;;
    4) run_mod "modules/download/download.sh" ;;
    5) run_mod "modules/ssh/ssh.sh" ;;
    6) run_mod "modules/firewall/firewall.sh" ;;
    7) run_mod "modules/proxy/proxy.sh" ;;
    8) run_mod "modules/rescue/rescue.sh" ;;
    9) force_update_all; read -r -p "回车继续..." _ ;;
    0) echo "Bye 👋"; exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
