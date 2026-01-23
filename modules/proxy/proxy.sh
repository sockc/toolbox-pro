#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

gen_caddyfile() {
  read -r -p "输入域名: " domain
  read -r -p "转发到本机端口（如 8080）: " port
  [[ -n "$domain" && -n "$port" ]] || { warn "域名/端口不能为空"; return; }

  mkdir -p /opt/apps/caddy >/dev/null 2>&1 || true
  cat > /opt/apps/caddy/Caddyfile <<EOF
${domain} {
  reverse_proxy 127.0.0.1:${port}
  encode gzip
}
EOF
  ok "已生成：/opt/apps/caddy/Caddyfile"
  echo "提示：你可以在 Docker 菜单部署 Caddy，然后它会自动读这个 Caddyfile"
}

npm_hint() {
  echo
  echo "Nginx Proxy Manager 使用步骤："
  echo "1) Docker 菜单部署 NPM（默认端口 81）"
  echo "2) 浏览器打开 http://IP:81"
  echo "3) 添加 Proxy Host："
  echo "   Domain: 你的域名"
  echo "   Forward Hostname: 127.0.0.1"
  echo "   Forward Port: 目标端口"
  echo "4) SSL 里申请 Let's Encrypt"
  echo
}

while true; do
  clear
  echo "=========== 反代工具 ==========="
  echo "1) 生成 Caddyfile 反代模板（推荐）"
  echo "2) NPM 反代设置指引"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  case "$c" in
    1) gen_caddyfile; read -r -p "回车继续..." _ ;;
    2) npm_hint; read -r -p "回车继续..." _ ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
