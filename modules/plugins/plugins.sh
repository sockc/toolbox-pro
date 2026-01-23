#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

CFG="/opt/server-toolbox/config/plugins.json"
[[ -f "$CFG" ]] || { err "缺少配置：$CFG"; exit 1; }

while true; do
  clear
  echo "=========== 常用插件（配置化） ==========="
  jq -r 'to_entries[] | "\(.key+1)) \(.value.name)"' "$CFG"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c
  [[ "$c" == "0" ]] && exit 0

  idx=$((c-1))
  name="$(jq -r ".[$idx].name // empty" "$CFG")"
  check="$(jq -r ".[$idx].check // empty" "$CFG")"
  install="$(jq -r ".[$idx].install // empty" "$CFG")"

  [[ -n "$name" ]] || { warn "无效选项"; sleep 1; continue; }

  info "插件：$name"
  if bash -lc "$check" >/dev/null 2>&1; then
    ok "已安装 ✅"
  else
    info "开始安装..."
    bash -lc "$install" || true
    if bash -lc "$check" >/dev/null 2>&1; then
      ok "安装成功 ✅"
    else
      warn "安装可能失败（请检查网络/系统）"
    fi
  fi

  read -r -p "回车继续..." _
done
