#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

CFG="/opt/server-toolbox/config/containers.json"
[[ -f "$CFG" ]] || { err "缺少配置：$CFG"; exit 1; }

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

ensure_volume() {
  local v="$1"
  if [[ "$v" == *":"* ]]; then
    # bind mount or sock
    return 0
  fi
  # named volume
  docker volume create "$v" >/dev/null 2>&1 || true
}

run_container_by_idx() {
  local idx="$1"
  local id image name extra
  id="$(jq -r ".[$idx].id" "$CFG")"
  name="$(jq -r ".[$idx].name" "$CFG")"
  image="$(jq -r ".[$idx].image" "$CFG")"
  extra="$(jq -r ".[$idx].extra // \"\"" "$CFG")"

  [[ -n "$id" && "$id" != "null" ]] || { warn "无效容器"; return; }

  install_docker
  mkdir -p "/opt/apps/${id}" 2>/dev/null || true

  info "准备部署：$name ($id)"
  info "镜像：$image"

  # 删除旧容器
  docker rm -f "$id" >/dev/null 2>&1 || true

  # 组装参数
  local ports volumes envs
  ports="$(jq -r ".[$idx].ports[]? // empty" "$CFG" | awk '{print "-p "$0}' | tr '\n' ' ')"
  volumes="$(jq -r ".[$idx].volumes[]? // empty" "$CFG" | while read -r v; do
      if [[ "$v" == *":"* ]]; then
        echo "-v $v"
      else
        ensure_volume "$v"
        echo "-v $v"
      fi
    done | tr '\n' ' ')"
  envs="$(jq -r ".[$idx].env[]? // empty" "$CFG" | awk '{print "-e "$0}' | tr '\n' ' ')"

  # shellcheck disable=SC2086
  docker run -d --name "$id" $ports $volumes $envs $extra "$image" >/dev/null

  ok "已启动 ✅ $name"
  docker ps --filter "name=^/${id}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

uninstall_container_by_idx() {
  local idx="$1"
  local id name
  id="$(jq -r ".[$idx].id" "$CFG")"
  name="$(jq -r ".[$idx].name" "$CFG")"
  docker rm -f "$id" >/dev/null 2>&1 || true
  ok "已移除容器 ✅ $name"
}

show_status() {
  install_docker
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

while true; do
  clear
  echo "=========== Docker 容器管理（配置化） ==========="
  echo "a) 查看容器状态"
  jq -r 'to_entries[] | "\(.key+1)) \(.value.name) [\(.value.id)]"' "$CFG"
  echo "u) 卸载某个容器"
  echo "0) 返回"
  echo
  read -r -p "选择（数字部署/重装 | a状态 | u卸载 | 0返回）: " c

  case "$c" in
    0) exit 0 ;;
    a) show_status; read -r -p "回车继续..." _ ;;
    u)
      read -r -p "输入要卸载的序号: " n
      [[ "$n" =~ ^[0-9]+$ ]] || { warn "请输入数字"; sleep 1; continue; }
      uninstall_container_by_idx $((n-1))
      read -r -p "回车继续..." _
      ;;
    *)
      if [[ "$c" =~ ^[0-9]+$ ]]; then
        run_container_by_idx $((c-1))
        read -r -p "回车继续..." _
      else
        warn "无效选项"; sleep 1
      fi
      ;;
  esac
done
