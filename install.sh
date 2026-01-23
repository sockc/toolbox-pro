#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/vinchi008/toolbox-pro/main"
INSTALL_DIR="/opt/server-toolbox"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[X] 请用 root 执行：sudo -i"
  exit 1
fi

# 强制把临时目录挪到更稳定位置，避免 /tmp 爆掉时 apt 无法工作
mkdir -p /var/tmp/toolbox-tmp >/dev/null 2>&1 || true
export TMPDIR="/var/tmp/toolbox-tmp"

echo "[1/4] 安装依赖（带自动修复）..."
bash <(curl -fsSL "${REPO_RAW}/scripts/deps.sh")

echo "[2/4] 拉取核心文件..."
mkdir -p "${INSTALL_DIR}/core" "${INSTALL_DIR}/modules" "${INSTALL_DIR}/config"

curl -fsSL "${REPO_RAW}/core/menu.sh" -o "${INSTALL_DIR}/core/menu.sh"
curl -fsSL "${REPO_RAW}/core/common.sh" -o "${INSTALL_DIR}/core/common.sh"
curl -fsSL "${REPO_RAW}/core/version.txt" -o "${INSTALL_DIR}/core/version.txt"
chmod +x "${INSTALL_DIR}/core/menu.sh"

echo "[3/4] 创建快捷命令：toolbox"
cat >/usr/local/bin/toolbox <<SH
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${EUID}" -ne 0 ]]; then
  exec sudo -i -c "${INSTALL_DIR}/core/menu.sh"
fi
exec ${INSTALL_DIR}/core/menu.sh
SH
chmod +x /usr/local/bin/toolbox

echo "[OK] 安装完成 ✅ 输入 toolbox 进入菜单"

echo "[4/4] 启动菜单..."
if [[ -t 0 ]]; then
  toolbox
else
  [[ -e /dev/tty ]] && toolbox </dev/tty || {
    echo "[!] 当前环境无 /dev/tty，无法交互"
    echo "请手动运行：sudo -i && toolbox"
    exit 2
  }
fi
