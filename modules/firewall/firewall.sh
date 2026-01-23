#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

has_ufw() { command -v ufw >/dev/null 2>&1; }
has_fwcmd() { command -v firewall-cmd >/dev/null 2>&1; }
has_iptables() { command -v iptables >/dev/null 2>&1; }

fw_backend() {
  if has_ufw; then echo "ufw"; return; fi
  if has_fwcmd; then echo "firewalld"; return; fi
  if has_iptables; then echo "iptables"; return; fi
  echo "none"
}

fw_enable() {
  local b; b="$(fw_backend)"
  case "$b" in
    ufw)
      ufw --force enable >/dev/null 2>&1 || true
      ok "UFW 已开启 ✅"
      ;;
    firewalld)
      systemctl enable --now firewalld >/dev/null 2>&1 || true
      ok "Firewalld 已开启 ✅"
      ;;
    iptables)
      warn "iptables 无“开启/关闭”概念（规则即时生效），建议用 ufw/firewalld"
      ;;
    none)
      warn "未检测到 ufw/firewalld/iptables"
      ;;
  esac
}

fw_disable() {
  local b; b="$(fw_backend)"
  case "$b" in
    ufw)
      ufw --force disable >/dev/null 2>&1 || true
      ok "UFW 已关闭 ✅"
      ;;
    firewalld)
      systemctl disable --now firewalld >/dev/null 2>&1 || true
      ok "Firewalld 已关闭 ✅"
      ;;
    iptables)
      warn "iptables 无“关闭”概念（你可以清空规则，但风险很大）"
      ;;
    none)
      warn "未检测到 ufw/firewalld/iptables"
      ;;
  esac
}

fw_allow() {
  read -r -p "输入端口（如 443 或 443-445）: " port
  read -r -p "协议 tcp/udp（默认 tcp）: " proto
  proto="${proto:-tcp}"

  local b; b="$(fw_backend)"
  case "$b" in
    ufw)
      ufw allow "${port}/${proto}" >/dev/null 2>&1 || true
      ok "已放行 ${port}/${proto} ✅"
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      ok "已放行 ${port}/${proto} ✅"
      ;;
    iptables)
      iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1 || true
      ok "已放行 ${port}/${proto} ✅（iptables 可能不持久化）"
      ;;
    none)
      warn "未检测到可用防火墙工具"
      ;;
  esac
}

fw_deny() {
  read -r -p "输入端口（如 443 或 443-445）: " port
  read -r -p "协议 tcp/udp（默认 tcp）: " proto
  proto="${proto:-tcp}"

  local b; b="$(fw_backend)"
  case "$b" in
    ufw)
      ufw delete allow "${port}/${proto}" >/dev/null 2>&1 || true
      ufw deny "${port}/${proto}" >/dev/null 2>&1 || true
      ok "已关闭 ${port}/${proto} ✅"
      ;;
    firewalld)
      firewall-cmd --permanent --remove-port="${port}/${proto}" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      ok "已关闭 ${port}/${proto} ✅"
      ;;
    iptables)
      iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1 || true
      ok "已关闭 ${port}/${proto} ✅（iptables 可能有多条规则需重复执行）"
      ;;
    none)
      warn "未检测到可用防火墙工具"
      ;;
  esac
}

fw_list() {
  local b; b="$(fw_backend)"
  case "$b" in
    ufw)
      ufw status numbered || true
      ;;
    firewalld)
      firewall-cmd --list-all || true
      ;;
    iptables)
      iptables -S INPUT | head -n 80
      ;;
    none)
      warn "未检测到可用防火墙工具"
      ;;
  esac
}

while true; do
  clear
  echo "=========== 防火墙工具 ==========="
  echo "当前后端: $(fw_backend)"
  echo "1) 开启防火墙"
  echo "2) 关闭防火墙"
  echo "3) 放行端口"
  echo "4) 关闭端口"
  echo "5) 查看放行规则"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  case "$c" in
    1) fw_enable; read -r -p "回车继续..." _ ;;
    2) fw_disable; read -r -p "回车继续..." _ ;;
    3) fw_allow; read -r -p "回车继续..." _ ;;
    4) fw_deny; read -r -p "回车继续..." _ ;;
    5) fw_list; read -r -p "回车继续..." _ ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
