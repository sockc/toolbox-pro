#!/usr/bin/env bash
set -euo pipefail

source /opt/server-toolbox/core/common.sh
need_root

LOG_DIR="/opt/server-toolbox/logs"
CMD_LOG="${LOG_DIR}/command-center.log"
mkdir -p "$LOG_DIR"
touch "$CMD_LOG"
chmod 600 "$CMD_LOG" 2>/dev/null || true

pause() {
  echo
  read -r -p "回车继续..." _ || true
}

rule() {
  echo "------------------------------------------------------------"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

q() {
  printf "%q" "$1"
}

show_cmd() {
  local cmd="$1"
  echo
  info "实际命令：$cmd"
  printf '%s | %s\n' "$(date '+%F %T')" "$cmd" >>"$CMD_LOG" 2>/dev/null || true
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

valid_pid() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 ))
}

need_tool() {
  local tool="$1"
  local hint="${2:-插件中心}"
  if have "$tool"; then
    return 0
  fi
  warn "缺少工具：$tool"
  echo "可返回主菜单 → 插件中心安装相关工具（$hint）"
  return 1
}

# ============================================================
# 端口 / 连接
# ============================================================

show_listening_ports() {
  if have ss; then
    show_cmd "ss -lntup"
    ss -lntup || true
  elif have netstat; then
    show_cmd "netstat -lntup"
    netstat -lntup || true
  else
    err "缺少 ss/netstat"
  fi
}

query_port() {
  local p
  read -r -p "输入端口（1-65535）: " p || true
  valid_port "$p" || { warn "端口格式错误"; return; }

  echo
  info "查询端口：$p"

  if have ss; then
    show_cmd "ss -lntup | grep ':$p'"
    ss -lntup 2>/dev/null | awk -v p=":$p" '$0 ~ p {print}' || true
  fi

  if have lsof; then
    echo
    show_cmd "lsof -nP -i :$p"
    lsof -nP -i :"$p" 2>/dev/null || true
  fi

  if have docker; then
    echo
    info "Docker 端口映射："
    show_cmd "docker ps --format ..."
    docker ps --format 'table {{.Names}}\t{{.Ports}}' 2>/dev/null | {
      read -r header || true
      echo "$header"
      grep -E "(^|[:.])$p->|0\.0\.0\.0:$p->|\[::\]:$p->" || true
    }
  fi
}

show_connections() {
  if have ss; then
    show_cmd "ss -tunap"
    ss -tunap | head -n 250 || true
  else
    warn "当前系统没有 ss"
  fi
}

connection_summary() {
  if have ss; then
    show_cmd "ss -s"
    ss -s || true
  else
    warn "当前系统没有 ss"
  fi
}

test_remote_port() {
  local host port
  read -r -p "目标域名/IP: " host || true
  read -r -p "目标端口: " port || true
  [[ -n "$host" ]] || { warn "目标不能为空"; return; }
  valid_port "$port" || { warn "端口格式错误"; return; }

  if have nc; then
    show_cmd "nc -vz -w 5 $(q "$host") $port"
    if nc -vz -w 5 "$host" "$port"; then
      ok "连接成功"
    else
      err "连接失败或超时"
    fi
  elif have timeout; then
    show_cmd "timeout 5 bash -c '</dev/tcp/$(q "$host")/$port'"
    if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
      ok "连接成功"
    else
      err "连接失败或超时"
    fi
  else
    warn "建议在插件中心安装 netcat"
  fi
}

port_menu() {
  while true; do
    clear
    echo "============== 端口 / 网络连接 =============="
    echo "1) 查看所有监听端口"
    echo "2) 查询指定端口被谁占用"
    echo "3) 查看当前 TCP/UDP 连接"
    echo "4) 查看连接统计"
    echo "5) 测试远程 IP/域名端口"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) show_listening_ports; pause ;;
      2) query_port; pause ;;
      3) show_connections; pause ;;
      4) connection_summary; pause ;;
      5) test_remote_port; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 进程
# ============================================================

top_cpu() {
  show_cmd "ps aux --sort=-%cpu | head -n 21"
  ps aux --sort=-%cpu | head -n 21
}

top_memory() {
  show_cmd "ps aux --sort=-%mem | head -n 21"
  ps aux --sort=-%mem | head -n 21
}

search_process() {
  local k
  read -r -p "输入进程名称/关键词: " k || true
  [[ -n "$k" ]] || return
  show_cmd "pgrep -a -f $(q "$k")"
  pgrep -a -f -- "$k" 2>/dev/null || warn "没有找到匹配进程"
}

pid_detail() {
  local p
  read -r -p "输入 PID: " p || true
  valid_pid "$p" || { warn "PID 格式错误"; return; }
  [[ -d "/proc/$p" ]] || { warn "PID $p 不存在"; return; }

  show_cmd "ps -p $p -o pid,ppid,user,%cpu,%mem,etime,lstart,cmd"
  ps -p "$p" -o pid,ppid,user,%cpu,%mem,etime,lstart,cmd || true

  echo
  info "可执行文件："
  readlink -f "/proc/$p/exe" 2>/dev/null || true

  echo
  info "工作目录："
  readlink -f "/proc/$p/cwd" 2>/dev/null || true

  echo
  info "打开文件数量："
  find "/proc/$p/fd" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l || true
}

terminate_process() {
  local p
  read -r -p "输入要结束的 PID: " p || true
  valid_pid "$p" || { warn "PID 格式错误"; return; }
  [[ -d "/proc/$p" ]] || { warn "PID $p 不存在"; return; }

  ps -p "$p" -o pid,user,%cpu,%mem,etime,cmd || true
  echo
  warn "优先发送 TERM，让程序正常退出。"
  read -r -p "确认结束 PID $p？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return

  show_cmd "kill -TERM $p"
  kill -TERM "$p" 2>/dev/null || { err "发送 TERM 失败"; return; }
  sleep 2

  if [[ -d "/proc/$p" ]]; then
    warn "进程仍存在。"
    read -r -p "是否强制 kill -9？(y/N): " yn2 || true
    if [[ "${yn2,,}" == "y" ]]; then
      show_cmd "kill -KILL $p"
      kill -KILL "$p" 2>/dev/null || err "强制结束失败"
    fi
  else
    ok "进程已结束"
  fi
}

process_tree() {
  if have pstree; then
    show_cmd "pstree -ap"
    pstree -ap | head -n 250 || true
  else
    show_cmd "ps -ef --forest"
    ps -ef --forest | head -n 250 || true
  fi
}

process_menu() {
  while true; do
    clear
    echo "================ 进程管理 ================"
    echo "1) CPU 占用最高的进程"
    echo "2) 内存占用最高的进程"
    echo "3) 搜索进程"
    echo "4) 查看 PID 详细信息"
    echo "5) 查看进程树"
    echo "6) 结束指定进程"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) top_cpu; pause ;;
      2) top_memory; pause ;;
      3) search_process; pause ;;
      4) pid_detail; pause ;;
      5) process_tree; pause ;;
      6) terminate_process; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# systemd 服务
# ============================================================

service_name_input() {
  local prompt="$1"
  local svc
  read -r -p "$prompt" svc || true
  svc="${svc%.service}"
  [[ "$svc" =~ ^[A-Za-z0-9_.@:-]+$ ]] || return 1
  printf "%s" "$svc"
}

service_status() {
  local svc
  svc="$(service_name_input "输入服务名（如 docker / ssh / fail2ban）: ")" || { warn "服务名格式错误"; return; }
  show_cmd "systemctl status $(q "$svc") --no-pager"
  systemctl status "$svc" --no-pager || true
}

list_running_services() {
  show_cmd "systemctl list-units --type=service --state=running"
  systemctl list-units --type=service --state=running --no-pager | head -n 250 || true
}

list_failed_services() {
  show_cmd "systemctl --failed --type=service"
  systemctl --failed --type=service --no-pager || true
}

service_action() {
  local action="$1"
  local svc
  svc="$(service_name_input "输入服务名: ")" || { warn "服务名格式错误"; return; }

  echo
  systemctl status "$svc" --no-pager -n 5 2>/dev/null || true
  echo
  read -r -p "确认执行 systemctl $action $svc？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return

  show_cmd "systemctl $action $(q "$svc")"
  if systemctl "$action" "$svc"; then
    ok "操作成功"
  else
    err "操作失败"
  fi
}

