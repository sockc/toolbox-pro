#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

pkg_install() {
  local p="$1"
  if command -v apt >/dev/null 2>&1; then
    apt update -y && apt install -y "$p" || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install "$p" || true
  elif command -v yum >/dev/null 2>&1; then
    yum -y install "$p" || true
  fi
}

sys_update() {
  info "系统更新..."
  if command -v apt >/dev/null 2>&1; then
    apt update -y && apt upgrade -y
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y upgrade
  elif command -v yum >/dev/null 2>&1; then
    yum -y update
  fi
  ok "更新完成 ✅"
}

sys_info() {
  echo "CPU/内存/磁盘："
  uptime
  free -h || true
  df -hT | head -n 20
  echo
  echo "网络："
  ip a | head -n 60
}

clean_system() {
  info "清理系统缓存/日志..."
  journalctl --vacuum-time=7d >/dev/null 2>&1 || true
  if command -v apt >/dev/null 2>&1; then
    apt autoremove -y && apt clean
  fi
  ok "清理完成 ✅"
}

enable_bbr() {
  info "开启 BBR..."
  cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null 2>&1 || true
  ok "已尝试开启 BBR ✅"
}

swap_add() {
  read -r -p "输入 Swap 大小（如 2G/4G）: " sz
  [[ -n "$sz" ]] || { warn "未输入"; return; }
  fallocate -l "$sz" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  ok "Swap 已启用 ✅"
}

time_set() {
  read -r -p "输入时区（如 Asia/Shanghai 或 America/Los_Angeles）: " tz
  [[ -n "$tz" ]] || return
  timedatectl set-timezone "$tz" || true
  timedatectl
}

hostname_set() {
  read -r -p "输入新主机名: " hn
  [[ -n "$hn" ]] || return
  hostnamectl set-hostname "$hn" || true
  ok "已修改主机名 ✅"
}

open_ports() {
  info "当前监听端口："
  ss -lntup | head -n 120 || true
}

fail2ban_install() {
  pkg_install fail2ban
  systemctl enable --now fail2ban >/dev/null 2>&1 || true
  ok "Fail2ban 已启用 ✅"
}

speedtest_install() {
  pkg_install speedtest-cli
  speedtest-cli || true
}

while true; do
  clear
  echo "=========== 系统工具 PRO ==========="
  echo "1) 系统更新 upgrade"
  echo "2) 系统信息（CPU/内存/磁盘/网络）"
  echo "3) 清理系统（日志/缓存）"
  echo "4) 开启 BBR"
  echo "5) 添加 Swap"
  echo "6) 设置时区"
  echo "7) 修改主机名"
  echo "8) 查看监听端口"
  echo "9) 安装 Fail2ban"
  echo "10) Speedtest 测速"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  case "$c" in
    1) sys_update; read -r -p "回车继续..." _ ;;
    2) sys_info; read -r -p "回车继续..." _ ;;
    3) clean_system; read -r -p "回车继续..." _ ;;
    4) enable_bbr; read -r -p "回车继续..." _ ;;
    5) swap_add; read -r -p "回车继续..." _ ;;
    6) time_set; read -r -p "回车继续..." _ ;;
    7) hostname_set; read -r -p "回车继续..." _ ;;
    8) open_ports; read -r -p "回车继续..." _ ;;
    9) fail2ban_install; read -r -p "回车继续..." _ ;;
    10) speedtest_install; read -r -p "回车继续..." _ ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
