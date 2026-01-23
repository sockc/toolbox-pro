#!/usr/bin/env bash
set -euo pipefail

log(){ echo -e "$*"; }
ok(){ log "\033[32m[OK]\033[0m $*"; }
warn(){ log "\033[33m[!]\033[0m $*"; }
err(){ log "\033[31m[X]\033[0m $*"; }

# 临时目录兜底（/tmp 满了 apt 会炸）
mkdir -p /var/tmp/toolbox-tmp >/dev/null 2>&1 || true
export TMPDIR="/var/tmp/toolbox-tmp"

is_debian_like() { command -v apt >/dev/null 2>&1; }
has_docker() { command -v docker >/dev/null 2>&1; }

# 检查根分区可用空间（MB）
free_mb_root() {
  df -Pm / 2>/dev/null | awk 'NR==2{print $4}' || echo 0
}

# 轻量清理（安全）
auto_cleanup_safe() {
  warn "检测到磁盘空间不足或 /tmp 写入失败，执行安全清理..."

  # journald 清理
  journalctl --vacuum-time=7d >/dev/null 2>&1 || true
  journalctl --vacuum-size=200M >/dev/null 2>&1 || true

  # apt 缓存
  if is_debian_like; then
    apt clean >/dev/null 2>&1 || true
    rm -rf /var/lib/apt/lists/* >/dev/null 2>&1 || true
  fi

  # /tmp 清理
  rm -rf /tmp/* >/dev/null 2>&1 || true

  # docker 清理（需要确认）
  if has_docker; then
    warn "检测到 Docker，可能占用大量空间"
    read -r -p "是否执行 Docker 清理（prune）？(y/N): " yn </dev/tty 2>/dev/null || yn="n"
    if [[ "${yn,,}" == "y" ]]; then
      docker system prune -af >/dev/null 2>&1 || true
      docker volume prune -f >/dev/null 2>&1 || true
      ok "Docker 清理完成 ✅"
    else
      warn "已跳过 Docker 清理"
    fi
  fi

  ok "安全清理完成 ✅"
}

# apt 锁检测
apt_locked() {
  # 任意一个锁存在且被占用，都算 locked
  fuser /var/lib/apt/lists/lock >/dev/null 2>&1 && return 0 || true
  fuser /var/lib/dpkg/lock >/dev/null 2>&1 && return 0 || true
  fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && return 0 || true
  return 1
}

show_apt_lockers() {
  warn "APT/DPKG 正被占用，下面是占用进程："
  for f in /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend; do
    if [[ -e "$f" ]]; then
      echo ">> $f"
      fuser -v "$f" 2>/dev/null || true
    fi
  done
  echo
}

try_fix_dpkg() {
  dpkg --configure -a >/dev/null 2>&1 || true
  apt --fix-broken install -y >/dev/null 2>&1 || true
}

wait_or_kill_apt_lock() {
  # 尝试等待几次，如果一直锁着，给用户选择是否 kill
  local i=0
  while apt_locked; do
    i=$((i+1))
    if [[ "$i" -le 3 ]]; then
      warn "检测到 APT 锁占用，尝试等待释放...（第 ${i} 次）"
      sleep 2
    else
      show_apt_lockers
      read -r -p "锁长期占用，是否强制结束占用进程？(y/N): " yn </dev/tty 2>/dev/null || yn="n"
      if [[ "${yn,,}" == "y" ]]; then
        # 找出占用锁的 PID 并 kill
        local pids=""
        pids="$(fuser /var/lib/apt/lists/lock 2>/dev/null || true)"
        pids="${pids} $(fuser /var/lib/dpkg/lock 2>/dev/null || true)"
        pids="${pids} $(fuser /var/lib/dpkg/lock-frontend 2>/dev/null || true)"
        pids="$(echo "$pids" | tr ' ' '\n' | awk 'NF{print $1}' | sort -u | tr '\n' ' ')"

        if [[ -n "$pids" ]]; then
          warn "即将 kill：$pids"
          kill $pids >/dev/null 2>&1 || true
          sleep 2
          # 还不死就 -9
          if apt_locked; then
            warn "仍未释放锁，执行 kill -9：$pids"
            kill -9 $pids >/dev/null 2>&1 || true
            sleep 1
          fi
          ok "已处理占用进程 ✅"
          try_fix_dpkg
        else
          warn "未能自动提取 PID（但锁仍存在）"
        fi
      else
        err "APT 锁未释放，无法继续。你可以稍后再运行安装。"
        exit 1
      fi
    fi
  done
}

# -----------------------------------------------------------
# 主逻辑：先救系统，再装依赖
# -----------------------------------------------------------

# 1) 检查磁盘空间，太小就清理
root_free="$(free_mb_root)"
if [[ "${root_free}" -lt 300 ]]; then
  warn "根分区可用空间过低：${root_free}MB"
  auto_cleanup_safe
fi

# 2) 检查 /tmp 写入
if ! (echo test > /tmp/.toolbox_write_test 2>/dev/null); then
  warn "/tmp 无法写入（通常是磁盘满）"
  auto_cleanup_safe
else
  rm -f /tmp/.toolbox_write_test >/dev/null 2>&1 || true
fi

# 3) APT 锁处理
if is_debian_like; then
  wait_or_kill_apt_lock
fi

# 4) 开始安装依赖
if is_debian_like; then
  apt update -y || {
    warn "apt update 失败，尝试执行清理 + 再试一次"
    auto_cleanup_safe
    wait_or_kill_apt_lock
    apt update -y
  }

  apt install -y curl wget ca-certificates openssl iproute2 jq unzip tar qrencode || {
    warn "依赖安装失败，尝试 dpkg 修复后重试"
    try_fix_dpkg
    apt install -y curl wget ca-certificates openssl iproute2 jq unzip tar qrencode
  }

  ok "依赖安装完成 ✅"
  exit 0
fi

if command -v dnf >/dev/null 2>&1; then
  dnf -y install curl wget ca-certificates openssl iproute jq unzip tar || true
  ok "依赖安装完成 ✅"
  exit 0
fi

if command -v yum >/dev/null 2>&1; then
  yum -y install curl wget ca-certificates openssl iproute jq unzip tar || true
  ok "依赖安装完成 ✅"
  exit 0
fi

warn "暂未适配该系统包管理器，请手动安装：curl/wget/jq/openssl"
exit 1