service_logs() {
  local svc lines
  svc="$(service_name_input "输入服务名: ")" || { warn "服务名格式错误"; return; }
  read -r -p "显示多少行 [默认 100]: " lines || true
  lines="${lines:-100}"
  [[ "$lines" =~ ^[0-9]+$ ]] || lines=100
  (( lines > 1000 )) && lines=1000
  show_cmd "journalctl -u $(q "$svc") -n $lines --no-pager"
  journalctl -u "$svc" -n "$lines" --no-pager || true
}

service_menu() {
  while true; do
    clear
    echo "================ 服务管理 ================"
    echo "1) 查看运行中的服务"
    echo "2) 查看启动失败的服务"
    echo "3) 查看指定服务状态"
    echo "4) 启动服务"
    echo "5) 停止服务"
    echo "6) 重启服务"
    echo "7) 设置开机自启"
    echo "8) 取消开机自启"
    echo "9) 查看服务日志"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) list_running_services; pause ;;
      2) list_failed_services; pause ;;
      3) service_status; pause ;;
      4) service_action start; pause ;;
      5) service_action stop; pause ;;
      6) service_action restart; pause ;;
      7) service_action enable; pause ;;
      8) service_action disable; pause ;;
      9) service_logs; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# DNS / 域名 / TLS
# ============================================================

domain_input() {
  local d
  read -r -p "输入域名（例如 example.com）: " d || true
  d="${d#http://}"
  d="${d#https://}"
  d="${d%%/*}"
  d="${d%%:*}"
  [[ "$d" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]] || return 1
  printf "%s" "$d"
}

dns_query() {
  local type="$1"
  local d
  d="$(domain_input)" || { warn "域名格式错误"; return; }

  if have dig; then
    show_cmd "dig +short $type $(q "$d")"
    dig +short "$type" "$d" || true
  elif have getent && [[ "$type" == "A" || "$type" == "AAAA" ]]; then
    show_cmd "getent ahosts $(q "$d")"
    getent ahosts "$d" || true
  else
    warn "建议在插件中心安装 DNS 查询工具（dig）"
  fi
}

dns_full() {
  local d
  d="$(domain_input)" || { warn "域名格式错误"; return; }
  if need_tool dig "DNS 查询工具"; then
    show_cmd "dig $(q "$d")"
    dig "$d" || true
  fi
}

tls_check() {
  local d port
  d="$(domain_input)" || { warn "域名格式错误"; return; }
  read -r -p "TLS 端口 [默认 443]: " port || true
  port="${port:-443}"
  valid_port "$port" || { warn "端口格式错误"; return; }

  need_tool openssl "OpenSSL" || return

  show_cmd "openssl s_client -connect $(q "$d"):$port -servername $(q "$d") ... | openssl x509 ..."
  local cert
  cert="$(timeout 10 openssl s_client -connect "$d:$port" -servername "$d" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates -serial -fingerprint -sha256 2>/dev/null || true)"
  if [[ -n "$cert" ]]; then
    echo "$cert"
  else
    err "未取得证书，可能端口不可达或 TLS 握手失败"
  fi
}

http_check() {
  local url
  read -r -p "输入网址（例如 https://example.com）: " url || true
  [[ "$url" =~ ^https?://[^[:space:]]+$ ]] || { warn "URL 格式错误，需要 http:// 或 https://"; return; }

  need_tool curl "curl" || return
  show_cmd "curl -IL --max-time 15 $(q "$url")"
  curl -IL --max-time 15 "$url" || true
}

dns_menu() {
  while true; do
    clear
    echo "============= 域名 / DNS / HTTPS ============="
    echo "1) 查询 IPv4（A）"
    echo "2) 查询 IPv6（AAAA）"
    echo "3) 查询 MX 邮件记录"
    echo "4) 查询 TXT 记录"
    echo "5) 查询 NS 记录"
    echo "6) 查看完整 DNS 响应"
    echo "7) 检查 HTTPS/TLS 证书"
    echo "8) 检查网站响应和跳转"
    echo "9) 对比公共 DNS 解析"
    echo "10) 计算证书剩余天数"
    echo "11) 网站连接耗时分析"
    echo "12) 检查域名 80/443 连通"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) dns_query A; pause ;;
      2) dns_query AAAA; pause ;;
      3) dns_query MX; pause ;;
      4) dns_query TXT; pause ;;
      5) dns_query NS; pause ;;
      6) dns_full; pause ;;
      7) tls_check; pause ;;
      8) http_check; pause ;;
      9) dns_compare_public; pause ;;
      10) certificate_days_left; pause ;;
      11) http_timing; pause ;;
      12) check_web_ports; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 文件 / 磁盘
# ============================================================

disk_usage() {
  show_cmd "df -hT"
  df -hT || true
}

inode_usage() {
  show_cmd "df -ih"
  df -ih || true
}

directory_size() {
  local path
  read -r -p "输入目录 [默认 /opt]: " path || true
  path="${path:-/opt}"
  [[ -d "$path" ]] || { warn "目录不存在"; return; }
  show_cmd "du -sh $(q "$path")"
  du -sh -- "$path" 2>/dev/null || true
  echo
  info "一级子目录："
  du -xhd1 -- "$path" 2>/dev/null | sort -h | tail -n 30 || true
}

largest_files() {
  local path count
  read -r -p "搜索目录 [默认 /]: " path || true
  path="${path:-/}"
  [[ -d "$path" ]] || { warn "目录不存在"; return; }
  read -r -p "显示前多少个 [默认 20]: " count || true
  count="${count:-20}"
  [[ "$count" =~ ^[0-9]+$ ]] || count=20
  (( count > 100 )) && count=100

  show_cmd "find $(q "$path") -xdev -type f -printf '%s %p\\n' | sort -nr | head -n $count"
  find "$path" -xdev -type f -printf '%s %p\n' 2>/dev/null |
    sort -nr |
    head -n "$count" |
    numfmt --field=1 --to=iec-i --suffix=B 2>/dev/null || true
}

find_file_name() {
  local path pattern
  read -r -p "搜索目录 [默认 /]: " path || true
  path="${path:-/}"
  [[ -d "$path" ]] || { warn "目录不存在"; return; }
  read -r -p "文件名关键词（例如 nginx.conf 或 *.log）: " pattern || true
  [[ -n "$pattern" ]] || return

  show_cmd "find $(q "$path") -iname $(q "*$pattern*")"
  find "$path" -iname "*$pattern*" 2>/dev/null | head -n 200 || true
}

search_file_content() {
  local path keyword
  read -r -p "搜索目录 [默认 /etc]: " path || true
  path="${path:-/etc}"
  [[ -d "$path" ]] || { warn "目录不存在"; return; }
  read -r -p "要查找的文字: " keyword || true
  [[ -n "$keyword" ]] || return

  if have rg; then
    show_cmd "rg -n -i --hidden --glob '!*.log' $(q "$keyword") $(q "$path")"
    rg -n -i --hidden --glob '!*.log' -- "$keyword" "$path" 2>/dev/null | head -n 250 || true
  else
    show_cmd "grep -Rni -- $(q "$keyword") $(q "$path")"
    grep -Rni --binary-files=without-match -- "$keyword" "$path" 2>/dev/null | head -n 250 || true
  fi
}

recent_files() {
  local path days
  read -r -p "目录 [默认 /etc]: " path || true
  path="${path:-/etc}"
  [[ -d "$path" ]] || { warn "目录不存在"; return; }
  read -r -p "最近多少天 [默认 1]: " days || true
  days="${days:-1}"
  [[ "$days" =~ ^[0-9]+$ ]] || days=1
  show_cmd "find $(q "$path") -type f -mtime -$days -printf ..."
  find "$path" -type f -mtime "-$days" -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null |
    sort -r | head -n 200 || true
}

