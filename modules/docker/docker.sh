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

port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntup | grep -qE "[:.]${p}\b" && return 0 || return 1
  fi
  return 1
}

check_port_conflicts() {
  local idx="$1"
  local conflicts=()
  while read -r pm; do
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

write_env_file() {
  local id="$1"
  local idx="$2"
  local envfile="/opt/apps/${id}/.env"
  mkdir -p "/opt/apps/${id}" >/dev/null 2>&1 || true
  : >"$envfile"

  jq -r ".[$idx].env[]? // empty" "$CFG" >>"$envfile" || true

  local scount
  scount="$(jq -r ".[$idx].secrets | length 2>/dev/null" "$CFG")"
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
  local show
  show="$(jq -r ".[$idx].show_after_install // false" "$CFG")"
  [[ "$show" != "true" ]] && return 0

  local notes envfile
  notes="$(jq -r ".[$idx].notes // \"\"" "$CFG")"
  envfile="/opt/apps/${id}/.env"

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
  write_env_file "$id" "$idx"

  info "部署：$name"
  docker rm -f "$id" >/dev/null 2>&1 || true

  local ports volumes
  ports="$(jq -r ".[$idx].ports[]? // empty" "$CFG" | awk '{print "-p "$0}' | tr '\n' ' ')"
  volumes="$(jq -r ".[$idx].volumes[]? // empty" "$CFG" | awk '{print "-v "$0}' | tr '\n' ' ')"

  # shellcheck disable=SC2086
  docker run -d --name "$id" \
    --env-file "/opt/apps/${id}/.env" \
    $ports $volumes $extra "$image" >/dev/null 2>&1 || {
      warn "启动失败：$id（镜像/参数/端口冲突）"
      return
    }

  ok "已启动 ✅ $name"
  docker ps --filter "name=^/${id}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  show_after_install "$id" "$idx"
}

deploy_compose_by_idx() {
  local idx="$1"
  local id name compose
  id="$(jq -r ".[$idx].id" "$CFG")"
  name="$(jq -r ".[$idx].name" "$CFG")"
  compose="$(jq -r ".[$idx].compose // empty" "$CFG")"
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

show_list_with_status() {
  local total cols colw
  total="$(jq 'length' "$CFG" 2>/dev/null || echo 0)"
  cols="$(tput cols 2>/dev/null || echo 120)"
  colw=$((cols/2))
  [[ $colw -lt 55 ]] && colw=55

  local lines=()
  for i in $(seq 0 $((total-1))); do
    local id name state icon ports
    id="$(jq -r ".[$i].id" "$CFG")"
    name="$(jq -r ".[$i].name" "$CFG")"

    icon="⚪"; state="未安装"; ports="-"
    if command -v docker >/dev/null 2>&1; then
      if docker inspect "$id" >/dev/null 2>&1; then
        local running health
        running="$(docker inspect -f '{{.State.Running}}' "$id" 2>/dev/null || echo false)"
        health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$id" 2>/dev/null || true)"

        if [[ "$running" == "true" ]]; then
          icon="🟢"; state="运行中"
        else
          icon="⚪"; state="已停止"
        fi

        if [[ -n "${health:-}" && "$health" != "<no value>" ]]; then
          if [[ "$health" == "healthy" ]]; then
            icon="🟢"; state="运行健康"
          elif [[ "$health" == "unhealthy" ]]; then
            icon="🔴"; state="运行异常"
          else
            icon="🟡"; state="健康检查:${health}"
          fi
        fi

        ports="$(docker ps --filter "name=^/${id}$" --format '{{.Ports}}' 2>/dev/null | head -n1 || true)"
        [[ -z "$ports" ]] && ports="$(docker inspect -f '{{range $p,$conf := .NetworkSettings.Ports}}{{$p}} {{end}}' "$id" 2>/dev/null | xargs || true)"
        [[ -z "$ports" ]] && ports="-"
      fi
    fi

    lines+=("$(printf "%2d) %s %s (%s) %s" "$((i+1))" "$icon" "$name" "$state" "$ports")")
  done

  local k=0
  while [[ $k -lt ${#lines[@]} ]]; do
    local left="${lines[$k]}"
    local right=""
    if [[ $((k+1)) -lt ${#lines[@]} ]]; then
      right="${lines[$((k+1))]}"
    fi
    printf "%-${colw}s%s\n" "$left" "$right"
    k=$((k+2))
  done
}

get_public_ip_best() {
  local ip=""
  ip="$(curl -fsSL --max-time 2 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$ip" ]] && { echo "$ip"; return; }
  ip="$(curl -fsSL --max-time 2 https://ip.sb 2>/dev/null || true)"
  [[ -n "$ip" ]] && { echo "$ip"; return; }
  hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_SERVER_IP"
}

show_web_access_by_idx() {
  local idx="$1"
  local id name notes
  id="$(jq -r ".[$idx].id" "$CFG")"
  name="$(jq -r ".[$idx].name" "$CFG")"
  notes="$(jq -r ".[$idx].notes // \"\"" "$CFG")"
  [[ -n "$id" && "$id" != "null" ]] || { warn "无效容器"; return; }

  local ip
  ip="$(get_public_ip_best)"

  echo
  echo "========== 一键访问地址 =========="
  echo "容器: $name"
  [[ -n "$notes" && "$notes" != "null" ]] && echo "提示: $notes"
  echo "服务器: $ip"
  echo

  local ports=()
  while read -r p; do
    [[ -n "$p" ]] && ports+=("$p")
  done < <(jq -r ".[$idx].ports[]? // empty" "$CFG")

  if [[ "${#ports[@]}" -eq 0 ]]; then
    warn "该容器配置中没有 ports，无法推断 Web 地址"
    echo "================================="
    echo
    return
  fi

  local web_candidates=("443" "9443" "8443" "81" "80" "8080" "8081" "8082" "3000" "3001" "9000" "9090" "2283" "5244" "16601" "9876")
  local host_ports=()

  for pm in "${ports[@]}"; do
    local hp="${pm%%:*}"
    hp="${hp%%/*}"
    [[ "$hp" =~ ^[0-9]+$ ]] && host_ports+=("$hp")
  done

  host_ports=($(printf "%s\n" "${host_ports[@]}" | awk '!a[$0]++'))

  local chosen=""
  for c in "${web_candidates[@]}"; do
    for hp in "${host_ports[@]}"; do
      if [[ "$hp" == "$c" ]]; then
        chosen="$hp"
        break 2
      fi
    done
  done

  echo "配置端口映射："
  for pm in "${ports[@]}"; do
    echo "  - $pm"
  done
  echo

  if [[ -n "$chosen" ]]; then
    local scheme="http"
    [[ "$chosen" == "443" || "$chosen" == "9443" || "$chosen" == "8443" ]] && scheme="https"
    echo "⭐ 推荐访问：${scheme}://${ip}:${chosen}"
    echo
  fi

  echo "全部可能访问地址："
  for hp in "${host_ports[@]}"; do
    local scheme="http"
    [[ "$hp" == "443" || "$hp" == "9443" || "$hp" == "8443" ]] && scheme="https"
    echo "  - ${scheme}://${ip}:${hp}"
  done

  echo "================================="
  echo
}

while true; do
  clear
  echo "=========== Docker 容器中心 PRO ==========="
  echo "输入说明："
  echo "  数字   = 运行部署/重装"
  echo "  c数字  = Compose部署（如 c40）"
  echo "  l数字  = 查看日志"
  echo "  e数字  = 进入容器"
  echo "  r数字  = 重启容器"
  echo "  d数字  = 删除容器"
  echo "  w数字  = 一键访问地址（如 w3）"
  echo "  u      = 更新所有镜像"
  echo "  s      = 查看运行状态"
  echo "  0      = 返回"
  echo

  show_list_with_status
  echo
  read -r -p "请输入: " c

  case "$c" in
    0) exit 0 ;;
    s) install_docker; docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"; read -r -p "回车继续..." _ ;;
    u) update_all_images; read -r -p "回车继续..." _ ;;
    [0-9]*)
      deploy_run_by_idx $((c-1)); read -r -p "回车继续..." _ ;;
    c[0-9]*)
      n="${c#c}"; deploy_compose_by_idx $((n-1)); read -r -p "回车继续..." _ ;;
    l[0-9]*)
      n="${c#l}"; logs_by_idx $((n-1)) ;;
    e[0-9]*)
      n="${c#e}"; exec_by_idx $((n-1)) ;;
    r[0-9]*)
      n="${c#r}"; restart_by_idx $((n-1)); read -r -p "回车继续..." _ ;;
    d[0-9]*)
      n="${c#d}"; delete_by_idx $((n-1)); read -r -p "回车继续..." _ ;;
    w[0-9]*)
      n="${c#w}"; show_web_access_by_idx $((n-1)); read -r -p "回车继续..." _ ;;
    *)
      warn "无效输入"; sleep 1 ;;
  esac
done
