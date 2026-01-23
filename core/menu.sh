#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/server-toolbox"
source "${INSTALL_DIR}/core/common.sh"
need_root

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

while true; do
  clear
  echo "=================================="
  echo "   Server Toolbox (Docker & System)"
  echo "=================================="
  echo "1) 容器管理 Docker"
  echo "2) 系统工具 System"
  echo "3) 常用插件 Plugins"
  echo "9) 更新工具箱（从 GitHub 拉最新）"
  echo "0) 退出"
  echo
  read -r -p "请输入选项 [0/1/2/3/9]: " c

  case "$c" in
    1) docker_menu ;;
    2) system_menu ;;
    3) plugins_menu ;;
    9) force_update; read -r -p "回车继续..." _ ;;
    0) echo "Bye 👋"; exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
