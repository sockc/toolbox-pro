#!/usr/bin/env bash
set -euo pipefail
source /opt/server-toolbox/core/common.sh
need_root

CFG="/opt/server-toolbox/config/plugins.json"
[[ -f "$CFG" ]] || { err "缺少配置：$CFG"; exit 1; }

APT_REFRESHED=0

pause() {
  read -r -p "回车继续..." _ || true
}

ensure_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  warn "插件中心需要 jq，正在安装..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y jq
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y jq
  elif command -v yum >/dev/null 2>&1; then
    yum install -y jq
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache jq
  else
    err "无法自动安装 jq"
    return 1
  fi
}

validate_cfg() {
  jq -e 'type == "array" and length > 0' "$CFG" >/dev/null 2>&1 || {
    err "plugins.json 格式错误"
    exit 1
  }
}

detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then
    echo apt
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  elif command -v yum >/dev/null 2>&1; then
    echo yum
  elif command -v apk >/dev/null 2>&1; then
    echo apk
  else
    echo unknown
  fi
}

apt_refresh_once() {
  [[ "$APT_REFRESHED" == "1" ]] && return 0
  apt-get update -y
  APT_REFRESHED=1
}

pkg_install() {
  local packages="$1"
  local pm
  pm="$(detect_pm)"
  [[ -n "$packages" && "$packages" != "null" ]] || {
    err "当前系统没有对应的软件包配置"
    return 1
  }

  local args=()
  read -r -a args <<<"$packages"

  case "$pm" in
    apt) apt_refresh_once; apt-get install -y "${args[@]}" ;;
    dnf) dnf install -y "${args[@]}" ;;
    yum) yum install -y "${args[@]}" ;;
    apk) apk add --no-cache "${args[@]}" ;;
    *) err "不支持当前系统的软件包管理器"; return 1 ;;
  esac
}

pkg_remove() {
  local packages="$1"
  local pm
  pm="$(detect_pm)"
  [[ -n "$packages" && "$packages" != "null" ]] || return 1

  local args=()
  read -r -a args <<<"$packages"

  case "$pm" in
    apt) apt-get remove -y "${args[@]}" ;;
    dnf) dnf remove -y "${args[@]}" ;;
    yum) yum remove -y "${args[@]}" ;;
    apk) apk del "${args[@]}" ;;
    *) return 1 ;;
  esac
}

field() {
  local idx="$1"
  local key="$2"
  jq -r ".["$idx"].$key // empty" "$CFG"
}

package_for_idx() {
  local idx="$1"
  local pm
  pm="$(detect_pm)"
  jq -r --arg pm "$pm" '.['"$idx"'].packages[$pm] // .['"$idx"'].packages.default // empty' "$CFG"
}

is_installed() {
  local idx="$1"
  local check
  check="$(field "$idx" check)"
  [[ -n "$check" ]] || return 1
  bash -lc "$check" >/dev/null 2>&1
}

status_text() {
  local idx="$1"
  if is_installed "$idx"; then
    printf "✓ 已安装"
  else
    printf "○ 未安装"
  fi
}

run_script_field() {
  local idx="$1"
  local key="$2"
  local cmd
  cmd="$(field "$idx" "$key")"
  [[ -n "$cmd" ]] || return 1
  bash -lc "$cmd"
}

install_idx() {
  local idx="$1"
  local name type packages
  name="$(field "$idx" name)"
  type="$(field "$idx" install_type)"

  if is_installed "$idx"; then
    ok "$name 已安装"
    return 0
  fi

  info "正在安装：$name"
  if [[ "$type" == "package" ]]; then
    packages="$(package_for_idx "$idx")"
    pkg_install "$packages"
  else
    run_script_field "$idx" install
  fi

  if is_installed "$idx"; then
    ok "安装成功：$name"
  else
    err "安装后仍未检测到：$name"
    return 1
  fi
}

upgrade_idx() {
  local idx="$1"
  local name type packages upgrade
  name="$(field "$idx" name)"
  type="$(field "$idx" install_type)"
  upgrade="$(field "$idx" upgrade)"

  info "正在升级/重新安装：$name"
  if [[ -n "$upgrade" ]]; then
    bash -lc "$upgrade"
  elif [[ "$type" == "package" ]]; then
    packages="$(package_for_idx "$idx")"
    pkg_install "$packages"
  else
    run_script_field "$idx" install
  fi

  if is_installed "$idx"; then
    ok "处理完成：$name"
  else
    err "升级/重装后检测失败：$name"
    return 1
  fi
}

