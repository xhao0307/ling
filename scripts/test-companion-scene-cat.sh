#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${CITYLING_BASE_URL:-http://127.0.0.1:39028}"
IMAGE_PATH="${1:-$ROOT_DIR/cat.png}"
CHILD_ID="${CITYLING_TEST_CHILD_ID:-kid_cat_test}"
CHILD_AGE="${CITYLING_TEST_CHILD_AGE:-8}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1"
    exit 1
  fi
}

if [[ ! -f "$IMAGE_PATH" ]]; then
  echo "图片不存在: $IMAGE_PATH"
  exit 1
fi

require_cmd curl
require_cmd jq
require_cmd base64

encode_base64() {
  if base64 --help 2>/dev/null | grep -q -- "-w"; then
    base64 -w 0 "$1"
  else
    base64 <"$1" | tr -d '\n'
  fi
}

IMAGE_B64="$(encode_base64 "$IMAGE_PATH")"
if [[ -z "$IMAGE_B64" ]]; then
  echo "图片 base64 为空"
  exit 1
fi

tmp_scan_image="$(mktemp)"
tmp_scan="$(mktemp)"
tmp_scene="$(mktemp)"
req_scan_image="$(mktemp)"
req_scan="$(mktemp)"
req_scene="$(mktemp)"
trap 'rm -f "$tmp_scan_image" "$tmp_scan" "$tmp_scene" "$req_scan_image" "$req_scan" "$req_scene"' EXIT

echo "[1/3] POST /api/v1/scan/image"
cat >"$req_scan_image" <<EOF
{
  "child_id":"$CHILD_ID",
  "child_age":$CHILD_AGE,
  "image_base64":"$IMAGE_B64"
}
EOF
scan_image_code="$(
  curl -sS -o "$tmp_scan_image" -w "%{http_code}" \
    -X POST "$BASE_URL/api/v1/scan/image" \
    -H "Content-Type: application/json" \
    --data-binary "@$req_scan_image"
)"
echo "HTTP $scan_image_code"
if [[ "$scan_image_code" != "200" ]]; then
  echo "scan/image 失败:"
  cat "$tmp_scan_image"
  exit 1
fi

detected_label="$(jq -r '.detected_label_en // .detected_label // empty' "$tmp_scan_image")"
if [[ -z "$detected_label" || "$detected_label" == "null" ]]; then
  echo "scan/image 未返回 detected_label:"
  cat "$tmp_scan_image"
  exit 1
fi
echo "detected_label=$detected_label"

echo "[2/3] POST /api/v1/scan"
cat >"$req_scan" <<EOF
{
  "child_id":"$CHILD_ID",
  "child_age":$CHILD_AGE,
  "detected_label":"$detected_label"
}
EOF
scan_code="$(
  curl -sS -o "$tmp_scan" -w "%{http_code}" \
    -X POST "$BASE_URL/api/v1/scan" \
    -H "Content-Type: application/json" \
    --data-binary "@$req_scan"
)"
echo "HTTP $scan_code"
if [[ "$scan_code" != "200" ]]; then
  echo "scan 失败:"
  cat "$tmp_scan"
  exit 1
fi

object_type="$(jq -r '.object_type // empty' "$tmp_scan")"
if [[ -z "$object_type" || "$object_type" == "null" ]]; then
  echo "scan 未返回 object_type:"
  cat "$tmp_scan"
  exit 1
fi
echo "object_type=$object_type"

echo "[3/3] POST /api/v1/companion/scene (携带 source_image_base64)"
cat >"$req_scene" <<EOF
{
  "child_id":"$CHILD_ID",
  "child_age":$CHILD_AGE,
  "object_type":"$object_type",
  "weather":"晴天",
  "environment":"室内",
  "object_traits":"毛茸茸",
  "source_image_base64":"$IMAGE_B64"
}
EOF
scene_code="$(
  curl -sS -o "$tmp_scene" -w "%{http_code}" \
    -X POST "$BASE_URL/api/v1/companion/scene" \
    -H "Content-Type: application/json" \
    --data-binary "@$req_scene"
)"
echo "HTTP $scene_code"
if [[ "$scene_code" != "200" ]]; then
  echo "companion/scene 失败:"
  cat "$tmp_scene"
  exit 1
fi

character_name="$(jq -r '.character_name // empty' "$tmp_scene")"
dialog_text="$(jq -r '.dialog_text // empty' "$tmp_scene")"
image_url="$(jq -r '.character_image_url // empty' "$tmp_scene")"
image_b64_len="$(jq -r '(.character_image_base64 // "") | length' "$tmp_scene")"
voice_b64_len="$(jq -r '(.voice_audio_base64 // "") | length' "$tmp_scene")"

echo "character_name=${character_name:-<empty>}"
echo "dialog_text=${dialog_text:-<empty>}"
echo "character_image_url=${image_url:-<empty>}"
echo "character_image_base64_length=$image_b64_len"
echo "voice_audio_base64_length=$voice_b64_len"

if [[ -z "$dialog_text" || "$dialog_text" == "null" ]]; then
  echo "FAIL: dialog_text 为空"
  cat "$tmp_scene"
  exit 1
fi
if [[ "$voice_b64_len" -le 0 ]]; then
  echo "FAIL: voice_audio_base64 为空"
  cat "$tmp_scene"
  exit 1
fi
if [[ -z "$image_url" && "$image_b64_len" -le 0 ]]; then
  echo "FAIL: 角色图 URL/base64 都为空"
  cat "$tmp_scene"
  exit 1
fi

echo "PASS: cat 图片剧情接口链路正常。"
