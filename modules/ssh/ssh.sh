#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

SSHD="/etc/ssh/sshd_config"

restart_ssh() {
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  ok "SSH 已重启 ✅"
}

change_root_password() {
  info "修改 root 密码..."
  passwd root
  ok "root 密码已修改 ✅"
}

set_sshd_kv() {
  local key="$1"
  local val="$2"
  if grep -qE "^\s*${key}\s+" "$SSHD"; then
    sed -i -E "s|^\s*${key}\s+.*|${key} ${val}|g" "$SSHD"
  else
    echo "${key} ${val}" >>"$SSHD"
  fi
}

change_ssh_port() {
  read -r -p "输入新 SSH 端口（建议 2222/2022）: " p
  [[ "$p" =~ ^[0-9]+$ ]] || { warn "端口必须是数字"; return; }

  set_sshd_kv "Port" "$p"

  # 放行防火墙
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${p}/tcp" >/dev/null 2>&1 || true
    ok "UFW 已放行端口 ${p}/tcp ✅"
  fi

  ok "SSH 端口已修改为：$p ✅"
  restart_ssh
}

allow_root_login() {
  set_sshd_kv "PermitRootLogin" "yes"
  set_sshd_kv "PasswordAuthentication" "yes"
  ok "已允许 root 密码登录 ✅"
  restart_ssh
}

while true; do
  clear
  echo "=========== SSH 工具 ==========="
  echo "1) 修改 root 密码"
  echo "2) 修改 SSH 端口"
  echo "3) 一键允许 root 密码登录"
  echo "4) 重启 SSH 服务"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  case "$c" in
    1) change_root_password; read -r -p "回车继续..." _ ;;
    2) change_ssh_port; read -r -p "回车继续..." _ ;;
    3) allow_root_login; read -r -p "回车继续..." _ ;;
    4) restart_ssh; read -r -p "回车继续..." _ ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