uninstall_idx() {
  local idx="$1"
  local name type packages uninstall
  name="$(field "$idx" name)"
  type="$(field "$idx" install_type)"
  uninstall="$(field "$idx" uninstall)"

  if ! is_installed "$idx"; then
    warn "$name 当前未安装"
    return 0
  fi

  warn "即将卸载：$name"
  read -r -p "确认卸载？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return 0

  if [[ -n "$uninstall" ]]; then
    bash -lc "$uninstall"
  elif [[ "$type" == "package" ]]; then
    packages="$(package_for_idx "$idx")"
    pkg_remove "$packages"
  else
    warn "该插件没有自动卸载规则，请手动处理"
    return 1
  fi

  if is_installed "$idx"; then
    warn "插件仍能被检测到，可能存在残留或由其他方式安装"
  else
    ok "已卸载：$name"
  fi
}

run_idx() {
  local idx="$1"
  local name run
  name="$(field "$idx" name)"
  run="$(field "$idx" run)"

  [[ -n "$run" ]] || {
    warn "$name 没有配置直接运行入口"
    return 0
  }

  is_installed "$idx" || {
    warn "请先安装 $name"
    return 0
  }

  echo
  info "启动：$name"
  bash -lc "$run" || true
}

plugin_detail() {
  local idx="$1"
  local id name tool category desc risk homepage type
  id="$(field "$idx" id)"
  name="$(field "$idx" name)"
  tool="$(field "$idx" tool)"
  category="$(field "$idx" category)"
  desc="$(field "$idx" desc)"
  risk="$(field "$idx" risk)"
  homepage="$(field "$idx" homepage)"
  type="$(field "$idx" install_type)"

  while true; do
    clear
    echo "============== 插件详情 =============="
    echo "名称：$name"
    echo "工具：$tool"
    echo "分类：$category"
    echo "状态：$(status_text "$idx")"
    echo "风险：${risk:-low}"
    echo "说明：$desc"
    [[ -n "$homepage" ]] && echo "项目：$homepage"
    echo "安装方式：$type"
    echo "--------------------------------------"
    echo "1) 安装"
    echo "2) 升级 / 重新安装"
    echo "3) 运行 / 查看版本"
    echo "4) 卸载"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) install_idx "$idx"; pause ;;
      2) upgrade_idx "$idx"; pause ;;
      3) run_idx "$idx"; pause ;;
      4) uninstall_idx "$idx"; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

