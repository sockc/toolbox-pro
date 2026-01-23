#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/server-toolbox"
REPO_RAW="https://raw.githubusercontent.com/vinchi008/toolbox-pro/main"

c() {
  case "$1" in
    g) echo -e "\033[32m$2\033[0m" ;;
    y) echo -e "\033[33m$2\033[0m" ;;
    r) echo -e "\033[31m$2\033[0m" ;;
    b) echo -e "\033[36m$2\033[0m" ;;
    *) echo "$2" ;;
  esac
}

ok(){ c g "[OK] $*"; }
warn(){ c y "[!] $*"; }
err(){ c r "[X] $*"; }
info(){ c b "[*] $*"; }

need_root() {
  [[ "${EUID}" -eq 0 ]] || { err "请用 root 执行：sudo -i"; exit 1; }
}

fetch() {
  # $1 = rel_path, $2 = dst(optional)
  local rel="$1"
  local dst="${2:-${INSTALL_DIR}/${rel}}"
  local url="${REPO_RAW}/${rel}"
  mkdir -p "$(dirname "$dst")"
  curl -fsSL "$url" -o "$dst"
}

fetch_if_missing() {
  local rel="$1"
  local dst="${INSTALL_DIR}/${rel}"
  if [[ ! -f "$dst" ]]; then
    info "首次拉取：${rel}"
    fetch "$rel" "$dst"
    chmod +x "$dst" 2>/dev/null || true
    ok "已就绪：${rel}"
  fi
}

force_update_all() {
  info "从 GitHub 更新核心/模块/配置..."

  fetch "core/menu.sh" "${INSTALL_DIR}/core/menu.sh"
  fetch "core/common.sh" "${INSTALL_DIR}/core/common.sh"
  fetch "core/version.txt" "${INSTALL_DIR}/core/version.txt"

  # 模块
  for m in \
    "modules/docker/docker.sh" \
    "modules/system/system.sh" \
    "modules/plugins/plugins.sh" \
    "modules/download/download.sh" \
    "modules/ssh/ssh.sh"
  do
    fetch "$m" "${INSTALL_DIR}/${m}" || true
    chmod +x "${INSTALL_DIR}/${m}" 2>/dev/null || true
  done

  # 配置
  for c in "config/plugins.json" "config/containers.json"; do
    fetch "$c" "${INSTALL_DIR}/${c}" || true
  done

  ok "更新完成 ✅"
}

auto_hot_update() {
  # 可用环境变量关闭热更新：NO_TOOLBOX_UPDATE=1
  [[ "${NO_TOOLBOX_UPDATE:-0}" == "1" ]] && return 0

  local local_ver="0"
  local remote_ver="0"

  if [[ -f "${INSTALL_DIR}/core/version.txt" ]]; then
    local_ver="$(cat "${INSTALL_DIR}/core/version.txt" 2>/dev/null || echo 0)"
  fi

  remote_ver="$(curl -fsSL "${REPO_RAW}/core/version.txt" 2>/dev/null || echo 0)"

  if [[ "$remote_ver" != "$local_ver" ]]; then
    info "检测到新版本：${local_ver} -> ${remote_ver}，自动热更新..."
    force_update_all
  fi
}
