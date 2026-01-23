#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

enable_bbr() {
  info "开启 BBR..."
  cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null 2>&1 || true
  ok "已尝试开启 BBR ✅（建议重启后确认）"
}

add_swap() {
  read -r -p "输入 Swap 大小（如 2G/4G）: " sz
  [[ -n "$sz" ]] || { warn "未输入"; return; }
  info "创建 swapfile..."
  fallocate -l "$sz" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  ok "Swap 已启用 ✅"
}

ufw_enable() {
  if ! command -v ufw >/dev/null 2>&1; then
    apt update -y && apt install -y ufw || true
  fi
  ufw allow OpenSSH >/dev/null 2>&1 || true
  ufw --force enable
  ok "UFW 已启用 ✅"
}

fail2ban_install() {
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    apt update -y && apt install -y fail2ban || true
  fi
  systemctl enable --now fail2ban || true
  ok "Fail2ban 已启用 ✅"
}

log_cleanup() {
  info "清理 journald 日志（保留 7 天）..."
  journalctl --vacuum-time=7d >/dev/null 2>&1 || true
  ok "日志清理完成 ✅"
}

while true; do
  clear
  echo "=========== 系统工具 ==========="
  echo "1) 开启 BBR"
  echo "2) 添加 Swap"
  echo "3) 启用 UFW"
  echo "4) 安装 Fail2ban"
  echo "5) 清理日志（保留7天）"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  case "$c" in
    1) enable_bbr; read -r -p "回车继续..." _ ;;
    2) add_swap; read -r -p "回车继续..." _ ;;
    3) ufw_enable; read -r -p "回车继续..." _ ;;
    4) fail2ban_install; read -r -p "回车继续..." _ ;;
    5) log_cleanup; read -r -p "回车继续..." _ ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