disk_menu() {
  while true; do
    clear
    echo "=============== 文件 / 磁盘 ==============="
    echo "1) 查看磁盘容量"
    echo "2) 查看 inode 使用率"
    echo "3) 查看目录占用"
    echo "4) 查找最大的文件"
    echo "5) 按名字找文件"
    echo "6) 在文件中搜索文字"
    echo "7) 查看最近修改的文件"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) disk_usage; pause ;;
      2) inode_usage; pause ;;
      3) directory_size; pause ;;
      4) largest_files; pause ;;
      5) find_file_name; pause ;;
      6) search_file_content; pause ;;
      7) recent_files; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 网络诊断
# ============================================================

show_ips() {
  echo "公网 IPv4："
  show_cmd "curl -4 -fsSL --max-time 5 https://api.ipify.org"
  curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || echo "不可用"
  echo
  echo
  echo "公网 IPv6："
  show_cmd "curl -6 -fsSL --max-time 5 https://api64.ipify.org"
  curl -6 -fsSL --max-time 5 https://api64.ipify.org 2>/dev/null || echo "不可用"
  echo
}

show_interfaces() {
  show_cmd "ip -br address"
  ip -br address || true
}

show_routes() {
  show_cmd "ip route; ip -6 route"
  echo "IPv4："
  ip route || true
  echo
  echo "IPv6："
  ip -6 route || true
}

ping_host() {
  local host
  read -r -p "目标域名/IP: " host || true
  [[ -n "$host" && "$host" != *" "* ]] || { warn "目标格式错误"; return; }
  show_cmd "ping -c 4 $(q "$host")"
  ping -c 4 "$host" || true
}

route_trace() {
  local host
  read -r -p "目标域名/IP: " host || true
  [[ -n "$host" && "$host" != *" "* ]] || { warn "目标格式错误"; return; }

  if have mtr; then
    show_cmd "mtr -rwzc 10 $(q "$host")"
    mtr -rwzc 10 "$host" || true
  elif have traceroute; then
    show_cmd "traceroute $(q "$host")"
    traceroute "$host" || true
  else
    warn "插件中心安装 mtr 或 traceroute 后可使用"
  fi
}

network_dns_test() {
  show_cmd "getent ahosts github.com; getent ahosts google.com"
  getent ahosts github.com 2>/dev/null | head -n 10 || true
  echo
  getent ahosts google.com 2>/dev/null | head -n 10 || true
}

network_menu() {
  while true; do
    clear
    echo "=============== 网络诊断 ==============="
    echo "1) 查看公网 IPv4 / IPv6"
    echo "2) 查看本机网卡/IP"
    echo "3) 查看 IPv4 / IPv6 路由"
    echo "4) Ping 测试"
    echo "5) 路由/丢包诊断（优先 MTR）"
    echo "6) DNS 基础解析测试"
    echo "7) 测试远程端口"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) show_ips; pause ;;
      2) show_interfaces; pause ;;
      3) show_routes; pause ;;
      4) ping_host; pause ;;
      5) route_trace; pause ;;
      6) network_dns_test; pause ;;
      7) test_remote_port; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 日志
# ============================================================

system_errors() {
  show_cmd "journalctl -p 0..3 -n 200 --no-pager"
  journalctl -p 0..3 -n 200 --no-pager || true
}

boot_logs() {
  show_cmd "journalctl -b -n 250 --no-pager"
  journalctl -b -n 250 --no-pager || true
}

kernel_logs() {
  show_cmd "journalctl -k -n 250 --no-pager"
  journalctl -k -n 250 --no-pager || true
}

ssh_logs() {
  if journalctl -u ssh -n 1 --no-pager >/dev/null 2>&1; then
    show_cmd "journalctl -u ssh -n 200 --no-pager"
    journalctl -u ssh -n 200 --no-pager || true
  else
    show_cmd "journalctl -u sshd -n 200 --no-pager"
    journalctl -u sshd -n 200 --no-pager || true
  fi
}

docker_logs() {
  need_tool docker "Docker" || return
  local name
  echo "当前容器："
  docker ps --format 'table {{.Names}}\t{{.Status}}' || true
  echo
  read -r -p "输入容器名: " name || true
  [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || { warn "容器名格式错误"; return; }
  docker inspect "$name" >/dev/null 2>&1 || { warn "容器不存在"; return; }
  show_cmd "docker logs --tail 200 $(q "$name")"
  docker logs --tail 200 "$name" 2>&1 || true
}

command_history() {
  echo "最近执行的命令（最多 100 条）："
  rule
  tail -n 100 "$CMD_LOG" 2>/dev/null || true
}

log_menu() {
  while true; do
    clear
    echo "================ 日志中心 ================"
    echo "1) 最近系统错误"
    echo "2) 本次启动日志"
    echo "3) 内核日志"
    echo "4) SSH 日志"
    echo "5) 指定 systemd 服务日志"
    echo "6) Docker 容器日志"
    echo "7) Toolbox 命令历史"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) system_errors; pause ;;
      2) boot_logs; pause ;;
      3) kernel_logs; pause ;;
      4) ssh_logs; pause ;;
      5) service_logs; pause ;;
      6) docker_logs; pause ;;
      7) command_history; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 系统 / 用户
# ============================================================

system_overview() {
  show_cmd "uname -a; uptime; free -h; df -h /"
  echo "系统："
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "${PRETTY_NAME:-unknown}"
  fi
  echo "内核：$(uname -r)"
  echo "架构：$(uname -m)"
  echo "主机名：$(hostname)"
  echo
  uptime || true
  echo
  free -h || true
  echo
  df -h / || true
}

logged_users() {
  show_cmd "w"
  w || true
}

login_history() {
  show_cmd "last -a | head -n 50"
  last -a | head -n 50 || true
}

failed_logins() {
  if have lastb; then
    show_cmd "lastb -a | head -n 50"
    lastb -a | head -n 50 || true
  else
    warn "当前系统没有 lastb"
  fi
}

sudo_users() {
  show_cmd "getent group sudo; getent group wheel"
  getent group sudo 2>/dev/null || true
  getent group wheel 2>/dev/null || true
}

users_with_shell() {
  show_cmd "getent passwd | awk ... login shells"
  getent passwd | awk -F: '$7 !~ /(nologin|false)$/ {printf "%-20s uid=%-8s shell=%s\n",$1,$3,$7}' || true
}

system_user_menu() {
  while true; do
    clear
    echo "=============== 系统 / 用户 ==============="
    echo "1) 系统概览"
    echo "2) 当前登录用户"
    echo "3) 最近登录记录"
    echo "4) 登录失败记录"
    echo "5) sudo / wheel 用户"
    echo "6) 可登录系统的用户"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) system_overview; pause ;;
      2) logged_users; pause ;;
      3) login_history; pause ;;
      4) failed_logins; pause ;;
      5) sudo_users; pause ;;
      6) users_with_shell; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 软件包管理
# ============================================================

detect_package_manager() {
  if have apt-get; then echo apt
  elif have dnf; then echo dnf
  elif have yum; then echo yum
  elif have apk; then echo apk
  else echo unknown
  fi
}

valid_package_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.+:_-]*$ ]]
}

package_manager_info() {
  local pm
  pm="$(detect_package_manager)"
  echo "当前软件包管理器：$pm"
  case "$pm" in
    apt) show_cmd "apt-get --version | head -n1"; apt-get --version | head -n1 ;;
    dnf) show_cmd "dnf --version"; dnf --version | head -n2 ;;
    yum) show_cmd "yum --version"; yum --version | head -n2 ;;
    apk) show_cmd "apk --version"; apk --version ;;
    *) warn "未识别到支持的软件包管理器" ;;
  esac
}

package_refresh() {
  local pm
  pm="$(detect_package_manager)"
  read -r -p "确认刷新软件源索引？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return
  case "$pm" in
    apt) show_cmd "apt-get update"; apt-get update ;;
    dnf) show_cmd "dnf makecache"; dnf makecache ;;
    yum) show_cmd "yum makecache"; yum makecache ;;
    apk) show_cmd "apk update"; apk update ;;
    *) err "不支持当前软件包管理器" ;;
  esac
}

