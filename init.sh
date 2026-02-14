#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${CITYLING_BOOT_HOST:-127.0.0.1}"
PORT="${CITYLING_BOOT_PORT:-39028}"
BASE_URL="http://${HOST}:${PORT}"
PID_FILE="${CITYLING_BOOT_PID_FILE:-/tmp/cityling_dev.pid}"
LOG_FILE="${CITYLING_BOOT_LOG_FILE:-/tmp/cityling_dev.log}"

usage() {
  cat <<EOF
用法:
  ./init.sh                启动服务并执行 smoke test（默认）
  ./init.sh start          仅启动服务
  ./init.sh smoke          仅执行 smoke test（要求服务已启动）
  ./init.sh restart        重启服务并执行 smoke test
  ./init.sh stop           停止服务
  ./init.sh status         查看服务状态
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1"
    exit 1
  fi
}

is_running() {
  if [[ ! -f "$PID_FILE" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

wait_ready() {
  for _ in $(seq 1 50); do
    if curl -fsS "${BASE_URL}/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

start_server() {
  require_cmd go
  require_cmd curl

  if is_running; then
    echo "服务已运行: pid=$(cat "$PID_FILE"), url=${BASE_URL}"
    return 0
  fi

  cd "$ROOT_DIR"
  nohup go run ./cmd/server -host "$HOST" -port "$PORT" >"$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" >"$PID_FILE"

  if ! wait_ready; then
    echo "服务启动失败，最近日志:"
    tail -n 50 "$LOG_FILE" || true
    exit 1
  fi

  echo "服务已启动: pid=$pid, url=${BASE_URL}"
}

stop_server() {
  if ! is_running; then
    echo "服务未运行"
    rm -f "$PID_FILE"
    return 0
  fi

  local pid
  pid="$(cat "$PID_FILE")"
  kill "$pid" 2>/dev/null || true
  sleep 0.2
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  echo "服务已停止: pid=$pid"
}

status_server() {
  if is_running; then
    echo "running pid=$(cat "$PID_FILE") url=${BASE_URL} log=${LOG_FILE}"
  else
    echo "stopped url=${BASE_URL} log=${LOG_FILE}"
  fi
}

smoke_test() {
  require_cmd curl
  require_cmd grep

  local health
  health="$(curl -fsS "${BASE_URL}/healthz")"
  echo "$health" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"' || {
    echo "healthz 校验失败: $health"
    exit 1
  }

  curl -fsS "${BASE_URL}/docs/openapi.json" >/dev/null

  local scan
  scan="$(curl -fsS -X POST "${BASE_URL}/api/v1/scan" \
    -H "Content-Type: application/json" \
    -d '{"child_id":"kid_smoke","child_age":8,"detected_label":"mailbox"}')"

  echo "$scan" | grep -q '"session_id"' || {
    echo "scan 接口校验失败: $scan"
    exit 1
  }

  echo "smoke 通过: ${BASE_URL}"
}

cmd="${1:-bootstrap}"
case "$cmd" in
  start)
    start_server
    ;;
  smoke)
    smoke_test
    ;;
  restart)
    stop_server
    start_server
    smoke_test
    ;;
  stop)
    stop_server
    ;;
  status)
    status_server
    ;;
  bootstrap|init)
    start_server
    smoke_test
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
