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

fetch_if_missing() {
  # $1=relative_path like modules/docker/docker.sh
  local rel="$1"
  local dst="${INSTALL_DIR}/${rel}"
  local url="${REPO_RAW}/${rel}"
  mkdir -p "$(dirname "$dst")"

  if [[ ! -f "$dst" ]]; then
    info "首次拉取模块：${rel}"
    curl -fsSL "$url" -o "$dst"
    chmod +x "$dst" || true
    ok "模块就绪：${rel}"
  fi
}

force_update() {
  info "更新核心与模块..."
  curl -fsSL "${REPO_RAW}/core/menu.sh" -o "${INSTALL_DIR}/core/menu.sh"
  curl -fsSL "${REPO_RAW}/core/common.sh" -o "${INSTALL_DIR}/core/common.sh"

  # 常用模块
  for m in modules/docker/docker.sh modules/system/system.sh modules/plugins/plugins.sh; do
    curl -fsSL "${REPO_RAW}/${m}" -o "${INSTALL_DIR}/${m}" || true
    chmod +x "${INSTALL_DIR}/${m}" || true
  done
  ok "更新完成 ✅"
}