package_upgradable() {
  local pm
  pm="$(detect_package_manager)"
  case "$pm" in
    apt)
      show_cmd "apt list --upgradable"
      apt list --upgradable 2>/dev/null || true
      ;;
    dnf)
      show_cmd "dnf check-update"
      dnf check-update || true
      ;;
    yum)
      show_cmd "yum check-update"
      yum check-update || true
      ;;
    apk)
      show_cmd "apk version -l '<'"
      apk version -l '<' || true
      ;;
    *) err "不支持当前软件包管理器" ;;
  esac
}

package_search() {
  local term pm
  read -r -p "输入软件名称/关键词: " term || true
  [[ -n "$term" ]] || return
  pm="$(detect_package_manager)"
  case "$pm" in
    apt) show_cmd "apt-cache search $(q "$term")"; apt-cache search "$term" | head -n 100 || true ;;
    dnf) show_cmd "dnf search $(q "$term")"; dnf search "$term" | head -n 100 || true ;;
    yum) show_cmd "yum search $(q "$term")"; yum search "$term" | head -n 100 || true ;;
    apk) show_cmd "apk search -v $(q "*$term*")"; apk search -v "*$term*" | head -n 100 || true ;;
    *) err "不支持当前软件包管理器" ;;
  esac
}

package_install() {
  local pkg pm
  read -r -p "输入要安装的软件包名称: " pkg || true
  valid_package_name "$pkg" || { warn "软件包名称格式错误"; return; }
  pm="$(detect_package_manager)"
  read -r -p "确认安装 $pkg？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return

  case "$pm" in
    apt) show_cmd "apt-get install -y $(q "$pkg")"; apt-get install -y "$pkg" ;;
    dnf) show_cmd "dnf install -y $(q "$pkg")"; dnf install -y "$pkg" ;;
    yum) show_cmd "yum install -y $(q "$pkg")"; yum install -y "$pkg" ;;
    apk) show_cmd "apk add $(q "$pkg")"; apk add "$pkg" ;;
    *) err "不支持当前软件包管理器" ;;
  esac
}

package_remove() {
  local pkg pm
  read -r -p "输入要卸载的软件包名称: " pkg || true
  valid_package_name "$pkg" || { warn "软件包名称格式错误"; return; }
  pm="$(detect_package_manager)"
  warn "卸载软件可能同时移除依赖。"
  read -r -p "确认卸载 $pkg？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return

  case "$pm" in
    apt) show_cmd "apt-get remove $(q "$pkg")"; apt-get remove "$pkg" ;;
    dnf) show_cmd "dnf remove $(q "$pkg")"; dnf remove "$pkg" ;;
    yum) show_cmd "yum remove $(q "$pkg")"; yum remove "$pkg" ;;
    apk) show_cmd "apk del $(q "$pkg")"; apk del "$pkg" ;;
    *) err "不支持当前软件包管理器" ;;
  esac
}

package_menu() {
  while true; do
    clear
    echo "=============== 软件包管理 ==============="
    echo "1) 查看软件包管理器"
    echo "2) 刷新软件源索引"
    echo "3) 查看可升级软件"
    echo "4) 搜索软件"
    echo "5) 安装软件"
    echo "6) 卸载软件"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) package_manager_info; pause ;;
      2) package_refresh; pause ;;
      3) package_upgradable; pause ;;
      4) package_search; pause ;;
      5) package_install; pause ;;
      6) package_remove; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 用户 / 权限
# ============================================================

valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

user_exists() {
  getent passwd "$1" >/dev/null 2>&1
}

list_human_users() {
  show_cmd "getent passwd | awk -F: '\$3 >= 1000 ...'"
  getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {printf "%-20s uid=%-7s home=%-30s shell=%s\n",$1,$3,$6,$7}' || true
}

create_user_cmd() {
  local u
  read -r -p "新用户名: " u || true
  valid_username "$u" || { warn "用户名格式错误"; return; }
  user_exists "$u" && { warn "用户已存在"; return; }
  read -r -p "创建用户 $u 并创建 home 目录？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return

  if have useradd; then
    show_cmd "useradd -m -s /bin/bash $(q "$u")"
    useradd -m -s /bin/bash "$u"
  elif have adduser; then
    show_cmd "adduser $(q "$u")"
    adduser "$u"
  else
    err "系统没有 useradd/adduser"
    return
  fi
  ok "用户已创建。下面设置密码。"
  passwd "$u"
}

change_user_password() {
  local u
  read -r -p "用户名: " u || true
  valid_username "$u" || { warn "用户名格式错误"; return; }
  user_exists "$u" || { warn "用户不存在"; return; }
  show_cmd "passwd $(q "$u")"
  passwd "$u"
}

sudo_group_name() {
  if getent group sudo >/dev/null 2>&1; then echo sudo
  elif getent group wheel >/dev/null 2>&1; then echo wheel
  else echo ""
  fi
}

grant_sudo() {
  local u grp
  read -r -p "用户名: " u || true
  valid_username "$u" || { warn "用户名格式错误"; return; }
  user_exists "$u" || { warn "用户不存在"; return; }
  grp="$(sudo_group_name)"
  [[ -n "$grp" ]] || { err "没有检测到 sudo/wheel 组"; return; }
  read -r -p "确认把 $u 加入 $grp？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return
  show_cmd "usermod -aG $grp $(q "$u")"
  usermod -aG "$grp" "$u"
  ok "已加入 $grp"
}

revoke_sudo() {
  local u grp
  read -r -p "用户名: " u || true
  valid_username "$u" || { warn "用户名格式错误"; return; }
  user_exists "$u" || { warn "用户不存在"; return; }
  grp="$(sudo_group_name)"
  [[ -n "$grp" ]] || { err "没有检测到 sudo/wheel 组"; return; }
  [[ "$u" != "root" ]] || { warn "不能这样处理 root"; return; }
  read -r -p "确认把 $u 从 $grp 移除？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return

  if have gpasswd; then
    show_cmd "gpasswd -d $(q "$u") $grp"
    gpasswd -d "$u" "$grp"
  elif have deluser; then
    show_cmd "deluser $(q "$u") $grp"
    deluser "$u" "$grp"
  else
    err "系统没有 gpasswd/deluser"
  fi
}

lock_user() {
  local u
  read -r -p "要锁定的用户名: " u || true
  valid_username "$u" || { warn "用户名格式错误"; return; }
  user_exists "$u" || { warn "用户不存在"; return; }
  [[ "$u" != "root" ]] || { warn "禁止锁定 root"; return; }
  read -r -p "确认锁定 $u 的密码登录？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return
  show_cmd "passwd -l $(q "$u")"
  passwd -l "$u"
}

unlock_user() {
  local u
  read -r -p "要解锁的用户名: " u || true
  valid_username "$u" || { warn "用户名格式错误"; return; }
  user_exists "$u" || { warn "用户不存在"; return; }
  show_cmd "passwd -u $(q "$u")"
  passwd -u "$u"
}

delete_user_cmd() {
  local u
  read -r -p "要删除的用户名: " u || true
  valid_username "$u" || { warn "用户名格式错误"; return; }
  user_exists "$u" || { warn "用户不存在"; return; }
  [[ "$u" != "root" ]] || { warn "禁止删除 root"; return; }
  warn "这是高风险操作。"
  read -r -p "是否同时删除 home 目录？(y/N): " homeyn || true
  read -r -p "请输入用户名 $u 再次确认删除: " confirm || true
  [[ "$confirm" == "$u" ]] || { warn "确认不匹配，已取消"; return; }

  if [[ "${homeyn,,}" == "y" ]]; then
    if have userdel; then
      show_cmd "userdel -r $(q "$u")"
      userdel -r "$u"
    else
      show_cmd "deluser --remove-home $(q "$u")"
      deluser --remove-home "$u"
    fi
  else
    if have userdel; then
      show_cmd "userdel $(q "$u")"
      userdel "$u"
    else
      show_cmd "deluser $(q "$u")"
      deluser "$u"
    fi
  fi
}

file_permission_info() {
  local path
  read -r -p "文件/目录路径: " path || true
  [[ -e "$path" ]] || { warn "路径不存在"; return; }
  show_cmd "stat $(q "$path")"
  stat "$path" || true
  echo
  show_cmd "ls -ld $(q "$path")"
  ls -ld -- "$path" || true
}

