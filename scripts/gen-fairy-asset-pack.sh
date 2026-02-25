#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN_FILE="${CITYLING_FAIRY_ASSET_PLAN:-$ROOT_DIR/design/illustration/asset_generation_plan.json}"
REF_IMAGE="${1:-}"
OUT_DIR="${CITYLING_FAIRY_OUT_DIR:-$ROOT_DIR/flutter_client/assets/fairy/illustrations}"
RAW_DIR="$OUT_DIR/raw"
INDEX_FILE="$OUT_DIR/index.json"

if [[ -z "$REF_IMAGE" ]]; then
  echo "用法: scripts/gen-fairy-asset-pack.sh <参考图URL或本地路径>"
  exit 1
fi

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

IMAGE_API_BASE_URL="${CITYLING_IMAGE_API_BASE_URL:-https://api-image.charaboard.com}"
IMAGE_API_KEY="${CITYLING_IMAGE_API_KEY:-${CITYLING_LLM_API_KEY:-}}"
IMAGE_MODEL="${CITYLING_IMAGE_MODEL:-seedream-4-0-250828}"
IMAGE_RESPONSE_FORMAT="${CITYLING_IMAGE_RESPONSE_FORMAT:-b64_json}"
APP_ID="${CITYLING_LLM_APP_ID:-4}"
PLATFORM_ID="${CITYLING_LLM_PLATFORM_ID:-5}"
MAX_TIME="${CITYLING_IMAGE_MAX_TIME:-60}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "缺少命令: $1"; exit 1; }
}

need_cmd curl
need_cmd jq
need_cmd base64

if [[ -z "$IMAGE_API_KEY" ]]; then
  echo "缺少 API Key，请在 .env 或环境变量中设置 CITYLING_IMAGE_API_KEY / CITYLING_LLM_API_KEY"
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "计划文件不存在: $PLAN_FILE"
  exit 1
fi

encode_base64() {
  if base64 --help 2>/dev/null | grep -q -- "-w"; then
    base64 -w 0 "$1"
  else
    base64 <"$1" | tr -d '\n'
  fi
}

decode_base64_to_file() {
  local b64="$1"
  local out="$2"
  if base64 --help 2>/dev/null | grep -q -- "-d"; then
    printf '%s' "$b64" | base64 -d >"$out"
  else
    printf '%s' "$b64" | base64 -D >"$out"
  fi
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
    echo "参考图不存在: $input" >&2
    exit 1
  fi
  local ext mime b64
  ext="${input##*.}"
  ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    png) mime="image/png" ;;
    jpg|jpeg) mime="image/jpeg" ;;
    webp) mime="image/webp" ;;
    *) mime="image/jpeg" ;;
  esac
  b64="$(encode_base64 "$input")"
  echo "data:${mime};base64,${b64}"
}

mkdir -p "$OUT_DIR" "$RAW_DIR"
ref_payload="$(build_image_ref "$REF_IMAGE")"
base_prompt="$(jq -r '.base_prompt // ""' "$PLAN_FILE")"

items_tmp="$(mktemp)"
trap 'rm -f "$items_tmp"' EXIT

echo "开始批量生成资源..."
echo "model=$IMAGE_MODEL response_format=$IMAGE_RESPONSE_FORMAT"

while IFS= read -r item; do
  id="$(jq -r '.id' <<<"$item")"
  category="$(jq -r '.category // "misc"' <<<"$item")"
  prompt_local="$(jq -r '.prompt // ""' <<<"$item")"
  size="$(jq -r '.size // "2K"' <<<"$item")"
  prompt="${base_prompt} ${prompt_local}"

  req_file="$(mktemp)"
  resp_file="$RAW_DIR/${id}.json"

  jq -n \
    --arg model "$IMAGE_MODEL" \
    --arg prompt "$prompt" \
    --arg image "$ref_payload" \
    --arg response_format "$IMAGE_RESPONSE_FORMAT" \
    --arg size "$size" \
    '{model:$model,prompt:$prompt,image:$image,n:1,response_format:$response_format,size:$size,stream:false,watermark:true}' >"$req_file"

  code="$({
    curl -sS -o "$resp_file" -w "%{http_code}" \
      -X POST "${IMAGE_API_BASE_URL}/v1/byteplus/images/generations" \
      -H "Authorization: Bearer ${IMAGE_API_KEY}" \
      -H "Content-Type: application/json" \
      -H "x-app-id: ${APP_ID}" \
      -H "x-platform-id: ${PLATFORM_ID}" \
      -H "x-max-time: ${MAX_TIME}" \
      --data-binary "@${req_file}"
  })"

  rm -f "$req_file"

  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    echo "[$id] 失败 HTTP $code"
    jq -nc --arg id "$id" --arg category "$category" --arg status "failed" --arg http_code "$code" \
      '{id:$id,category:$category,status:$status,http_code:$http_code}' >>"$items_tmp"
    continue
  fi

  b64="$(jq -r '.data[0].b64_json // ""' "$resp_file")"
  url="$(jq -r '.data[0].url // ""' "$resp_file")"
  out_png="$OUT_DIR/${id}.png"

  if [[ -n "$b64" ]]; then
    decode_base64_to_file "$b64" "$out_png" || true
  elif [[ -n "$url" ]]; then
    curl -sS "$url" -o "$out_png" || true
  fi

  if [[ -f "$out_png" ]]; then
    echo "[$id] 生成成功 -> $out_png"
    jq -nc \
      --arg id "$id" \
      --arg category "$category" \
      --arg status "ok" \
      --arg file "${out_png#$ROOT_DIR/}" \
      --arg url "$url" \
      '{id:$id,category:$category,status:$status,file:$file,url:$url}' >>"$items_tmp"
  else
    echo "[$id] 响应成功但未产出图片文件"
    jq -nc --arg id "$id" --arg category "$category" --arg status "empty" --arg url "$url" \
      '{id:$id,category:$category,status:$status,url:$url}' >>"$items_tmp"
  fi

done < <(jq -c '.assets[]' "$PLAN_FILE")

jq -s \
  --arg generated_at "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
  --arg reference_image "$REF_IMAGE" \
  --arg plan_file "${PLAN_FILE#$ROOT_DIR/}" \
  '{generated_at:$generated_at,reference_image:$reference_image,plan_file:$plan_file,items:.}' \
  "$items_tmp" >"$INDEX_FILE"

echo "完成。索引文件: ${INDEX_FILE#$ROOT_DIR/}"
