#!/usr/bin/env bash
set -euo pipefail

source /opt/server-toolbox/core/common.sh
need_root

# ===== 基础检测 =====
has_f2b() { command -v fail2ban-client >/dev/null 2>&1; }
svc() { systemctl "$@" fail2ban >/dev/null 2>&1 || true; }

detect_pkg_mgr() {
  if command -v apt >/dev/null 2>&1; then echo "apt"; return; fi
  if command -v dnf >/dev/null 2>&1; then echo "dnf"; return; fi
  if command -v yum >/dev/null 2>&1; then echo "yum"; return; fi
  if command -v apk >/dev/null 2>&1; then echo "apk"; return; fi
  echo "unknown"
}

install_fail2ban() {
  local pm; pm="$(detect_pkg_mgr)"
  info "安装 Fail2ban（包管理器：$pm）..."
  case "$pm" in
    apt)
      apt update -y || true
      apt install -y fail2ban || true
      ;;
    dnf)
      dnf install -y fail2ban || true
      ;;
    yum)
      yum install -y epel-release >/dev/null 2>&1 || true
      yum install -y fail2ban || true
      ;;
    apk)
      apk add --no-cache fail2ban || true
      ;;
    *)
      err "不支持的系统包管理器，无法自动安装"
      return
      ;;
  esac

  if has_f2b; then ok "Fail2ban 安装完成 ✅"
  else err "Fail2ban 安装失败（请检查系统源/磁盘空间）"; fi
}

start_fail2ban() {
  svc start
  ok "已启动 Fail2ban ✅"
}

enable_fail2ban() {
  svc enable
  ok "已设置开机自启 ✅"
}

status_fail2ban() {
  echo
  systemctl status fail2ban --no-pager || true
  echo
  read -r -p "回车继续..." _ || true
}

restart_fail2ban() {
  svc restart
  ok "已重启 Fail2ban ✅"
}

copy_jail_local() {
  if [[ -f /etc/fail2ban/jail.local ]]; then
    warn "已存在 /etc/fail2ban/jail.local，跳过复制"
  else
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    ok "已生成 /etc/fail2ban/jail.local ✅"
  fi
}

edit_jail_local() {
  copy_jail_local
  ${EDITOR:-nano} /etc/fail2ban/jail.local
}

# ===== SSH 防护快速配置 =====
write_sshd_jail() {
  copy_jail_local
  # 追加 sshd 配置（如已存在则不重复写）
  if grep -q "^\[sshd\]" /etc/fail2ban/jail.local 2>/dev/null; then
    warn "jail.local 已存在 [sshd]，跳过写入"
    return
  fi

  cat >>/etc/fail2ban/jail.local <<'EOF'

[sshd]
enabled = true
port = ssh
mode = normal
logpath = %(sshd_log)s
backend = systemd
maxretry = 5
findtime = 10m
bantime = 12h
EOF

  ok "已写入 SSH 防护配置 [sshd] ✅"
}