change_file_mode() {
  local path mode
  read -r -p "文件/目录路径: " path || true
  [[ -e "$path" ]] || { warn "路径不存在"; return; }
  read -r -p "权限数字（例如 600 / 644 / 755）: " mode || true
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || { warn "权限格式错误"; return; }
  ls -ld -- "$path" || true
  read -r -p "确认 chmod $mode？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return
  show_cmd "chmod $mode $(q "$path")"
  chmod "$mode" -- "$path"
  ls -ld -- "$path" || true
}

change_file_owner() {
  local path owner
  read -r -p "文件/目录路径: " path || true
  [[ -e "$path" ]] || { warn "路径不存在"; return; }
  read -r -p "新属主（user 或 user:group）: " owner || true
  [[ "$owner" =~ ^[A-Za-z0-9_.-]+(:[A-Za-z0-9_.-]+)?$ ]] || { warn "属主格式错误"; return; }
  ls -ld -- "$path" || true
  read -r -p "确认 chown $owner？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return
  show_cmd "chown $(q "$owner") $(q "$path")"
  chown "$owner" -- "$path"
  ls -ld -- "$path" || true
}

user_permission_menu() {
  while true; do
    clear
    echo "=============== 用户 / 权限 ==============="
    echo "1) 查看普通用户"
    echo "2) 新建用户"
    echo "3) 修改用户密码"
    echo "4) 授予 sudo 权限"
    echo "5) 移除 sudo 权限"
    echo "6) 锁定用户登录"
    echo "7) 解锁用户登录"
    echo "8) 删除用户"
    echo "9) 查看文件/目录权限"
    echo "10) 修改 chmod 权限"
    echo "11) 修改文件属主"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) list_human_users; pause ;;
      2) create_user_cmd; pause ;;
      3) change_user_password; pause ;;
      4) grant_sudo; pause ;;
      5) revoke_sudo; pause ;;
      6) lock_user; pause ;;
      7) unlock_user; pause ;;
      8) delete_user_cmd; pause ;;
      9) file_permission_info; pause ;;
      10) change_file_mode; pause ;;
      11) change_file_owner; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# Cron / 定时任务
# ============================================================

show_root_cron() {
  show_cmd "crontab -l"
  crontab -l 2>/dev/null || echo "当前 root 没有 crontab"
}

show_system_timers() {
  if have systemctl; then
    show_cmd "systemctl list-timers --all"
    systemctl list-timers --all --no-pager | head -n 200 || true
  else
    warn "当前系统没有 systemd"
  fi
}

valid_hour() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 0 && $1 <= 23 ))
}

valid_minute() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 0 && $1 <= 59 ))
}

append_cron_line() {
  local schedule="$1"
  local cmd="$2"
  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null >"$tmp" || true
  printf '%s %s\n' "$schedule" "$cmd" >>"$tmp"
  show_cmd "(crontab -l; echo '$schedule <command>') | crontab -"
  crontab "$tmp"
  rm -f "$tmp"
  ok "定时任务已添加"
}

add_cron_preset() {
  local mode schedule="" cmd hour minute n weekday
  echo "选择频率："
  echo "1) 每天固定时间"
  echo "2) 每小时固定分钟"
  echo "3) 每 N 分钟"
  echo "4) 每周固定一天/时间"
  echo "5) 开机时执行"
  echo "0) 取消"
  read -r -p "请选择: " mode || true

  case "$mode" in
    1)
      read -r -p "小时 0-23: " hour || true
      read -r -p "分钟 0-59: " minute || true
      valid_hour "$hour" && valid_minute "$minute" || { warn "时间格式错误"; return; }
      schedule="$minute $hour * * *"
      ;;
    2)
      read -r -p "每小时的第几分钟 0-59: " minute || true
      valid_minute "$minute" || { warn "分钟格式错误"; return; }
      schedule="$minute * * * *"
      ;;
    3)
      read -r -p "每多少分钟（1-59）: " n || true
      [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= 59 )) || { warn "范围错误"; return; }
      schedule="*/$n * * * *"
      ;;
    4)
      read -r -p "星期几（0=周日, 1=周一 ... 6=周六）: " weekday || true
      [[ "$weekday" =~ ^[0-6]$ ]] || { warn "星期格式错误"; return; }
      read -r -p "小时 0-23: " hour || true
      read -r -p "分钟 0-59: " minute || true
      valid_hour "$hour" && valid_minute "$minute" || { warn "时间格式错误"; return; }
      schedule="$minute $hour * * $weekday"
      ;;
    5)
      schedule="@reboot"
      ;;
    0) return ;;
    *) warn "无效选项"; return ;;
  esac

  echo
  echo "请输入要执行的命令。"
  echo "示例：/opt/scripts/backup.sh"
  read -r -p "命令: " cmd || true
  [[ -n "$cmd" ]] || { warn "命令不能为空"; return; }

  echo
  echo "将添加："
  echo "$schedule $cmd"
  read -r -p "确认添加？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return
  append_cron_line "$schedule" "$cmd"
}

remove_cron_line() {
  local lines choice tmp
  mapfile -t lines < <(crontab -l 2>/dev/null || true)
  if [[ "${#lines[@]}" -eq 0 ]]; then
    warn "当前没有 crontab"
    return
  fi

  local i=1
  for line in "${lines[@]}"; do
    printf "%2d) %s\n" "$i" "$line"
    i=$((i+1))
  done
  read -r -p "输入要删除的行号: " choice || true
  [[ "$choice" =~ ^[0-9]+$ ]] || { warn "请输入数字"; return; }
  (( choice >= 1 && choice <= ${#lines[@]} )) || { warn "超出范围"; return; }

  echo "即将删除：${lines[$((choice-1))]}"
  read -r -p "确认删除？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return

  tmp="$(mktemp)"
  i=1
  for line in "${lines[@]}"; do
    if (( i != choice )); then
      printf '%s\n' "$line" >>"$tmp"
    fi
    i=$((i+1))
  done
  show_cmd "crontab <删除指定行后的临时文件>"
  crontab "$tmp"
  rm -f "$tmp"
  ok "已删除"
}

cron_menu() {
  while true; do
    clear
    echo "=============== 定时任务 ==============="
    echo "1) 查看 root Cron"
    echo "2) 按人话模板新增 Cron"
    echo "3) 按编号删除 Cron"
    echo "4) 查看 systemd timers"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) show_root_cron; pause ;;
      2) add_cron_preset; pause ;;
      3) remove_cron_line; pause ;;
      4) show_system_timers; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 压缩 / 解压
# ============================================================

archive_create() {
  local src out format parent base
  read -r -p "要压缩的文件/目录路径: " src || true
  [[ -e "$src" ]] || { warn "路径不存在"; return; }

  echo "格式：1) tar.gz  2) tar.zst  3) zip"
  read -r -p "请选择 [默认 1]: " format || true
  format="${format:-1}"

  parent="$(dirname "$src")"
  base="$(basename "$src")"

  case "$format" in
    1)
      read -r -p "输出文件 [默认 /root/$base.tar.gz]: " out || true
      out="${out:-/root/$base.tar.gz}"
      show_cmd "tar -C $(q "$parent") -czf $(q "$out") $(q "$base")"
      tar -C "$parent" -czf "$out" "$base"
      ;;
    2)
      need_tool zstd "zstd" || return
      read -r -p "输出文件 [默认 /root/$base.tar.zst]: " out || true
      out="${out:-/root/$base.tar.zst}"
      show_cmd "tar -C $(q "$parent") -cf - $(q "$base") | zstd -T0 -o $(q "$out")"
      tar -C "$parent" -cf - "$base" | zstd -T0 -o "$out"
      ;;
    3)
      need_tool zip "zip" || { warn "可先通过软件包管理安装 zip"; return; }
      read -r -p "输出文件 [默认 /root/$base.zip]: " out || true
      out="${out:-/root/$base.zip}"
      show_cmd "cd $(q "$parent") && zip -r $(q "$out") $(q "$base")"
      (cd "$parent" && zip -r "$out" "$base")
      ;;
    *) warn "无效格式"; return ;;
  esac

  [[ -f "$out" ]] && { ok "压缩完成"; ls -lh "$out"; }
}

