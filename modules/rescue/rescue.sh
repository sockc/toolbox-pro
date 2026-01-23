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

pause() { read -r -p "回车继续..." _; }

show_net() {
  echo "==== IP 地址 ===="
  ip a | head -n 120 || true
  echo
  echo "==== 路由表 ===="
  ip r || true
  echo
  echo "==== DNS 配置 ===="
  (command -v resolvectl >/dev/null 2>&1 && resolvectl status | head -n 120) || true
  echo
  cat /etc/resolv.conf 2>/dev/null || true
}

ping_test() {
  echo "==== IPv4 测试 ===="
  ping -c 2 1.1.1.1 || true
  echo
  echo "==== IPv6 测试 ===="
  ping -6 -c 2 2606:4700:4700::1111 || true
  echo
  echo "==== DNS 解析测试 ===="
  getent hosts google.com || true
  getent hosts github.com || true
}

fix_dns_quick() {
  warn "这会临时写入公共 DNS 到 /etc/resolv.conf（部分系统会被 NetworkManager/systemd 覆盖）"
  cat >/etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
EOF
  ok "已写入 DNS ✅"
  ping_test
}

fix_dns_systemd_resolved() {
  if ! systemctl list-unit-files | grep -q systemd-resolved; then
    warn "未检测到 systemd-resolved，跳过"
    return
  fi
  info "配置 systemd-resolved DNS..."
  mkdir -p /etc/systemd/resolved.conf.d >/dev/null 2>&1 || true
  cat >/etc/systemd/resolved.conf.d/dns.conf <<'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=2606:4700:4700::1111 2001:4860:4860::8888
EOF
  systemctl restart systemd-resolved || true
  ok "systemd-resolved 已重启 ✅"
  resolvectl status | head -n 80 || true
}

restart_network() {
  info "尝试重启网络服务..."
  systemctl restart networking 2>/dev/null || true
  systemctl restart NetworkManager 2>/dev/null || true
  systemctl restart systemd-networkd 2>/dev/null || true
  ok "已尝试重启网络 ✅"
  show_net
}

restart_services() {
  echo "1) 重启 SSH"
  echo "2) 重启 Docker"
  echo "3) 重启 Fail2ban"
  echo "4) 重启全部（SSH+Docker+Fail2ban）"
  echo "0) 返回"
  read -r -p "请选择: " c
  case "$c" in
    1)
      systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
      ok "SSH 已重启 ✅"
      ;;
    2)
      systemctl restart docker 2>/dev/null || true
      ok "Docker 已重启 ✅"
      ;;
    3)
      systemctl restart fail2ban 2>/dev/null || true
      ok "Fail2ban 已重启 ✅"
      ;;
    4)
      systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
      systemctl restart docker 2>/dev/null || true
      systemctl restart fail2ban 2>/dev/null || true
      ok "已重启关键服务 ✅"
      ;;
    0) ;;
    *) warn "无效选项" ;;
  esac
}

disk_top() {
  info "磁盘占用（/）Top 20："
  du -xhd1 / 2>/dev/null | sort -h | tail -n 20 || true
  echo
  info "/var 占用 Top 20："
  du -xhd1 /var 2>/dev/null | sort -h | tail -n 20 || true
  echo
  info "/opt 占用 Top 20："
  du -xhd1 /opt 2>/dev/null | sort -h | tail -n 20 || true
}

docker_space() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "未安装 Docker"
    return
  fi
  docker system df || true
}

docker_cleanup_safe() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "未安装 Docker"
    return
  fi
  warn "即将清理 Docker 无用镜像/容器/网络（不会删正在运行的容器）"
  read -r -p "确认执行？(y/N): " yn
  [[ "${yn,,}" == "y" ]] || return
  docker system prune -af || true
  ok "清理完成 ✅"
  docker system df || true
}

log_errors() {
  info "最近 200 行系统错误日志（journalctl -p 0..3）"
  journalctl -p 0..3 -n 200 --no-pager || true
}

log_service() {
  read -r -p "输入服务名（如 ssh / docker / hysteria-server）: " svc
  [[ -n "$svc" ]] || return
  journalctl -u "$svc" -n 200 --no-pager || true
}

fix_time_sync() {
  info "修复时间同步（NTP）..."
  timedatectl set-ntp true >/dev/null 2>&1 || true
  systemctl restart systemd-timesyncd 2>/dev/null || true
  timedatectl status || true
  ok "已尝试修复时间同步 ✅"
}

while true; do
  clear
  echo "=========== 系统急救菜单（Rescue） ==========="
  echo "1) 查看网络信息（IP/路由/DNS）"
  echo "2) 网络连通测试（IPv4/IPv6/DNS解析）"
  echo "3) 快速修复 DNS（写入 1.1.1.1/8.8.8.8）"
  echo "4) 修复 systemd-resolved DNS（推荐）"
  echo "5) 重启网络服务（networking/NM/systemd-networkd）"
  echo "6) 重启关键服务（SSH/Docker/Fail2ban）"
  echo "7) 磁盘占用定位（Top 20）"
  echo "8) Docker 占用查看（docker system df）"
  echo "9) Docker 清理（safe prune）"
  echo "10) 查看系统错误日志（journalctl）"
  echo "11) 查看指定服务日志（journalctl -u）"
  echo "12) 修复时间同步（NTP）"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  case "$c" in
    1) show_net; pause ;;
    2) ping_test; pause ;;
    3) fix_dns_quick; pause ;;
    4) fix_dns_systemd_resolved; pause ;;
    5) restart_network; pause ;;
    6) restart_services; pause ;;
    7) disk_top; pause ;;
    8) docker_space; pause ;;
    9) docker_cleanup_safe; pause ;;
    10) log_errors; pause ;;
    11) log_service; pause ;;
    12) fix_time_sync; pause ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
