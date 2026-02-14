#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${PM2_APP_NAME:-cityling-backend}"

cd "$ROOT_DIR"

# Load project env so pm2 start/restart gets all variables without manual export.
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${CITYLING_HOST:=0.0.0.0}"
: "${CITYLING_PORT:=8082}"

mkdir -p bin
echo "[pm2-up] building backend binary..."
go build -o ./bin/cityling-server ./cmd/server

echo "[pm2-up] start or restart app: $APP_NAME"
pm2 startOrRestart ecosystem.config.cjs --only "$APP_NAME" --update-env

echo "[pm2-up] pm2 status:"
pm2 status "$APP_NAME"

echo "[pm2-up] done."