archive_extract() {
  local file dest
  read -r -p "压缩包路径: " file || true
  [[ -f "$file" ]] || { warn "文件不存在"; return; }
  read -r -p "解压到目录 [默认当前目录]: " dest || true
  dest="${dest:-.}"
  mkdir -p "$dest"

  case "$file" in
    *.tar.gz|*.tgz)
      show_cmd "tar -xzf $(q "$file") -C $(q "$dest")"
      tar -xzf "$file" -C "$dest"
      ;;
    *.tar.zst|*.tzst)
      need_tool zstd "zstd" || return
      show_cmd "tar --use-compress-program=unzstd -xf $(q "$file") -C $(q "$dest")"
      tar --use-compress-program=unzstd -xf "$file" -C "$dest"
      ;;
    *.tar.xz)
      show_cmd "tar -xJf $(q "$file") -C $(q "$dest")"
      tar -xJf "$file" -C "$dest"
      ;;
    *.tar)
      show_cmd "tar -xf $(q "$file") -C $(q "$dest")"
      tar -xf "$file" -C "$dest"
      ;;
    *.zip)
      need_tool unzip "unzip" || return
      show_cmd "unzip $(q "$file") -d $(q "$dest")"
      unzip "$file" -d "$dest"
      ;;
    *) warn "暂不识别该压缩格式" ;;
  esac
}

archive_list() {
  local file
  read -r -p "压缩包路径: " file || true
  [[ -f "$file" ]] || { warn "文件不存在"; return; }
  case "$file" in
    *.tar.gz|*.tgz) show_cmd "tar -tzf $(q "$file")"; tar -tzf "$file" | head -n 200 ;;
    *.tar.zst|*.tzst) show_cmd "tar --use-compress-program=unzstd -tf $(q "$file")"; tar --use-compress-program=unzstd -tf "$file" | head -n 200 ;;
    *.tar.xz) show_cmd "tar -tJf $(q "$file")"; tar -tJf "$file" | head -n 200 ;;
    *.tar) show_cmd "tar -tf $(q "$file")"; tar -tf "$file" | head -n 200 ;;
    *.zip) need_tool unzip "unzip" || return; show_cmd "unzip -l $(q "$file")"; unzip -l "$file" | head -n 220 ;;
    *) warn "暂不识别该压缩格式" ;;
  esac
}

archive_menu() {
  while true; do
    clear
    echo "=============== 压缩 / 解压 ==============="
    echo "1) 创建压缩包"
    echo "2) 解压文件"
    echo "3) 查看压缩包内容"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) archive_create; pause ;;
      2) archive_extract; pause ;;
      3) archive_list; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# Git 常用操作
# ============================================================

git_repo_path() {
  local path
  read -r -p "Git 项目目录 [默认当前目录]: " path || true
  path="${path:-.}"
  [[ -d "$path/.git" ]] || return 1
  printf "%s" "$path"
}

git_clone_repo() {
  local url dest
  need_tool git "Git" || return
  read -r -p "仓库 URL（https://... 或 git@...）: " url || true
  [[ "$url" =~ ^https://[^[:space:]]+$ || "$url" =~ ^git@[^[:space:]]+:[^[:space:]]+$ ]] || { warn "仓库 URL 格式错误"; return; }
  read -r -p "保存目录 [留空使用仓库默认名]: " dest || true

  if [[ -n "$dest" ]]; then
    show_cmd "git clone $(q "$url") $(q "$dest")"
    git clone "$url" "$dest"
  else
    show_cmd "git clone $(q "$url")"
    git clone "$url"
  fi
}

git_status_repo() {
  local path
  path="$(git_repo_path)" || { warn "不是 Git 仓库"; return; }
  show_cmd "git -C $(q "$path") status --short --branch"
  git -C "$path" status --short --branch
}

git_pull_repo() {
  local path
  path="$(git_repo_path)" || { warn "不是 Git 仓库"; return; }
  show_cmd "git -C $(q "$path") status --short --branch"
  git -C "$path" status --short --branch
  echo
  read -r -p "确认执行 git pull --ff-only？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return
  show_cmd "git -C $(q "$path") pull --ff-only"
  git -C "$path" pull --ff-only
}

git_fetch_repo() {
  local path
  path="$(git_repo_path)" || { warn "不是 Git 仓库"; return; }
  show_cmd "git -C $(q "$path") fetch --all --prune"
  git -C "$path" fetch --all --prune
}

git_branches() {
  local path
  path="$(git_repo_path)" || { warn "不是 Git 仓库"; return; }
  show_cmd "git -C $(q "$path") branch -a"
  git -C "$path" branch -a
}

git_switch_branch() {
  local path branch
  path="$(git_repo_path)" || { warn "不是 Git 仓库"; return; }
  git -C "$path" branch -a || true
  read -r -p "要切换的本地分支名: " branch || true
  [[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] || { warn "分支名格式错误"; return; }
  read -r -p "确认切换到 $branch？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return
  show_cmd "git -C $(q "$path") switch $(q "$branch")"
  git -C "$path" switch "$branch"
}

git_log_repo() {
  local path
  path="$(git_repo_path)" || { warn "不是 Git 仓库"; return; }
  show_cmd "git -C $(q "$path") log --oneline --decorate --graph -n 30"
  git -C "$path" log --oneline --decorate --graph -n 30
}

git_diff_repo() {
  local path
  path="$(git_repo_path)" || { warn "不是 Git 仓库"; return; }
  show_cmd "git -C $(q "$path") diff --stat"
  git -C "$path" diff --stat
  echo
  git -C "$path" diff --color=always | head -n 250 || true
}

git_menu() {
  while true; do
    clear
    echo "================ Git 工具 ================"
    echo "1) 克隆仓库"
    echo "2) 查看仓库状态"
    echo "3) 安全拉取（--ff-only）"
    echo "4) Fetch 全部远端"
    echo "5) 查看分支"
    echo "6) 切换本地分支"
    echo "7) 查看最近提交"
    echo "8) 查看未提交差异"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) git_clone_repo; pause ;;
      2) git_status_repo; pause ;;
      3) git_pull_repo; pause ;;
      4) git_fetch_repo; pause ;;
      5) git_branches; pause ;;
      6) git_switch_branch; pause ;;
      7) git_log_repo; pause ;;
      8) git_diff_repo; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# Docker 常用命令
# ============================================================

docker_require() {
  need_tool docker "Docker" || return 1
}

docker_container_input() {
  local name
  read -r -p "容器名: " name || true
  [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
  docker inspect "$name" >/dev/null 2>&1 || return 1
  printf "%s" "$name"
}

docker_list_all() {
  docker_require || return
  show_cmd "docker ps -a"
  docker ps -a
}

docker_images() {
  docker_require || return
  show_cmd "docker images"
  docker images
}

docker_stats_once() {
  docker_require || return
  show_cmd "docker stats --no-stream"
  docker stats --no-stream
}

docker_disk_usage() {
  docker_require || return
  show_cmd "docker system df"
  docker system df
}

docker_networks() {
  docker_require || return
  show_cmd "docker network ls"
  docker network ls
}

docker_volumes() {
  docker_require || return
  show_cmd "docker volume ls"
  docker volume ls
}

docker_action() {
  local action="$1" name
  docker_require || return
  docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' || true
  name="$(docker_container_input)" || { warn "容器不存在或名称格式错误"; return; }
  read -r -p "确认 docker $action $name？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return
  show_cmd "docker $action $(q "$name")"
  docker "$action" "$name"
}

docker_inspect_cmd() {
  local name
  docker_require || return
  name="$(docker_container_input)" || { warn "容器不存在或名称格式错误"; return; }
  show_cmd "docker inspect $(q "$name")"
  docker inspect "$name"
}

docker_shell_cmd() {
  local name
  docker_require || return
  name="$(docker_container_input)" || { warn "容器不存在或名称格式错误"; return; }
  show_cmd "docker exec -it $(q "$name") sh"
  docker exec -it "$name" sh 2>/dev/null || docker exec -it "$name" bash
}

docker_compose_status() {
  local path
  docker_require || return
  docker compose version >/dev/null 2>&1 || { warn "未检测到 docker compose V2"; return; }
  read -r -p "Compose 项目目录: " path || true
  [[ -f "$path/docker-compose.yml" || -f "$path/compose.yml" || -f "$path/compose.yaml" ]] || { warn "目录里没有 Compose 文件"; return; }
  show_cmd "docker compose -f <项目配置> ps"
  (cd "$path" && docker compose ps)
}

docker_command_menu() {
  while true; do
    clear
    echo "============= Docker 常用命令 ============="
    echo "1) 查看所有容器"
    echo "2) 查看镜像"
    echo "3) 查看容器资源占用"
    echo "4) 查看 Docker 磁盘占用"
    echo "5) 查看网络"
    echo "6) 查看数据卷"
    echo "7) 启动容器"
    echo "8) 停止容器"
    echo "9) 重启容器"
    echo "10) 查看容器详情"
    echo "11) 进入容器 Shell"
    echo "12) 查看 Compose 项目状态"
    echo "13) 查看容器日志"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) docker_list_all; pause ;;
      2) docker_images; pause ;;
      3) docker_stats_once; pause ;;
      4) docker_disk_usage; pause ;;
      5) docker_networks; pause ;;
      6) docker_volumes; pause ;;
      7) docker_action start; pause ;;
      8) docker_action stop; pause ;;
      9) docker_action restart; pause ;;
      10) docker_inspect_cmd; pause ;;
      11) docker_shell_cmd; pause ;;
      12) docker_compose_status; pause ;;
      13) docker_logs; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 数据库工具
