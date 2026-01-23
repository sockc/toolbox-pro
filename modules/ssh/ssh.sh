#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

SSHD="/etc/ssh/sshd_config"

restart_ssh() {
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  ok "SSH 已重启 ✅"
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

change_root_password() {
  info "修改 root 密码..."
  passwd root
  ok "root 密码已修改 ✅"
}

change_ssh_port() {
  read -r -p "输入新 SSH 端口（建议 2222/2022）: " p
  [[ "$p" =~ ^[0-9]+$ ]] || { warn "端口必须是数字"; return; }
  set_sshd_kv "Port" "$p"
  ok "SSH 端口已修改为：$p ✅"
  restart_ssh
}

allow_root_login() {
  set_sshd_kv "PermitRootLogin" "yes"
  set_sshd_kv "PasswordAuthentication" "yes"
  ok "已允许 root 密码登录 ✅"
  restart_ssh
}

security_mode_on() {
  # ⚠️ 禁用密码登录（更安全）
  set_sshd_kv "PasswordAuthentication" "no"
  set_sshd_kv "PermitRootLogin" "prohibit-password"
  set_sshd_kv "PubkeyAuthentication" "yes"
  ok "安全模式已开启 ✅（禁用密码登录，仅允许密钥）"
  restart_ssh
}

security_mode_off() {
  set_sshd_kv "PasswordAuthentication" "yes"
  set_sshd_kv "PermitRootLogin" "yes"
  ok "已恢复密码登录 ✅"
  restart_ssh
}

while true; do
  clear
  echo "=========== SSH 工具 ==========="
  echo "1) 修改 root 密码"
  echo "2) 修改 SSH 端口"
  echo "3) 一键允许 root 密码登录"
  echo "4) 安全模式 ON（禁用密码，仅密钥）✅推荐"
  echo "5) 安全模式 OFF（恢复密码登录）"
  echo "6) 重启 SSH 服务"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  case "$c" in
    1) change_root_password; read -r -p "回车继续..." _ ;;
    2) change_ssh_port; read -r -p "回车继续..." _ ;;
    3) allow_root_login; read -r -p "回车继续..." _ ;;
    4) security_mode_on; read -r -p "回车继续..." _ ;;
    5) security_mode_off; read -r -p "回车继续..." _ ;;
    6) restart_ssh; read -r -p "回车继续..." _ ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
