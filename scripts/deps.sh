#!/usr/bin/env bash
set -euo pipefail

if command -v apt >/dev/null 2>&1; then
  apt update -y
  apt install -y curl wget ca-certificates openssl iproute2 jq unzip tar qrencode
  echo "[OK] 依赖安装完成 ✅"
  exit 0
fi

echo "[!] 暂未适配该系统的包管理器，请手动安装 curl/wget/jq/openssl"
exit 1
