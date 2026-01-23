#!/usr/bin/env bash
set -euo pipefail

source /opt/server-toolbox/core/common.sh
need_root

# ===== 工具函数 =====
detect_ssh_port() {
  # 优先读 sshd_config
  local p
  p="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)"
  if [[ -n "${p:-}" ]]; then
    echo "$p"
    return
  fi

  # 兜底：从配置文件读
  p="$(grep -E '^\s*Port\s+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -n1 || true)"
  [[ -n "${p:-}" ]] && { echo "$p"; return; }

  # 再兜底：猜 22
  echo "22"
}

ensure_ufw_installed() {
  if command -v ufw >/dev/null 2>&1; then return 0; fi

  info "安装 UFW..."
  if command -v apt >/dev/null 2>&1; then
    apt update -y || true
    apt install -y ufw || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ufw || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y ufw || true
  else
    err "未检测到 apt/dnf/yum，无法安装 ufw"
    return 1
  fi

  command -v ufw >/dev/null 2>&1 || { err "UFW 安装失败"; return 1; }
  ok "UFW 安装完成 ✅"
}

ufw_safe_enable() {
  ensure_ufw_installed

  local ssh_port
  ssh_port="$(detect_ssh_port)"

  info "检测到 SSH 端口：${ssh_port}"
  info "安全策略：先放行 SSH，再启用 UFW（防止断连）"

  # 默认规则：拒绝入站，允许出站
  ufw default deny incoming >/dev/null 2>&1 || true
  ufw default allow outgoing >/dev/null 2>&1 || true

  # 放行 SSH（TCP）
  ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || true

  # 如果你常用 80/443，也可以顺手放行（可删）
  # ufw allow 80/tcp >/dev/null 2>&1 || true
  # ufw allow 443/tcp >/dev/null 2>&1 || true

  # 开启
  ufw --force enable >/dev/null 2>&1 || true
  ok "UFW 已开启 ✅（SSH ${ssh_port}/tcp 已确保放行）"
}

ufw_disable() {
  ensure_ufw_installed
  ufw disable >/dev/null 2>&1 || true
  ok "UFW 已关闭 ✅"
}

ufw_allow_port() {
  ensure_ufw_installed
  read -r -p "输入要放行的端口（如 80 或 443 或 5201/udp）: " p || true
  [[ -n "${p:-}" ]] || { warn "端口不能为空"; return; }

  # 支持：80 / 443/tcp / 5201/udp
  if [[ "$p" =~ /udp$ ]]; then
    ufw allow "$p" >/dev/null 2>&1 || true
  elif [[ "$p" =~ /tcp$ ]]; then
    ufw allow "$p" >/dev/null 2>&1 || true
  else
    # 默认 TCP+UDP 都放行比较危险，这里默认放 TCP，更安全
    ufw allow "${p}/tcp" >/dev/null 2>&1 || true
  fi

  ok "已放行 ✅ $p"
}

ufw_deny_port() {
  ensure_ufw_installed
  local ssh_port
  ssh_port="$(detect_ssh_port)"

  read -r -p "输入要关闭的端口（如 80 或 443/tcp 或 5201/udp）: " p || true
  [[ -n "${p:-}" ]] || { warn "端口不能为空"; return; }

  # 防止误封 SSH
  if [[ "$p" == "$ssh_port" || "$p" == "${ssh_port}/tcp" ]]; then
    warn "你正在尝试关闭 SSH 端口 ${ssh_port}，已阻止（防止断连）"
    return
  fi

  # 支持：80 / 443/tcp / 5201/udp
  if [[ "$p" =~ /udp$ || "$p" =~ /tcp$ ]]; then
    ufw delete allow "$p" >/dev/null 2>&1 || true
  else
    ufw delete allow "${p}/tcp" >/dev/null 2>&1 || true
  fi

  ok "已关闭 ✅ $p"
}

ufw_status_rules() {
  ensure_ufw_installed
  echo
  ufw status verbose || true
  echo
  read -r -p "回车继续..." _ || true
}

# ===== 菜单 =====
while true; do
  clear
  echo "=========== 防火墙工具（UFW 安全模式）==========="
  echo "当前后端: ufw"
  echo "说明：自动检测 SSH 端口并确保不会被封"
  echo
  echo "1) 开启防火墙（安全开启：先放行SSH）"
  echo "2) 关闭防火墙"
  echo "3) 放行端口"
  echo "4) 关闭端口（禁止误封SSH）"
  echo "5) 查看放行规则"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c || true

  case "$c" in
    1) ufw_safe_enable ;;
    2) ufw_disable ;;
    3) ufw_allow_port ;;
    4) ufw_deny_port ;;
    5) ufw_status_rules ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
