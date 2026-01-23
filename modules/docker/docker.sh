#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

CFG="/opt/server-toolbox/config/containers.json"
[[ -f "$CFG" ]] || { err "缺少配置：$CFG"; exit 1; }

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    return
  fi
  info "安装 Docker（官方脚本）..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker >/dev/null 2>&1 || true
  ok "Docker 安装完成 ✅"
}

ensure_volume() {
  local v="$1"
  [[ "$v" == *":"* ]] && return 0
  docker volume create "$v" >/dev/null 2>&1 || true
}

compose_up() {
  local id="$1"
  local yml="/opt/apps/${id}/docker-compose.yml"
  [[ -f "$yml" ]] || { warn "缺少 compose 文件：$yml"; return; }
  install_docker
  (cd "/opt/apps/${id}" && docker compose up -d) || true
  ok "Compose 已启动 ✅ $id"
}

compose_down() {
  local id="$1"
  local yml="/opt/apps/${id}/docker-compose.yml"
  [[ -f "$yml" ]] || { warn "缺少 compose 文件：$yml"; return; }
  (cd "/opt/apps/${id}" && docker compose down) || true
  ok "Compose 已停止 ✅ $id"
}

deploy_run_by_idx() {
  local idx="$1"
  local id name image extra
  id="$(jq -r ".[$idx].id" "$CFG")"
  name="$(jq -r ".[$idx].name" "$CFG")"
  image="$(jq -r ".[$idx].image" "$CFG")"
  extra="$(jq -r ".[$idx].extra // \"\"" "$CFG")"
  [[ -n "$id" && "$id" != "null" ]] || { warn "无效容器"; return; }

  install_docker
  mkdir -p "/opt/apps/${id}" >/dev/null 2>&1 || true

  info "部署：$name  [$id]"
  docker rm -f "$id" >/dev/null 2>&1 || true

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
  docker run -d --name "$id" $ports $volumes $envs $extra "$image" >/dev/null 2>&1 || {
    warn "启动失败：$id（可能端口冲突/镜像拉取失败）"
    return
  }

  ok "已启动 ✅ $name"
  docker ps --filter "name=^/${id}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

deploy_compose_by_idx() {
  local idx="$1"
  local id name
  id="$(jq -r ".[$idx].id" "$CFG")"
  name="$(jq -r ".[$idx].name" "$CFG")"
  local compose="$(jq -r ".[$idx].compose // empty" "$CFG")"
  [[ -n "$compose" ]] || { warn "该容器未提供 compose 模板"; return; }

  mkdir -p "/opt/apps/${id}" >/dev/null 2>&1 || true
  printf "%s\n" "$compose" >"/opt/apps/${id}/docker-compose.yml"
  ok "已写入 compose 文件：/opt/apps/${id}/docker-compose.yml"
  compose_up "$id"
  ok "Compose 部署完成 ✅ $name"
}

logs_by_idx() {
  local idx="$1"
  local id; id="$(jq -r ".[$idx].id" "$CFG")"
  docker logs --tail 200 -f "$id" || true
}

exec_by_idx() {
  local idx="$1"
  local id; id="$(jq -r ".[$idx].id" "$CFG")"
  docker exec -it "$id" sh 2>/dev/null || docker exec -it "$id" bash 2>/dev/null || {
    warn "进入失败（容器可能没 sh/bash）"
  }
}

restart_by_idx() {
  local idx="$1"
  local id; id="$(jq -r ".[$idx].id" "$CFG")"
  docker restart "$id" >/dev/null 2>&1 || true
  ok "已重启 ✅ $id"
}

delete_by_idx() {
  local idx="$1"
  local id name
  id="$(jq -r ".[$idx].id" "$CFG")"
  name="$(jq -r ".[$idx].name" "$CFG")"
  docker rm -f "$id" >/dev/null 2>&1 || true
  ok "已删除 ✅ $name"
}

update_all_images() {
  install_docker
  info "更新所有容器镜像（pull）..."
  docker ps --format '{{.Image}}' | sort -u | while read -r img; do
    [[ -n "$img" ]] && docker pull "$img" >/dev/null 2>&1 || true
  done
  ok "镜像更新完成 ✅（需要的容器可手动重启）"
}

while true; do
  clear
  echo "=========== Docker 容器中心 PRO ==========="
  echo "命令说明："
  echo "  数字    = 一键部署/重装（run）"
  echo "  c数字   = Compose部署（如 c13）"
  echo "  l数字   = 查看日志（如 l13）"
  echo "  e数字   = 进入容器（如 e13）"
  echo "  r数字   = 重启容器"
  echo "  d数字   = 删除容器"
  echo "  u       = 更新所有镜像"
  echo "  s       = 查看当前运行状态"
  echo "  0       = 返回"
  echo
  jq -r 'to_entries[] | "\(.key+1)) \(.value.name) [\(.value.id)]"' "$CFG"
  echo
  read -r -p "请输入: " c

  [[ "$c" == "0" ]] && exit 0

  case "$c" in
    s)
      install_docker
      docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
      read -r -p "回车继续..." _
      ;;
    u)
      update_all_images
      read -r -p "回车继续..." _
      ;;
    *)
      if [[ "$c" =~ ^[0-9]+$ ]]; then
        deploy_run_by_idx $((c-1))
        read -r -p "回车继续..." _
      elif [[ "$c" =~ ^c[0-9]+$ ]]; then
        n="${c#c}"; deploy_compose_by_idx $((n-1))
        read -r -p "回车继续..." _
      elif [[ "$c" =~ ^l[0-9]+$ ]]; then
        n="${c#l}"; logs_by_idx $((n-1))
      elif [[ "$c" =~ ^e[0-9]+$ ]]; then
        n="${c#e}"; exec_by_idx $((n-1))
      elif [[ "$c" =~ ^r[0-9]+$ ]]; then
        n="${c#r}"; restart_by_idx $((n-1))
        read -r -p "回车继续..." _
      elif [[ "$c" =~ ^d[0-9]+$ ]]; then
        n="${c#d}"; delete_by_idx $((n-1))
        read -r -p "回车继续..." _
      else
        warn "无效输入"; sleep 1
      fi
      ;;
  esac
done
