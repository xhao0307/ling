#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${PM2_APP_NAME:-cityling-backend}"

cd "$ROOT_DIR"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

load_config_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* || "$line" == \;* ]] && continue
    [[ "$line" == \[*\] ]] && continue

    if [[ "$line" == export\ * ]]; then
      line="$(trim "${line#export }")"
    fi
    [[ "$line" == *=* ]] || continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="$(trim "$key")"
    value="$(trim "$value")"

    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ "${value:0:1}" == "\"" && "${value: -1}" == "\"" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi

    if [[ -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done <"$file"
}

# Load project config so pm2 start/restart gets all variables without manual export.
load_config_file "ling.ini"
load_config_file ".env"

: "${CITYLING_HOST:=0.0.0.0}"
: "${CITYLING_PORT:=3026}"

mkdir -p bin
echo "[pm2-up] building backend binary..."
go build -o ./bin/cityling-server ./cmd/server

echo "[pm2-up] start or restart app: $APP_NAME"
pm2 startOrRestart ecosystem.config.cjs --only "$APP_NAME" --update-env

echo "[pm2-up] pm2 status:"
pm2 status "$APP_NAME"

echo "[pm2-up] done."