# ============================================================

mysql_connect_test() {
  local host port user
  need_tool mysql "MySQL/MariaDB 客户端" || return
  read -r -p "数据库主机 [默认 127.0.0.1]: " host || true
  host="${host:-127.0.0.1}"
  read -r -p "端口 [默认 3306]: " port || true
  port="${port:-3306}"
  valid_port "$port" || { warn "端口格式错误"; return; }
  read -r -p "用户名 [默认 root]: " user || true
  user="${user:-root}"
  read -r -s -p "密码: " password || true
  echo
  show_cmd "MYSQL_PWD=*** mysql -h $(q "$host") -P $port -u $(q "$user") -e 'SELECT VERSION();'"
  MYSQL_PWD="$password" mysql -h "$host" -P "$port" -u "$user" -e 'SELECT VERSION();'
  unset password MYSQL_PWD 2>/dev/null || true
}

mysql_backup() {
  local host port user db out password
  need_tool mysqldump "MySQL/MariaDB 客户端" || return
  read -r -p "数据库主机 [默认 127.0.0.1]: " host || true
  host="${host:-127.0.0.1}"
  read -r -p "端口 [默认 3306]: " port || true
  port="${port:-3306}"
  valid_port "$port" || { warn "端口格式错误"; return; }
  read -r -p "用户名 [默认 root]: " user || true
  user="${user:-root}"
  read -r -p "数据库名: " db || true
  [[ "$db" =~ ^[A-Za-z0-9_$.-]+$ ]] || { warn "数据库名格式错误"; return; }
  read -r -p "输出文件 [默认 /root/$db-$(date +%F).sql.gz]: " out || true
  out="${out:-/root/$db-$(date +%F).sql.gz}"
  read -r -s -p "密码: " password || true
  echo
  show_cmd "MYSQL_PWD=*** mysqldump ... $(q "$db") | gzip > $(q "$out")"
  MYSQL_PWD="$password" mysqldump -h "$host" -P "$port" -u "$user" --single-transaction --routines --triggers "$db" | gzip >"$out"
  unset password MYSQL_PWD 2>/dev/null || true
  ok "备份完成"
  ls -lh "$out"
}

postgres_connect_test() {
  local host port user db password
  need_tool psql "PostgreSQL 客户端" || return
  read -r -p "数据库主机 [默认 127.0.0.1]: " host || true
  host="${host:-127.0.0.1}"
  read -r -p "端口 [默认 5432]: " port || true
  port="${port:-5432}"
  valid_port "$port" || { warn "端口格式错误"; return; }
  read -r -p "用户名 [默认 postgres]: " user || true
  user="${user:-postgres}"
  read -r -p "数据库 [默认 postgres]: " db || true
  db="${db:-postgres}"
  read -r -s -p "密码: " password || true
  echo
  show_cmd "PGPASSWORD=*** psql -h $(q "$host") -p $port -U $(q "$user") -d $(q "$db") -c 'SELECT version();'"
  PGPASSWORD="$password" psql -h "$host" -p "$port" -U "$user" -d "$db" -c 'SELECT version();'
  unset password PGPASSWORD 2>/dev/null || true
}

postgres_backup() {
  local host port user db out password
  need_tool pg_dump "PostgreSQL 客户端" || return
  read -r -p "数据库主机 [默认 127.0.0.1]: " host || true
  host="${host:-127.0.0.1}"
  read -r -p "端口 [默认 5432]: " port || true
  port="${port:-5432}"
  valid_port "$port" || { warn "端口格式错误"; return; }
  read -r -p "用户名 [默认 postgres]: " user || true
  user="${user:-postgres}"
  read -r -p "数据库名: " db || true
  [[ "$db" =~ ^[A-Za-z0-9_$.-]+$ ]] || { warn "数据库名格式错误"; return; }
  read -r -p "输出文件 [默认 /root/$db-$(date +%F).dump]: " out || true
  out="${out:-/root/$db-$(date +%F).dump}"
  read -r -s -p "密码: " password || true
  echo
  show_cmd "PGPASSWORD=*** pg_dump -Fc ... -f $(q "$out") $(q "$db")"
  PGPASSWORD="$password" pg_dump -h "$host" -p "$port" -U "$user" -Fc -f "$out" "$db"
  unset password PGPASSWORD 2>/dev/null || true
  ok "备份完成"
  ls -lh "$out"
}

redis_ping() {
  local host port password
  need_tool redis-cli "Redis 客户端" || return
  read -r -p "Redis 主机 [默认 127.0.0.1]: " host || true
  host="${host:-127.0.0.1}"
  read -r -p "端口 [默认 6379]: " port || true
  port="${port:-6379}"
  valid_port "$port" || { warn "端口格式错误"; return; }
  read -r -s -p "密码（无密码直接回车）: " password || true
  echo
  show_cmd "REDISCLI_AUTH=*** redis-cli -h $(q "$host") -p $port PING"
  if [[ -n "$password" ]]; then
    REDISCLI_AUTH="$password" redis-cli -h "$host" -p "$port" PING
  else
    redis-cli -h "$host" -p "$port" PING
  fi
  unset password REDISCLI_AUTH 2>/dev/null || true
}

database_menu() {
  while true; do
    clear
    echo "=============== 数据库工具 ==============="
    echo "1) 测试 MySQL/MariaDB 连接"
    echo "2) 备份 MySQL/MariaDB 数据库"
    echo "3) 测试 PostgreSQL 连接"
    echo "4) 备份 PostgreSQL 数据库"
    echo "5) Redis PING 测试"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) mysql_connect_test; pause ;;
      2) mysql_backup; pause ;;
      3) postgres_connect_test; pause ;;
      4) postgres_backup; pause ;;
      5) redis_ping; pause ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 服务器迁移辅助
# ============================================================

