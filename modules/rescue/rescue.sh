#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

pause() { read -r -p "回车继续..." _; }

is_debian_like() { command -v apt >/dev/null 2>&1; }

# ---------- 基础信息/网络 ----------
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
  warn "临时写入公共 DNS 到 /etc/resolv.conf（部分系统可能会被覆盖）"
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
    1) systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true; ok "SSH 已重启 ✅" ;;
    2) systemctl restart docker 2>/dev/null || true; ok "Docker 已重启 ✅" ;;
    3) systemctl restart fail2ban 2>/dev/null || true; ok "Fail2ban 已重启 ✅" ;;
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

# ---------- 磁盘/Docker ----------
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
  warn "将清理无用镜像/容器/网络（不删正在运行的容器）"
  read -r -p "确认执行？(y/N): " yn
  [[ "${yn,,}" == "y" ]] || return
  docker system prune -af || true
  ok "清理完成 ✅"
  docker system df || true
}

# ---------- 日志 ----------
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

# ==========================================================
# =============== 4 个硬核按钮（新增） =======================
# ==========================================================

# 1) 修复 APT 源 + apt 基础修复（Debian/Ubuntu）
apt_fix_all() {
  is_debian_like || { warn "非 Debian/Ubuntu 系统，跳过"; return; }

  info "一键修复 APT（清理缓存 + 更新索引 + 基础修复）..."

  # 写 DNS，避免“解析失败”
  fix_dns_quick >/dev/null 2>&1 || true

  rm -rf /var/lib/apt/lists/* >/dev/null 2>&1 || true
  apt clean >/dev/null 2>&1 || true
  apt update -y || true

  # 常见 broken 依赖修复
  apt --fix-broken install -y || true
  dpkg --configure -a || true

  ok "APT 修复流程执行完毕 ✅（如仍失败，多半是源不可用/网络被墙/时间错误）"
}

# 2) 释放内存（drop_caches）+ 可选重启服务
memory_emergency() {
  info "当前内存："
  free -h || true
  echo

  warn "将执行 drop_caches（不等于真正清理所有内存，但可救急）"
  read -r -p "确认执行？(y/N): " yn
  [[ "${yn,,}" == "y" ]] || return

  sync
  echo 3 >/proc/sys/vm/drop_caches || true
  ok "已执行 drop_caches ✅"
  free -h || true
  echo

  read -r -p "是否顺便重启 Docker/SSH 等服务？(y/N): " yn2
  [[ "${yn2,,}" == "y" ]] && restart_services
}

# 3) 端口占用查杀（按端口定位 PID，并可 kill）
port_killer() {
  read -r -p "输入要检查的端口（如 80）: " p
  [[ "$p" =~ ^[0-9]+$ ]] || { warn "端口必须是数字"; return; }

  info "查找占用端口 ${p} 的进程..."
  if command -v ss >/dev/null 2>&1; then
    ss -lntup | grep -E "[:.]${p}\b" || { warn "未发现占用该端口"; return; }
  elif command -v lsof >/dev/null 2>&1; then
    lsof -i :"$p" || { warn "未发现占用该端口"; return; }
  else
    warn "缺少 ss/lsof，建议安装 iproute2 或 lsof"
    return
  fi

  echo
  read -r -p "是否杀掉占用该端口的进程？(y/N): " yn
  [[ "${yn,,}" == "y" ]] || return

  # 尝试找 PID 并 kill
  local pid=""
  pid="$(ss -lntup 2>/dev/null | awk -v P=":${p}" '$0~P {print $NF}' | head -n1 | sed -E 's/.*pid=([0-9]+).*/\1/')" || true

  if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]; then
    warn "即将 kill -9 PID=${pid}"
    kill -9 "$pid" 2>/dev/null || true
    ok "已 kill PID=${pid} ✅"
  else
    warn "未能自动提取 PID（你可以手动从 ss 输出里找 pid=xxx）"
  fi
}

# 4) 备份/恢复关键配置（SSH、防火墙、sysctl、docker-compose）
backup_restore() {
  local backup_dir="/opt/server-toolbox/backups"
  mkdir -p "$backup_dir"

  echo "1) 备份关键配置"
  echo "2) 恢复最近一次备份"
  echo "3) 查看备份列表"
  echo "0) 返回"
  read -r -p "请选择: " c

  case "$c" in
    1)
      local ts; ts="$(date +%Y%m%d_%H%M%S)"
      local out="${backup_dir}/backup_${ts}.tar.gz"
      info "备份到：$out"

      tar -czf "$out" \
        /etc/ssh/sshd_config \
        /etc/ufw  \
        /etc/sysctl.conf \
        /etc/sysctl.d \
        /opt/apps \
        /opt/server-toolbox/config \
        >/dev/null 2>&1 || true

      ok "备份完成 ✅"
      ;;
    2)
      local latest
      latest="$(ls -1t "${backup_dir}"/backup_*.tar.gz 2>/dev/null | head -n1 || true)"
      [[ -n "$latest" ]] || { warn "没有可恢复的备份"; return; }

      warn "即将恢复：$latest （会覆盖部分配置）"
      read -r -p "确认恢复？(y/N): " yn
      [[ "${yn,,}" == "y" ]] || return

      tar -xzf "$latest" -C / >/dev/null 2>&1 || true
      ok "恢复完成 ✅（建议重启 SSH/防火墙/相关服务）"
      ;;
    3)
      ls -lh "$backup_dir" | tail -n 50 || true
      ;;
    0) ;;
    *) warn "无效选项" ;;
  esac
}

# ---------- 主菜单 ----------
while true; do
  clear
  echo "=========== 系统急救菜单（Rescue PRO） ==========="
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
  echo "-----------------------------------------------"
  echo "13) 【硬核】一键修复 APT（清缓存/修依赖/更新索引）"
  echo "14) 【硬核】释放内存（drop_caches + 可选重启服务）"
  echo "15) 【硬核】端口查占用 + 一键 kill"
  echo "16) 【硬核】备份/恢复关键配置"
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
    13) apt_fix_all; pause ;;
    14) memory_emergency; pause ;;
    15) port_killer; pause ;;
    16) backup_restore; pause ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
