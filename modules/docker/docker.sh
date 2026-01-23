#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

CFG="/opt/server-toolbox/config/containers.json"
[[ -f "$CFG" ]] || { err "缺少配置：$CFG"; exit 1; }

install_docker() {
  if command -v docker >/dev/null 2>&1; then return; fi
  info "安装 Docker（官方脚本）..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker >/dev/null 2>&1 || true
  ok "Docker 安装完成 ✅"
}

# 检测端口是否被占用（TCP/UDP都看）
port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntup | grep -qE "[:.]${p}\b" && return 0 || return 1
  fi
  return 1
}

# 从 ports 配置里提取主机端口，检查冲突
check_port_conflicts() {
  local idx="$1"
  local conflicts=()
  while read -r pm; do
    # 格式：host:container 或 host:container/proto
    local host="${pm%%:*}"
    host="${host%%/*}"
    [[ "$host" =~ ^[0-9]+$ ]] || continue
    if port_in_use "$host"; then
      conflicts+=("$host")
    fi
  done < <(jq -r ".[$idx].ports[]? // empty" "$CFG")

  if [[ "${#conflicts[@]}" -gt 0 ]]; then
    warn "端口冲突：${conflicts[*]}"
    read -r -p "仍然继续部署？(y/N): " yn
    [[ "${yn,,}" == "y" ]] || return 1
  fi
  return 0
}

# 写入 env 到 /opt/apps/<id>/.env
write_env_file() {
  local id="$1"
  local idx="$2"
  local envfile="/opt/apps/${id}/.env"
  mkdir -p "/opt/apps/${id}" >/dev/null 2>&1 || true
  : >"$envfile"

  # 常规 env
  jq -r ".[$idx].env[]? // empty" "$CFG" >>"$envfile" || true

  # secrets（交互输入）
  local scount; scount="$(jq -r ".[$idx].secrets | length 2>/dev/null" "$CFG")"
  if [[ "$scount" != "null" && "$scount" -gt 0 ]]; then
    for i in $(seq 0 $((scount-1))); do
      local key prompt def val
      key="$(jq -r ".[$idx].secrets[$i].key" "$CFG")"
      prompt="$(jq -r ".[$idx].secrets[$i].prompt" "$CFG")"
      def="$(jq -r ".[$idx].secrets[$i].default // \"\"" "$CFG")"

      echo
      read -r -p "${prompt} [默认: ${def}]: " val
      val="${val:-$def}"
      echo "${key}=${val}" >>"$envfile"
    done
  fi

  ok "已生成环境文件：$envfile"
}

show_after_install() {
  local id="$1"
  local idx="$2"
  local show; show="$(jq -r ".[$idx].show_after_install // false" "$CFG")"
  [[ "$show" != "true" ]] && return 0

  local notes; notes="$(jq -r ".[$idx].notes // \"\"" "$CFG")"
  local envfile="/opt/apps/${id}/.env"

  echo
  echo "========== 安装信息 =========="
  echo "容器: $id"
  [[ -n "$notes" && "$notes" != "null" ]] && echo "提示: $notes"
  if [[ -f "$envfile" ]]; then
    echo "凭据(.env):"
    sed 's/=.*/=******/' "$envfile" | sed 's/^/  - /'
    echo "（真实密码已写入：$envfile）"
  fi
  echo "=============================="
  echo
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

  check_port_conflicts "$idx" || return

  # 生成 env
  write_env_file "$id" "$idx"

  info "部署：$name [$id]"
  docker rm -f "$id" >/dev/null 2>&1 || true

  local ports volumes
  ports="$(jq -r ".[$idx].ports[]? // empty" "$CFG" | awk '{print "-p "$0}' | tr '\n' ' ')"
  volumes="$(jq -r ".[$idx].volumes[]? // empty" "$CFG" | awk '{print "-v "$0}' | tr '\n' ' ')"

  # shellcheck disable=SC2086
  docker run -d --name "$id" \
    --env-file "/opt/apps/${id}/.env" \
    $ports $volumes $extra "$image" >/dev/null 2>&1 || {
      warn "启动失败：$id（可能镜像拉取失败/参数不兼容/端口冲突）"
      return
    }

  ok "已启动 ✅ $name"
  docker ps --filter "name=^/${id}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  show_after_install "$id" "$idx"
}

