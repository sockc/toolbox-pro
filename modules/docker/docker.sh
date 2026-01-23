#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    ok "Docker 已安装：$(docker --version)"
    return
  fi

  info "安装 Docker（官方脚本）..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  ok "Docker 安装完成 ✅"
}

install_compose_plugin() {
  if docker compose version >/dev/null 2>&1; then
    ok "Docker Compose 已可用：$(docker compose version)"
    return
  fi
  warn "你的 Docker 可能较老，建议升级 Docker 后再试"
}

portainer_install() {
  install_docker
  docker volume create portainer_data >/dev/null 2>&1 || true
  docker rm -f portainer >/dev/null 2>&1 || true
  docker run -d \
    --name portainer \
    --restart=always \
    -p 9000:9000 \
    -p 9443:9443 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
  ok "Portainer 已启动 ✅ 访问：https://你的IP:9443"
}

watchtower_install() {
  install_docker
  docker rm -f watchtower >/dev/null 2>&1 || true
  docker run -d \
    --name watchtower \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower:latest \
    --cleanup --schedule "0 0 4 * * *"
  ok "Watchtower 已启动 ✅ 每天 04:00 自动更新容器"
}

docker_cleanup() {
  info "清理无用镜像/容器/网络..."
  docker system prune -af --volumes
  ok "清理完成 ✅"
}

while true; do
  clear
  echo "=========== Docker 管理 ==========="
  echo "1) 安装 Docker"
  echo "2) 检查 Compose"
  echo "3) 安装 Portainer"
  echo "4) 安装 Watchtower（自动更新容器）"
  echo "5) Docker 清理（危险）"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  case "$c" in
    1) install_docker; read -r -p "回车继续..." _ ;;
    2) install_compose_plugin; read -r -p "回车继续..." _ ;;
    3) portainer_install; read -r -p "回车继续..." _ ;;
    4) watchtower_install; read -r -p "回车继续..." _ ;;
    5) docker_cleanup; read -r -p "回车继续..." _ ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