ssh_defense_menu() {
  echo
  info "SSH 防护向导："
  echo "1) 写入 [sshd] 防护（推荐）"
  echo "2) 清空 /etc/fail2ban/jail.d/*（谨慎）"
  echo "3) 写入后重启 Fail2ban"
  echo "0) 返回"
  echo
  read -r -p "请选择: " x || true

  case "$x" in
    1) write_sshd_jail ;;
    2)
      warn "将删除 /etc/fail2ban/jail.d/*"
      read -r -p "确认删除？(y/N): " yn || true
      [[ "${yn,,}" == "y" ]] || return
      rm -rf /etc/fail2ban/jail.d/* || true
      ok "已清空 jail.d ✅"
      ;;
    3) restart_fail2ban ;;
    0) return ;;
    *) warn "无效选项" ;;
  esac
}

# ===== 查看封禁/解封 =====
ban_list_all() {
  if ! has_f2b; then err "未安装 Fail2ban"; return; fi
  echo
  fail2ban-client status || true
  echo
  read -r -p "回车继续..." _ || true
}

ban_status_sshd() {
  if ! has_f2b; then err "未安装 Fail2ban"; return; fi
  echo
  fail2ban-client status sshd || true
  echo
  read -r -p "回车继续..." _ || true
}

unban_ip() {
  if ! has_f2b; then err "未安装 Fail2ban"; return; fi
  read -r -p "输入要解封的 IP: " ip || true
  [[ -n "${ip:-}" ]] || { warn "IP 不能为空"; return; }
  fail2ban-client set sshd unbanip "$ip" >/dev/null 2>&1 || true
  ok "已尝试解封 ✅  $ip"
}

ban_ip_manual() {
  if ! has_f2b; then err "未安装 Fail2ban"; return; fi
  read -r -p "输入要封禁的 IP: " ip || true
  [[ -n "${ip:-}" ]] || { warn "IP 不能为空"; return; }
  fail2ban-client set sshd banip "$ip" >/dev/null 2>&1 || true
  ok "已尝试封禁 ✅  $ip"
}

whitelist_ip() {
  copy_jail_local
  read -r -p "输入要加入白名单的 IP（忽略封禁）: " ip || true
  [[ -n "${ip:-}" ]] || { warn "IP 不能为空"; return; }

  if grep -q "^ignoreip" /etc/fail2ban/jail.local; then
    # 追加到 ignoreip 行末
    sed -i "s/^ignoreip.*/& ${ip}/" /etc/fail2ban/jail.local
  else
    # 新增 ignoreip 行
    printf "\n# 白名单（永不封禁）\nignoreip = 127.0.0.1/8 ::1 %s\n" "$ip" >>/etc/fail2ban/jail.local
  fi

  ok "已加入白名单 ✅  $ip"
  restart_fail2ban
}

view_jail_local() {
  if [[ -f /etc/fail2ban/jail.local ]]; then
    echo
    sed -n '1,220p' /etc/fail2ban/jail.local
    echo
  else
    warn "不存在 /etc/fail2ban/jail.local"
  fi
  read -r -p "回车继续..." _ || true
}

reset_config_backup() {
  warn "将备份并重置 Fail2ban 配置（仅重置 jail.local）"
  read -r -p "确认继续？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return

  if [[ -f /etc/fail2ban/jail.local ]]; then
    cp /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.bak.$(date +%F_%H%M%S)" || true
    rm -f /etc/fail2ban/jail.local || true
    ok "已备份并删除 jail.local ✅"
  else
    warn "没有 jail.local，无需重置"
  fi

  restart_fail2ban
}

# ===== 主菜单 =====
main_menu() {
  while true; do
    clear
    echo "=============================================="
    echo "            Fail2ban 安全防护中心"
    echo "=============================================="
    if has_f2b; then
      echo "状态: $(systemctl is-active fail2ban 2>/dev/null || echo unknown) / 自启: $(systemctl is-enabled fail2ban 2>/dev/null || echo unknown)"
    else
      echo "状态: 未安装"
    fi
    echo
    echo "1) 安装 Fail2ban"
    echo "2) 启动服务"
    echo "3) 开机自启"
    echo "4) 查看服务状态"
    echo "5) 生成配置文件 jail.local"
    echo "6) 编辑 jail.local"
    echo "7) 重启服务"
    echo "8) SSH 防护向导（写入 [sshd]）"
    echo "9) 查看封禁列表（总览）"
    echo "10) 查看 SSH 封禁情况"
    echo "11) 解封 IP（sshd）"
    echo "12) 手动封禁 IP（sshd）"
    echo "13) 添加白名单 IP（忽略封禁）"
    echo "14) 查看 jail.local（前220行）"
    echo "15) 重置配置（备份 jail.local 后重置）"
    echo "0) 返回"
    echo
    read -r -p "请输入选项: " c || true

    case "$c" in
      1) install_fail2ban ;;
      2) start_fail2ban ;;
      3) enable_fail2ban ;;
      4) status_fail2ban ;;
      5) copy_jail_local ;;
      6) edit_jail_local ;;
      7) restart_fail2ban ;;
      8) ssh_defense_menu ;;
      9) ban_list_all ;;
      10) ban_status_sshd ;;
      11) unban_ip ;;
      12) ban_ip_manual ;;
      13) whitelist_ip ;;
      14) view_jail_local ;;
      15) reset_config_backup ;;
      0) break ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

main_menu