rsync_dry_run() {
  local src user host dest
  need_tool rsync "rsync" || return
  read -r -p "本机源目录: " src || true
  [[ -d "$src" ]] || { warn "源目录不存在"; return; }
  read -r -p "远端 SSH 用户 [默认 root]: " user || true
  user="${user:-root}"
  [[ "$user" =~ ^[A-Za-z_][A-Za-z0-9_-]{0,31}$ ]] || { warn "用户名格式错误"; return; }
  read -r -p "远端 IP/域名: " host || true
  [[ -n "$host" && "$host" != *" "* ]] || { warn "主机格式错误"; return; }
  read -r -p "远端目录（例如 /opt/backup/）: " dest || true
  [[ "$dest" == /* ]] || { warn "请输入绝对路径"; return; }

  show_cmd "rsync -avhn --delete-delay $(q "$src/") $(q "$user@$host:$dest")"
  rsync -avhn --delete-delay "$src/" "$user@$host:$dest"
}

rsync_transfer() {
  local src user host dest port
  need_tool rsync "rsync" || return
  read -r -p "本机源目录: " src || true
  [[ -d "$src" ]] || { warn "源目录不存在"; return; }
  read -r -p "远端 SSH 用户 [默认 root]: " user || true
  user="${user:-root}"
  [[ "$user" =~ ^[A-Za-z_][A-Za-z0-9_-]{0,31}$ ]] || { warn "用户名格式错误"; return; }
  read -r -p "远端 IP/域名: " host || true
  [[ -n "$host" && "$host" != *" "* ]] || { warn "主机格式错误"; return; }
  read -r -p "SSH 端口 [默认 22]: " port || true
  port="${port:-22}"
  valid_port "$port" || { warn "端口格式错误"; return; }
  read -r -p "远端目录（例如 /opt/backup/）: " dest || true
  [[ "$dest" == /* ]] || { warn "请输入绝对路径"; return; }

  warn "建议先执行“迁移预演（dry-run）”。"
  read -r -p "确认开始真实传输？(y/N): " yn || true
  [[ "${yn,,}" == "y" ]] || return

  show_cmd "rsync -avh --partial --progress -e 'ssh -p $port' $(q "$src/") $(q "$user@$host:$dest")"
  rsync -avh --partial --progress -e "ssh -p $port" "$src/" "$user@$host:$dest"
}

migration_checksum() {
  local path
  read -r -p "文件路径: " path || true
  [[ -f "$path" ]] || { warn "文件不存在"; return; }
  show_cmd "sha256sum $(q "$path")"
  sha256sum "$path"
}

migration_menu() {
  while true; do
    clear
    echo "============= 服务器迁移辅助 ============="
    echo "1) rsync 迁移预演（不会写入远端）"
    echo "2) rsync 正式传输目录"
    echo "3) 计算文件 SHA256"
    echo "4) 压缩/解压工具"
    echo "0) 返回"
    echo
    read -r -p "请选择: " c || true
    case "$c" in
      1) rsync_dry_run; pause ;;
      2) rsync_transfer; pause ;;
      3) migration_checksum; pause ;;
      4) archive_menu ;;
      0) return ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

# ============================================================
# 域名 / 证书深入诊断
# ============================================================

dns_compare_public() {
  local d
  d="$(domain_input)" || { warn "域名格式错误"; return; }
  need_tool dig "DNS 查询工具" || return
  echo "系统默认 DNS："
  show_cmd "dig +short A $(q "$d")"
  dig +short A "$d" || true
  echo
  echo "Cloudflare 1.1.1.1："
  show_cmd "dig @1.1.1.1 +short A $(q "$d")"
  dig @1.1.1.1 +short A "$d" || true
  echo
  echo "Google 8.8.8.8："
  show_cmd "dig @8.8.8.8 +short A $(q "$d")"
  dig @8.8.8.8 +short A "$d" || true
}

certificate_days_left() {
  local d end epoch_end epoch_now days
  d="$(domain_input)" || { warn "域名格式错误"; return; }
  need_tool openssl "OpenSSL" || return
  show_cmd "openssl s_client ... | openssl x509 -noout -enddate"
  end="$(timeout 10 openssl s_client -connect "$d:443" -servername "$d" </dev/null 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2- || true)"
  [[ -n "$end" ]] || { err "无法读取证书到期时间"; return; }
  epoch_end="$(date -d "$end" +%s 2>/dev/null || true)"
  epoch_now="$(date +%s)"
  [[ -n "$epoch_end" ]] || { echo "到期时间：$end"; return; }
  days=$(( (epoch_end-epoch_now) / 86400 ))
  echo "到期时间：$end"
  if (( days < 0 )); then
    err "证书已过期 $((-days)) 天"
  elif (( days <= 14 )); then
    warn "剩余 $days 天"
  else
    ok "剩余 $days 天"
  fi
}

http_timing() {
  local url
  read -r -p "网址（例如 https://example.com）: " url || true
  [[ "$url" =~ ^https?://[^[:space:]]+$ ]] || { warn "URL 格式错误"; return; }
  need_tool curl "curl" || return
  show_cmd "curl -o /dev/null -sS -w '<timing>' $(q "$url")"
  curl -o /dev/null -sS --max-time 20 -w \
'DNS: %{time_namelookup}s
TCP: %{time_connect}s
TLS: %{time_appconnect}s
首字节: %{time_starttransfer}s
总耗时: %{time_total}s
HTTP: %{http_code}
远端IP: %{remote_ip}
' "$url" || true
}

check_web_ports() {
  local d
  d="$(domain_input)" || { warn "域名格式错误"; return; }
  echo "检查 80："
  if have nc; then
    show_cmd "nc -vz -w 5 $(q "$d") 80"
    nc -vz -w 5 "$d" 80 || true
    echo
    echo "检查 443："
    show_cmd "nc -vz -w 5 $(q "$d") 443"
    nc -vz -w 5 "$d" 443 || true
  else
    warn "插件中心安装 netcat 后可进行端口探测"
  fi
}

# ============================================================
# 快速搜索/导航
# ============================================================

quick_search() {
  local ql
  read -r -p "输入你想做的事（如：端口 / 磁盘 / DNS / 软件 / 用户 / Cron / Git / Docker）: " ql || true
  ql="${ql,,}"

  case "$ql" in
    *端口*|*port*|*连接*) port_menu ;;
    *进程*|*process*|*cpu*|*内存*) process_menu ;;
    *服务*|*service*|*systemd*) service_menu ;;
    *dns*|*域名*|*证书*|*https*|*tls*) dns_menu ;;
    *文件*|*磁盘*|*目录*|*空间*) disk_menu ;;
    *网络*|*ping*|*路由*|*mtr*) network_menu ;;
    *日志*|*log*) log_menu ;;
    *软件*|*安装*|*卸载*|*apt*|*dnf*|*package*) package_menu ;;
    *权限*|*chmod*|*chown*|*sudo*) user_permission_menu ;;
    *cron*|*定时*|*timer*) cron_menu ;;
    *压缩*|*解压*|*tar*|*zip*) archive_menu ;;
    *git*|*仓库*|*代码*) git_menu ;;
    *docker*|*容器*) docker_command_menu ;;
    *mysql*|*postgres*|*redis*|*数据库*) database_menu ;;
    *迁移*|*rsync*|*同步*) migration_menu ;;
    *系统*|*用户*|*登录*) system_user_menu ;;
    *) warn "暂时没有匹配到。可以从主分类进入。" ; pause ;;
  esac
}

while true; do
  clear
  echo "============================================================"
  echo "                 命令工具中心"
  echo "============================================================"
  echo "不需要记 Linux 命令：选择你想做的事即可。"
  echo "每次执行都会显示实际命令，便于理解和排查。"
  rule
  echo "1) 端口 / 网络连接"
  echo "2) 进程管理"
  echo "3) systemd 服务管理"
  echo "4) 域名 / DNS / HTTPS"
  echo "5) 文件 / 磁盘"
  echo "6) 网络诊断"
  echo "7) 日志中心"
  echo "8) 系统 / 用户信息"
  echo "9) 软件包管理"
  echo "10) 用户 / 文件权限"
  echo "11) Cron / 定时任务"
  echo "12) 压缩 / 解压"
  echo "13) Git 常用操作"
  echo "14) Docker 常用命令"
  echo "15) 数据库工具"
  echo "16) 服务器迁移辅助"
  echo
  echo "S) 搜索我要做的事"
  echo "H) 查看最近执行命令"
  echo "0) 返回"
  echo
  read -r -p "请选择: " c || true

  case "$c" in
    1) port_menu ;;
    2) process_menu ;;
    3) service_menu ;;
    4) dns_menu ;;
    5) disk_menu ;;
    6) network_menu ;;
    7) log_menu ;;
    8) system_user_menu ;;
    9) package_menu ;;
    10) user_permission_menu ;;
    11) cron_menu ;;
    12) archive_menu ;;
    13) git_menu ;;
    14) docker_command_menu ;;
    15) database_menu ;;
    16) migration_menu ;;
    s|S) quick_search ;;
    h|H) clear; command_history; pause ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
