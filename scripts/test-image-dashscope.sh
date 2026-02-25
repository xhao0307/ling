#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DASHSCOPE_API_URL="${CITYLING_DASHSCOPE_API_URL:-https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation}"
DASHSCOPE_API_KEY="${CITYLING_DASHSCOPE_API_KEY:-}"
DASHSCOPE_MODEL="${CITYLING_DASHSCOPE_MODEL:-${CITYLING_IMAGE_MODEL:-wan2.6-image}}"
IMAGE_INPUT="${1:-https://media-1406176426.cos.ap-hongkong.myqcloud.com/1772003944_cat.png}"
PROMPT="${CITYLING_DASHSCOPE_PROMPT:-参考此图生成绘本风格的图片，在日常环境中，主体大小占1/5左右}"
SIZE="${CITYLING_DASHSCOPE_SIZE:-1280*1280}"
OUT_DIR="${CITYLING_IMAGE_TEST_OUT_DIR:-$ROOT_DIR/test_screenshots}"
OUT_FILE="$OUT_DIR/dashscope_i2i_last_response.json"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
  set +a
  DASHSCOPE_API_URL="${CITYLING_DASHSCOPE_API_URL:-$DASHSCOPE_API_URL}"
  DASHSCOPE_API_KEY="${CITYLING_DASHSCOPE_API_KEY:-$DASHSCOPE_API_KEY}"
  DASHSCOPE_MODEL="${CITYLING_DASHSCOPE_MODEL:-${CITYLING_IMAGE_MODEL:-$DASHSCOPE_MODEL}}"
  PROMPT="${CITYLING_DASHSCOPE_PROMPT:-$PROMPT}"
  SIZE="${CITYLING_DASHSCOPE_SIZE:-$SIZE}"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1"
    exit 1
  fi
}

require_cmd curl
require_cmd jq

if [[ -z "$DASHSCOPE_API_KEY" ]]; then
  echo "缺少 DashScope Key，请设置 CITYLING_DASHSCOPE_API_KEY"
  exit 1
fi

if [[ "$IMAGE_INPUT" != http* ]]; then
  echo "当前脚本仅支持公网 image URL 输入"
  exit 1
fi

mkdir -p "$OUT_DIR"
tmp_req="$(mktemp)"
tmp_resp="$(mktemp)"
trap 'rm -f "$tmp_req" "$tmp_resp"' EXIT

jq -n \
  --arg model "$DASHSCOPE_MODEL" \
  --arg prompt "$PROMPT" \
  --arg image "$IMAGE_INPUT" \
  --arg size "$SIZE" \
  '{
    model: $model,
    input: {
      messages: [
        {
          role: "user",
          content: [
            {text: $prompt},
            {image: $image}
          ]
        }
      ]
    },
    parameters: {
      prompt_extend: true,
      watermark: false,
      n: 1,
      enable_interleave: false,
      size: $size
    }
  }' >"$tmp_req"

echo "POST $DASHSCOPE_API_URL"
echo "model=$DASHSCOPE_MODEL"
echo "image_input=$IMAGE_INPUT"

metrics="$(
  curl -sS -o "$tmp_resp" \
    -w "%{http_code},%{time_total},%{time_starttransfer}" \
    -X POST "$DASHSCOPE_API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
    --data-binary "@$tmp_req"
)"

http_code="$(echo "$metrics" | cut -d',' -f1)"
time_total="$(echo "$metrics" | cut -d',' -f2)"
time_ttfb="$(echo "$metrics" | cut -d',' -f3)"
cp "$tmp_resp" "$OUT_FILE"

echo "HTTP $http_code"
echo "time_total=${time_total}s ttfb=${time_ttfb}s"
echo "response_file=$OUT_FILE"

if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  echo "请求失败，响应体："
  cat "$tmp_resp"
  exit 1
fi

image_url="$(jq -r '
  (
    .output.choices[0].message.content[]? | select(type=="object") | .image? // empty
  ),
  .output.images[]?,
  .output.results[]?.url?,
  .output.results[]?.image?,
  .output.image?,
  .data[0].url?
' "$tmp_resp" | awk 'NF{print; exit}')"
b64_len="$(jq -r '(.data[0].b64_json // "") | length' "$tmp_resp")"

echo "image_url=${image_url:-<empty>}"
echo "b64_length=$b64_len"

if [[ -z "$image_url" && "$b64_len" -le 0 ]]; then
  echo "FAIL: 响应中未找到可用图片字段"
  cat "$tmp_resp"
  exit 2
fi

echo "PASS: DashScope 图生图请求成功"
