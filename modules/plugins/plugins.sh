#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

install_ctop() {
  if command -v ctop >/dev/null 2>&1; then ok "ctop 已安装"; return; fi
  info "安装 ctop..."
  curl -fsSL https://github.com/bcicen/ctop/releases/latest/download/ctop-0.7.7-linux-amd64 -o /usr/local/bin/ctop || true
  chmod +x /usr/local/bin/ctop || true
  ok "ctop 安装完成 ✅ 输入 ctop 运行"
}

install_lazydocker() {
  if command -v lazydocker >/dev/null 2>&1; then ok "lazydocker 已安装"; return; fi
  info "安装 lazydocker..."
  curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
  ok "lazydocker 安装完成 ✅ 输入 lazydocker 运行"
}

while true; do
  clear
  echo "=========== 常用插件 ==========="
  echo "1) 安装 ctop（容器监控）"
  echo "2) 安装 lazydocker（Docker TUI）"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  case "$c" in
    1) install_ctop; read -r -p "回车继续..." _ ;;
    2) install_lazydocker; read -r -p "回车继续..." _ ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
