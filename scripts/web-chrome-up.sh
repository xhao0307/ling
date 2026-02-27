#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="${CITYLING_FLUTTER_DIR:-$ROOT_DIR/flutter_client}"
WEB_PORT="${CITYLING_WEB_PORT:-7357}"
WEB_HOST="${CITYLING_WEB_HOST:-127.0.0.1}"
WEB_URL="http://${WEB_HOST}:${WEB_PORT}"
WEB_PID_FILE="${CITYLING_WEB_PID_FILE:-/tmp/cityling_web.pid}"
WEB_LOG_FILE="${CITYLING_WEB_LOG_FILE:-/tmp/cityling_web.log}"
BASE_URL="${CITYLING_BASE_URL:-http://121.43.118.53:3026}"
START_BACKEND="${CITYLING_WEB_START_BACKEND:-0}"
OPEN_BROWSER="${CITYLING_WEB_OPEN_BROWSER:-1}"
SKIP_BUILD="${CITYLING_WEB_SKIP_BUILD:-0}"

# Prefer explicit Flutter path, fallback to PATH.
FLUTTER_BIN="${CITYLING_FLUTTER_BIN:-}"
if [[ -z "$FLUTTER_BIN" ]]; then
  if [[ -x "/Users/xuxinghao/develop/flutter/bin/flutter" ]]; then
    FLUTTER_BIN="/Users/xuxinghao/develop/flutter/bin/flutter"
  else
    FLUTTER_BIN="flutter"
  fi
fi

usage() {
  cat <<USAGE
用法:
  scripts/web-chrome-up.sh start    # 构建并启动 Web + 打开 Chrome
  CITYLING_WEB_SKIP_BUILD=1 scripts/web-chrome-up.sh restart
                                   # 快速重启：复用现有 build/web，不重新构建
  scripts/web-chrome-up.sh stop     # 停止 Web 静态服务
  scripts/web-chrome-up.sh status   # 查看后端与 Web 状态
  scripts/web-chrome-up.sh restart  # 重启 Web

可选环境变量:
  CITYLING_BASE_URL           Flutter 构建时注入的后端地址（默认: ${BASE_URL})
  CITYLING_WEB_PORT           Web 端口（默认: ${WEB_PORT})
  CITYLING_WEB_START_BACKEND  1/0，是否先执行 ./init.sh restart（默认: ${START_BACKEND})
  CITYLING_WEB_OPEN_BROWSER   1/0，是否自动打开 Chrome（默认: ${OPEN_BROWSER})
  CITYLING_WEB_SKIP_BUILD     1/0，是否跳过 pub get/build（默认: ${SKIP_BUILD}）
  CITYLING_FLUTTER_BIN        Flutter 可执行文件路径
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1"
    exit 1
  fi
}

port_listeners() {
  if ! command -v lsof >/dev/null 2>&1; then
    return 0
  fi
  lsof -tiTCP:"$WEB_PORT" -sTCP:LISTEN 2>/dev/null || true
}

is_web_running() {
  [[ -n "$(port_listeners)" ]]
}

wait_web_ready() {
  for _ in $(seq 1 40); do
    if curl -fsS "$WEB_URL" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

open_chrome() {
  if [[ "$OPEN_BROWSER" != "1" ]]; then
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    open -a "Google Chrome" "$WEB_URL" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$WEB_URL" >/dev/null 2>&1 || true
  fi
}

stop_web() {
  local stopped_any=0
  if is_web_running; then
    if [[ -f "$WEB_PID_FILE" ]]; then
      local pid
      pid="$(cat "$WEB_PID_FILE" 2>/dev/null || true)"
      if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        sleep 0.2
        if kill -0 "$pid" 2>/dev/null; then
          kill -9 "$pid" 2>/dev/null || true
        fi
        echo "已停止 Web 服务: pid=$pid"
        stopped_any=1
      fi
    fi
  fi

  local listener_pids
  listener_pids="$(port_listeners)"
  if [[ -n "$listener_pids" ]]; then
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      local cmd
      cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
      if [[ "$cmd" == *"-m http.server $WEB_PORT"* ]]; then
        kill "$pid" 2>/dev/null || true
        sleep 0.1
        if kill -0 "$pid" 2>/dev/null; then
          kill -9 "$pid" 2>/dev/null || true
        fi
        echo "已清理端口占用进程: pid=$pid"
        stopped_any=1
      fi
    done <<< "$listener_pids"
  fi

  if [[ "$stopped_any" == "0" ]]; then
    echo "Web 服务未运行"
  else
    sleep 0.2
  fi
  rm -f "$WEB_PID_FILE"
}

start_web() {
  require_cmd curl
  require_cmd python3

  if [[ "$START_BACKEND" == "1" ]]; then
    (cd "$ROOT_DIR" && ./init.sh restart)
  fi

  if [[ ! -d "$FLUTTER_DIR" ]]; then
    echo "Flutter 目录不存在: $FLUTTER_DIR"
    exit 1
  fi

  if [[ "$SKIP_BUILD" == "1" ]]; then
    if [[ ! -d "$FLUTTER_DIR/build/web" ]]; then
      echo "快速模式失败：未找到 $FLUTTER_DIR/build/web，请先执行一次完整构建：scripts/web-chrome-up.sh start"
      exit 1
    fi
    echo "快速模式：跳过 pub get/build，复用已有 build/web"
  else
    (cd "$FLUTTER_DIR" && "$FLUTTER_BIN" pub get)
    (cd "$FLUTTER_DIR" && "$FLUTTER_BIN" build web --dart-define=CITYLING_BASE_URL="$BASE_URL")
  fi

  stop_web

  mkdir -p "$(dirname "$WEB_LOG_FILE")"
  : >"$WEB_LOG_FILE"
  (cd "$FLUTTER_DIR/build/web" && nohup python3 -m http.server "$WEB_PORT" >"$WEB_LOG_FILE" 2>&1 & echo $! >"$WEB_PID_FILE")

  if ! wait_web_ready; then
    echo "Web 启动失败，日志如下:"
    tail -n 60 "$WEB_LOG_FILE" || true
    exit 1
  fi

  local pid
  pid="$(cat "$WEB_PID_FILE" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    echo "Web 启动异常：未生成 pid 文件"
    tail -n 60 "$WEB_LOG_FILE" || true
    exit 1
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "Web 启动异常：新进程未存活（pid=${pid:-none}）"
    tail -n 60 "$WEB_LOG_FILE" || true
    exit 1
  fi

  if [[ -z "$(port_listeners)" ]]; then
    echo "Web 启动异常：端口 ${WEB_PORT} 无监听进程"
    tail -n 60 "$WEB_LOG_FILE" || true
    exit 1
  fi

  echo "Web 已启动: pid=$pid, url=$WEB_URL"
  open_chrome
}

status_all() {
  if [[ "$START_BACKEND" == "1" ]]; then
    (cd "$ROOT_DIR" && ./init.sh status) || true
  else
    echo "backend: skipped (使用远程后端)"
  fi
  if is_web_running; then
    local pid
    pid="$(port_listeners | head -n 1)"
    echo "web: running pid=$pid url=$WEB_URL log=$WEB_LOG_FILE"
  else
    echo "web: stopped url=$WEB_URL log=$WEB_LOG_FILE"
  fi
}

cmd="${1:-start}"
case "$cmd" in
  start)
    start_web
    ;;
  stop)
    stop_web
    ;;
  status)
    status_all
    ;;
  restart)
    stop_web
    start_web
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "未知命令: $cmd"
    usage
    exit 1
    ;;
esac
