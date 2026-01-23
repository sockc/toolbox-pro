#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

install_pkg() {
  local pkg="$1"
  if command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y "$pkg"
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install "$pkg"
  elif command -v yum >/dev/null 2>&1; then
    yum -y install "$pkg"
  else
    warn "未知包管理器，请手动安装：$pkg"
  fi
}

while true; do
  clear
  echo "=========== 下载工具 ==========="
  echo "1) aria2 (多线程下载)"
  echo "2) rclone (网盘/同步)"
  echo "3) axel (加速下载)"
  echo "4) yt-dlp (视频下载)"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  case "$c" in
    1) install_pkg aria2; ok "aria2 安装完成 ✅"; read -r -p "回车继续..." _ ;;
    2) install_pkg rclone; ok "rclone 安装完成 ✅"; read -r -p "回车继续..." _ ;;
    3) install_pkg axel; ok "axel 安装完成 ✅"; read -r -p "回车继续..." _ ;;
    4)
      install_pkg python3-pip || true
      pip3 install -U yt-dlp || true
      ok "yt-dlp 安装完成 ✅"
      read -r -p "回车继续..." _
      ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
