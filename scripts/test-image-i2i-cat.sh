#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_API_BASE_URL="${CITYLING_IMAGE_API_BASE_URL:-https://api-image.charaboard.com}"
IMAGE_API_KEY="${CITYLING_IMAGE_API_KEY:-${CITYLING_LLM_API_KEY:-}}"
IMAGE_MODEL="${CITYLING_IMAGE_MODEL:-seedream-4-0-250828}"
APP_ID="${CITYLING_LLM_APP_ID:-4}"
PLATFORM_ID="${CITYLING_LLM_PLATFORM_ID:-5}"
MAX_TIME="${CITYLING_IMAGE_MAX_TIME:-60}"
IMAGE_INPUT="${1:-$ROOT_DIR/cat.png}"
PROMPT="${CITYLING_IMAGE_PROMPT:-基于参考图生成儿童向二次元拟人角色，保留主体外形和配色特征，单人清晰构图，明亮柔和插画风。}"
OUT_DIR="${CITYLING_IMAGE_TEST_OUT_DIR:-$ROOT_DIR/test_screenshots}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1"
    exit 1
  fi
}

require_cmd curl
require_cmd jq
require_cmd base64

if [[ -z "$IMAGE_API_KEY" ]]; then
  echo "缺少 API Key，请设置 CITYLING_IMAGE_API_KEY 或 CITYLING_LLM_API_KEY"
  exit 1
fi

encode_base64() {
  if base64 --help 2>/dev/null | grep -q -- "-w"; then
    base64 -w 0 "$1"
  else
    base64 <"$1" | tr -d '\n'
  fi
}

mime_type_from_path() {
  local lower
  lower="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.png) echo "image/png" ;;
    *.jpg|*.jpeg) echo "image/jpeg" ;;
    *.webp) echo "image/webp" ;;
    *) echo "image/jpeg" ;;
  esac
}

build_image_ref() {
  local input="$1"
  if [[ "$input" =~ ^https?:// ]]; then
    echo "$input"
    return
  fi
  if [[ "$input" =~ ^data:image/ ]]; then
    echo "$input"
    return
  fi
  if [[ ! -f "$input" ]]; then
    echo "图片不存在: $input" >&2
    exit 1
  fi
  local mime image_b64
  mime="$(mime_type_from_path "$input")"
  image_b64="$(encode_base64 "$input")"
  if [[ -z "$image_b64" ]]; then
    echo "图片 base64 为空: $input" >&2
    exit 1
  fi
  echo "data:${mime};base64,${image_b64}"
}

IMAGE_REF="$(build_image_ref "$IMAGE_INPUT")"
resp_file="$(mktemp)"
req_file="$(mktemp)"
image_ref_file="$(mktemp)"
trap 'rm -f "$resp_file" "$req_file" "$image_ref_file"' EXIT
printf '%s' "$IMAGE_REF" >"$image_ref_file"

jq -n \
  --arg model "$IMAGE_MODEL" \
  --arg prompt "$PROMPT" \
  --rawfile image "$image_ref_file" \
  '{
    model: $model,
    prompt: $prompt,
    image: $image,
    n: 1,
    response_format: "url",
    size: "2K",
    stream: false,
    watermark: true
  }' >"$req_file"

echo "POST ${IMAGE_API_BASE_URL}/v1/byteplus/images/generations"
echo "model=$IMAGE_MODEL"
echo "image_input=$IMAGE_INPUT"
echo "x-app-id=$APP_ID x-platform-id=$PLATFORM_ID x-max-time=$MAX_TIME"

http_code="$(
  curl -sS -o "$resp_file" -w "%{http_code}" \
    -X POST "${IMAGE_API_BASE_URL}/v1/byteplus/images/generations" \
    -H "Authorization: Bearer ${IMAGE_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "x-app-id: ${APP_ID}" \
    -H "x-platform-id: ${PLATFORM_ID}" \
    -H "x-max-time: ${MAX_TIME}" \
    --data-binary "@${req_file}"
)"

echo "HTTP $http_code"
if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  echo "请求失败，响应体:"
  cat "$resp_file"
  exit 1
fi

url="$(jq -r '.data[0].url // empty' "$resp_file")"
b64_len="$(jq -r '(.data[0].b64_json // "") | length' "$resp_file")"
size="$(jq -r '.data[0].size // empty' "$resp_file")"
generated="$(jq -r '.usage.generated_images // 0' "$resp_file")"

echo "generated_images=$generated"
echo "size=${size:-<empty>}"
echo "image_url=${url:-<empty>}"
echo "b64_length=$b64_len"

mkdir -p "$OUT_DIR"
cp "$resp_file" "$OUT_DIR/image_i2i_last_response.json"
echo "响应已保存: $OUT_DIR/image_i2i_last_response.json"

if [[ -z "$url" && "$b64_len" -le 0 ]]; then
  echo "FAIL: data[0].url 和 data[0].b64_json 都为空"
  cat "$resp_file"
  exit 1
fi

echo "PASS: 图生图接口调用成功。"
