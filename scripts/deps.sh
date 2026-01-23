#!/usr/bin/env bash
set -euo pipefail

if command -v apt >/dev/null 2>&1; then
  apt update -y
  apt install -y curl wget ca-certificates openssl iproute2 jq unzip tar qrencode
  echo "[OK] 依赖安装完成 ✅"
  exit 0
fi

if command -v dnf >/dev/null 2>&1; then
  dnf -y install curl wget ca-certificates openssl iproute jq unzip tar
  echo "[OK] 依赖安装完成 ✅"
  exit 0
fi

if command -v yum >/dev/null 2>&1; then
  yum -y install curl wget ca-certificates openssl iproute jq unzip tar
  echo "[OK] 依赖安装完成 ✅"
  exit 0
fi

echo "[!] 暂未适配该系统包管理器，请手动安装：curl/wget/jq/openssl"
exit 1
