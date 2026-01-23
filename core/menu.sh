#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/server-toolbox"
source "${INSTALL_DIR}/core/common.sh"
need_root

# 🔥 热更新：每次进入菜单自动检查
auto_hot_update

docker_menu() {
  fetch_if_missing "modules/docker/docker.sh"
  bash "${INSTALL_DIR}/modules/docker/docker.sh"
}
system_menu() {
  fetch_if_missing "modules/system/system.sh"
  bash "${INSTALL_DIR}/modules/system/system.sh"
}
plugins_menu() {
  fetch_if_missing "modules/plugins/plugins.sh"
  bash "${INSTALL_DIR}/modules/plugins/plugins.sh"
}
download_menu() {
  fetch_if_missing "modules/download/download.sh"
  bash "${INSTALL_DIR}/modules/download/download.sh"
}
ssh_menu() {
  fetch_if_missing "modules/ssh/ssh.sh"
  bash "${INSTALL_DIR}/modules/ssh/ssh.sh"
}

while true; do
  clear
  echo "========================================="
  echo "   Server Toolbox  (Docker + System + SSH)"
  echo "========================================="
  echo "1) Docker 容器管理（20个常用容器）"
  echo "2) 系统工具（BBR/Swap/UFW/日志）"
  echo "3) 常用插件（配置化安装）"
  echo "4) 下载工具（aria2/rclone/yt-dlp等）"
  echo "5) SSH 工具（改密/改端口/允许root/重启）"
  echo "9) 手动更新（从 GitHub 拉最新）"
  echo "0) 退出"
  echo
  read -r -p "请输入选项 [0-5/9]: " c

  case "$c" in
    1) docker_menu ;;
    2) system_menu ;;
    3) plugins_menu ;;
    4) download_menu ;;
    5) ssh_menu ;;
    9) force_update_all; read -r -p "回车继续..." _ ;;
    0) echo "Bye 👋"; exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