browse_indices() {
  local title="$1"
  shift
  local indices=("$@")

  if [[ "${#indices[@]}" -eq 0 ]]; then
    warn "没有符合条件的插件"
    pause
    return
  fi

  while true; do
    clear
    echo "=========== $title ==========="
    local pos=1 idx name tool category state
    for idx in "${indices[@]}"; do
      name="$(field "$idx" name)"
      tool="$(field "$idx" tool)"
      category="$(field "$idx" category)"
      state="$(status_text "$idx")"
      printf "%2d) %-11s %-28s [%s / %s]\n" "$pos" "$state" "$name" "$category" "$tool"
      pos=$((pos+1))
    done
    echo "0) 返回"
    echo
    read -r -p "选择插件: " c || true
    [[ "$c" == "0" ]] && return
    [[ "$c" =~ ^[0-9]+$ ]] || { warn "请输入编号"; sleep 1; continue; }
    (( c >= 1 && c <= ${#indices[@]} )) || { warn "编号超出范围"; sleep 1; continue; }
    plugin_detail "${indices[$((c-1))]}"
  done
}

all_plugins() {
  local indices=()
  mapfile -t indices < <(jq -r 'to_entries[] | .key' "$CFG")
  browse_indices "全部插件" "${indices[@]}"
}

recommended_plugins() {
  local indices=()
  mapfile -t indices < <(jq -r 'to_entries[] | select(.value.recommended == true) | .key' "$CFG")
  browse_indices "推荐插件" "${indices[@]}"
}

installed_plugins() {
  local indices=()
  local idx
  while read -r idx; do
    is_installed "$idx" && indices+=("$idx")
  done < <(jq -r 'to_entries[] | .key' "$CFG")
  browse_indices "已安装插件" "${indices[@]}"
}

missing_plugins() {
  local indices=()
  local idx
  while read -r idx; do
    if ! is_installed "$idx"; then
      indices+=("$idx")
    fi
  done < <(jq -r 'to_entries[] | .key' "$CFG")
  browse_indices "未安装插件" "${indices[@]}"
}

category_browser() {
  local categories=()
  mapfile -t categories < <(jq -r '.[].category' "$CFG" | awk '!seen[$0]++')

  while true; do
    clear
    echo "=========== 按分类浏览 ==========="
    local i=1 cat count
    for cat in "${categories[@]}"; do
      count="$(jq -r --arg cat "$cat" '[.[] | select(.category == $cat)] | length' "$CFG")"
      printf "%2d) %-18s (%s)\n" "$i" "$cat" "$count"
      i=$((i+1))
    done
    echo "0) 返回"
    echo
    read -r -p "请选择分类: " c || true
    [[ "$c" == "0" ]] && return
    [[ "$c" =~ ^[0-9]+$ ]] || { warn "请输入编号"; sleep 1; continue; }
    (( c >= 1 && c <= ${#categories[@]} )) || { warn "编号超出范围"; sleep 1; continue; }

    cat="${categories[$((c-1))]}"
    local indices=()
    mapfile -t indices < <(jq -r --arg cat "$cat" 'to_entries[] | select(.value.category == $cat) | .key' "$CFG")
    browse_indices "$cat" "${indices[@]}"
  done
}

search_plugins() {
  read -r -p "输入用途或工具名（如：磁盘 / 网络 / Docker / tmux）: " q || true
  [[ -n "$q" ]] || return
  local indices=()
  mapfile -t indices < <(
    jq -r --arg q "$q" '
      ($q | ascii_downcase) as $needle |
      to_entries[] |
      select(
        ([.value.id, .value.name, .value.tool, .value.category, .value.desc] | join(" ") | ascii_downcase)
        | contains($needle)
      ) |
      .key
    ' "$CFG"
  )
  browse_indices "搜索：$q" "${indices[@]}"
}

install_recommended() {
  local indices=()
  local missing=()
  local idx name

  mapfile -t indices < <(jq -r 'to_entries[] | select(.value.recommended == true) | .key' "$CFG")
  for idx in "${indices[@]}"; do
    if ! is_installed "$idx"; then
      missing+=("$idx")
    fi
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    ok "推荐插件已经全部安装"
    pause
    return
  fi

  echo
  echo "准备安装以下推荐插件："
  for idx in "${missing[@]}"; do
    name="$(field "$idx" name)"
    echo "  - $name"
  done
  echo
  read -r -p "确认一键安装以上 ${#missing[@]} 个插件？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return

  local ok_count=0 fail_count=0
  for idx in "${missing[@]}"; do
    if install_idx "$idx"; then
      ok_count=$((ok_count+1))
    else
      fail_count=$((fail_count+1))
    fi
    echo
  done

  echo "完成：成功 $ok_count，失败 $fail_count"
  pause
}

show_summary() {
  local total installed=0 idx
  total="$(jq 'length' "$CFG")"
  while read -r idx; do
    is_installed "$idx" && installed=$((installed+1))
  done < <(jq -r 'to_entries[] | .key' "$CFG")
  echo "插件：$total 个 / 已安装：$installed / 未安装：$((total-installed))"
}

ensure_jq
validate_cfg

while true; do
  clear
  echo "============== 插件中心 =============="
  show_summary
  echo "--------------------------------------"
  echo "1) 推荐插件"
  echo "2) 按分类浏览"
  echo "3) 搜索插件"
  echo "4) 全部插件"
  echo "5) 已安装插件"
  echo "6) 未安装插件"
  echo "7) 一键安装推荐插件"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c || true

  case "$c" in
    1) recommended_plugins ;;
    2) category_browser ;;
    3) search_plugins ;;
    4) all_plugins ;;
    5) installed_plugins ;;
    6) missing_plugins ;;
    7) install_recommended ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
