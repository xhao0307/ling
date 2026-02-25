#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BADGE_RULES_FILE="${CITYLING_BADGE_RULES_FILE:-$ROOT_DIR/internal/service/badge_rules.json}"
BADGE_IMAGE_DIR="${CITYLING_BADGE_IMAGE_DIR:-$ROOT_DIR/勋章图例}"
BADGE_MANIFEST_OUT="${CITYLING_BADGE_ASSET_MANIFEST:-$ROOT_DIR/design/badges/cloud_badge_assets.json}"
BASE_URL="${CITYLING_BADGE_UPLOAD_BASE_URL:-${CITYLING_BASE_URL:-http://127.0.0.1:39028}}"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
  set +a
  BASE_URL="${CITYLING_BADGE_UPLOAD_BASE_URL:-${CITYLING_BASE_URL:-$BASE_URL}}"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1"
    exit 1
  fi
}

require_cmd curl
require_cmd jq

if [[ ! -f "$BADGE_RULES_FILE" ]]; then
  echo "勋章规则文件不存在: $BADGE_RULES_FILE"
  exit 1
fi
if [[ ! -d "$BADGE_IMAGE_DIR" ]]; then
  echo "勋章图片目录不存在: $BADGE_IMAGE_DIR"
  exit 1
fi

health_code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE_URL/healthz" || true)"
if [[ "$health_code" != "200" ]]; then
  echo "后端未就绪，请先启动服务: $BASE_URL/healthz (got $health_code)"
  exit 1
fi

echo "upload_base_url=$BASE_URL"

mkdir -p "$(dirname "$BADGE_MANIFEST_OUT")"
tmp_manifest="$(mktemp)"
tmp_resp="$(mktemp)"
trap 'rm -f "$tmp_manifest" "$tmp_resp"' EXIT

echo '{"updated_at":"","items":[]}' >"$tmp_manifest"

uploaded=0
skipped=0
failed=0

while IFS= read -r -d '' image_file; do
  base_name="$(basename "$image_file")"
  source_file="勋章图例/$base_name"
  badge_id="$(
    jq -r --arg source "$source_file" '
      .badges[]
      | select(.image_file == $source)
      | .id
    ' "$BADGE_RULES_FILE" | head -n 1
  )"

  if [[ -z "$badge_id" || "$badge_id" == "null" ]]; then
    echo "跳过（规则未绑定）: $source_file"
    skipped=$((skipped + 1))
    continue
  fi

  http_code="$(
    curl -sS -o "$tmp_resp" -w '%{http_code}' \
      -X POST "$BASE_URL/api/v1/media/upload" \
      -F "file=@${image_file};type=image/jpeg"
  )"

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "上传失败: $source_file http=$http_code body=$(cat "$tmp_resp")"
    failed=$((failed + 1))
    continue
  fi

  image_url="$(jq -r '.image_url // empty' "$tmp_resp")"
  if [[ -z "$image_url" ]]; then
    echo "上传失败: $source_file 响应缺少 image_url"
    failed=$((failed + 1))
    continue
  fi

  jq \
    --arg badge_id "$badge_id" \
    --arg source_file "$source_file" \
    --arg image_url "$image_url" \
    '.items += [{"badge_id":$badge_id,"source_file":$source_file,"image_url":$image_url}]' \
    "$tmp_manifest" >"${tmp_manifest}.next"
  mv "${tmp_manifest}.next" "$tmp_manifest"

  echo "上传成功: $source_file -> $image_url"
  uploaded=$((uploaded + 1))
done < <(find "$BADGE_IMAGE_DIR" -maxdepth 1 -type f -name '*.jpg' -print0 | sort -z)

jq --arg updated_at "$(date '+%Y-%m-%d %H:%M:%S')" '.updated_at = $updated_at' "$tmp_manifest" >"${tmp_manifest}.final"
mv "${tmp_manifest}.final" "$BADGE_MANIFEST_OUT"

echo "完成: uploaded=$uploaded skipped=$skipped failed=$failed"
echo "manifest: $BADGE_MANIFEST_OUT"

if [[ "$failed" -gt 0 ]]; then
  exit 2
fi
