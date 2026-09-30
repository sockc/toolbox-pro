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
# 快速搜索/导航
# ============================================================

quick_search() {
  local ql
  read -r -p "输入你想做的事（如：端口 / 磁盘 / DNS / 日志 / 服务 / 进程）: " ql || true
  ql="${ql,,}"

  case "$ql" in
    *端口*|*port*|*连接*) port_menu ;;
    *进程*|*process*|*cpu*|*内存*) process_menu ;;
    *服务*|*service*|*systemd*) service_menu ;;
    *dns*|*域名*|*证书*|*https*|*tls*) dns_menu ;;
    *文件*|*磁盘*|*目录*|*空间*) disk_menu ;;
    *网络*|*ping*|*路由*|*mtr*) network_menu ;;
    *日志*|*log*) log_menu ;;
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
    s|S) quick_search ;;
    h|H) clear; command_history; pause ;;
    0) exit 0 ;;
    *) warn "无效选项"; sleep 1 ;;
  esac
done
