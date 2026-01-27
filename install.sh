#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/sockc/toolbox-pro/main"
INSTALL_DIR="/opt/server-toolbox"

c() {
  case "$1" in
    g) echo -e "\033[32m$2\033[0m" ;;
    y) echo -e "\033[33m$2\033[0m" ;;
    r) echo -e "\033[31m$2\033[0m" ;;
    b) echo -e "\033[36m$2\033[0m" ;;
    *) echo "$2" ;;
  esac
}
ok(){ c g "[OK] $*"; }
warn(){ c y "[!] $*"; }
err(){ c r "[X] $*"; }
info(){ c b "[*] $*"; }

need_root() {
  [[ "${EUID}" -eq 0 ]] || { err "请用 root 执行：sudo -i"; exit 1; }
}

fetch() {
  # $1 = rel_path
  local rel="$1"
  local dst="${INSTALL_DIR}/${rel}"
  local url="${REPO_RAW}/${rel}"
  mkdir -p "$(dirname "$dst")"
  curl -fsSL "$url" -o "$dst"
  chmod +x "$dst" 2>/dev/null || true
}

fetch_cfg() {
  local rel="$1"
  local dst="${INSTALL_DIR}/${rel}"
  local url="${REPO_RAW}/${rel}"
  mkdir -p "$(dirname "$dst")"
  curl -fsSL "$url" -o "$dst" || true
}

main() {
  need_root

  # 强制把临时目录挪到更稳定位置，避免 /tmp 爆掉时 apt 无法工作
  mkdir -p /var/tmp/toolbox-tmp >/dev/null 2>&1 || true
  export TMPDIR="/var/tmp/toolbox-tmp"

  echo
  info "[1/4] 安装依赖（带自动修复）..."
  bash <(curl -fsSL "${REPO_RAW}/scripts/deps.sh")

  echo
  info "[2/4] 拉取核心 + 模块 + 配置..."
  mkdir -p "${INSTALL_DIR}/core" "${INSTALL_DIR}/modules" "${INSTALL_DIR}/config"

  # 核心
  fetch "core/menu.sh"
  fetch "core/common.sh"
  fetch "core/version.txt"

  # ===== 模块列表（你新增模块时，把路径加在这里即可）=====
  MODULES=(
    "modules/docker/docker.sh"
    "modules/system/system.sh"
    "modules/plugins/plugins.sh"
    "modules/download/download.sh"
    "modules/ssh/ssh.sh"
    "modules/firewall/firewall.sh"
    "modules/proxy/proxy.sh"
    "modules/rescue/rescue.sh"
    "modules/fail2ban/fail2ban.sh"
  )

  for m in "${MODULES[@]}"; do
    fetch "$m"
  done

  # 配置文件（不存在也不报错，防止你还没提交）
  fetch_cfg "config/containers.json"
  fetch_cfg "config/plugins.json"

  ok "核心/模块/配置 已拉取完成 ✅"

  echo
  info "[3/4] 创建快捷命令：toolbox"
  cat >/usr/local/bin/toolbox <<SH
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${EUID}" -ne 0 ]]; then
  exec sudo -i -c "${INSTALL_DIR}/core/menu.sh"
fi
exec ${INSTALL_DIR}/core/menu.sh
SH
  chmod +x /usr/local/bin/toolbox
  ok "安装完成 ✅ 输入 toolbox 进入菜单"

  echo
  info "[4/4] 启动菜单..."
  if [[ -t 0 ]]; then
    toolbox
  else
    [[ -e /dev/tty ]] && toolbox </dev/tty || {
      warn "当前环境无 /dev/tty，无法交互"
      echo "请手动运行：sudo -i && toolbox"
      exit 2
    }
  fi
}

main "$@"