deploy_compose_by_idx() {
  local idx="$1"
  local id name
  id="$(jq -r ".[$idx].id" "$CFG")"
  name="$(jq -r ".[$idx].name" "$CFG")"
  local compose; compose="$(jq -r ".[$idx].compose // empty" "$CFG")"
  [[ -n "$compose" ]] || { warn "该容器未提供 compose 模板"; return; }

  install_docker
  mkdir -p "/opt/apps/${id}" >/dev/null 2>&1 || true

  write_env_file "$id" "$idx"
  printf "%s\n" "$compose" >"/opt/apps/${id}/docker-compose.yml"
  ok "已写入 compose：/opt/apps/${id}/docker-compose.yml"

  (cd "/opt/apps/${id}" && docker compose up -d) || { warn "Compose 启动失败"; return; }
  ok "Compose 部署完成 ✅ $name"
  show_after_install "$id" "$idx"
}

logs_by_idx() {
  local idx="$1"
  local id; id="$(jq -r ".[$idx].id" "$CFG")"
  docker logs --tail 200 -f "$id" || true
}

exec_by_idx() {
  local idx="$1"
  local id; id="$(jq -r ".[$idx].id" "$CFG")"
  docker exec -it "$id" sh 2>/dev/null || docker exec -it "$id" bash 2>/dev/null || warn "进入失败（无 sh/bash）"
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
  info "更新所有镜像（pull）..."
  docker ps --format '{{.Image}}' | sort -u | while read -r img; do
    [[ -n "$img" ]] && docker pull "$img" >/dev/null 2>&1 || true
  done
  ok "镜像更新完成 ✅（需要的容器可 r数字 重启）"
}

while true; do
  clear
  echo "=========== Docker 容器中心 PRO ==========="
  echo "输入说明："
  echo "  数字   = 运行部署/重装（run）"
  echo "  c数字  = Compose部署（如 c40）"
  echo "  l数字  = 查看日志"
  echo "  e数字  = 进入容器"
  echo "  r数字  = 重启容器"
  echo "  d数字  = 删除容器"
  echo "  u      = 更新所有镜像"
  echo "  s      = 查看运行状态"
  echo "  0      = 返回"
  echo
  jq -r 'to_entries[] | "\(.key+1)) \(.value.name) [\(.value.id)]"' "$CFG"
  echo
  read -r -p "请输入: " c

  [[ "$c" == "0" ]] && exit 0

  case "$c" in
    s) install_docker; docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"; read -r -p "回车继续..." _ ;;
    u) update_all_images; read -r -p "回车继续..." _ ;;
    *)
      if [[ "$c" =~ ^[0-9]+$ ]]; then
        deploy_run_by_idx $((c-1)); read -r -p "回车继续..." _ ;;
      elif [[ "$c" =~ ^c[0-9]+$ ]]; then
        n="${c#c}"; deploy_compose_by_idx $((n-1)); read -r -p "回车继续..." _ ;;
      elif [[ "$c" =~ ^l[0-9]+$ ]]; then
        n="${c#l}"; logs_by_idx $((n-1)) ;;
      elif [[ "$c" =~ ^e[0-9]+$ ]]; then
        n="${c#e}"; exec_by_idx $((n-1)) ;;
      elif [[ "$c" =~ ^r[0-9]+$ ]]; then
        n="${c#r}"; restart_by_idx $((n-1)); read -r -p "回车继续..." _ ;;
      elif [[ "$c" =~ ^d[0-9]+$ ]]; then
        n="${c#d}"; delete_by_idx $((n-1)); read -r -p "回车继续..." _ ;;
      else
        warn "无效输入"; sleep 1 ;;
      fi
      ;;
  esac
done
