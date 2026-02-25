#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_API_BASE_URL="${CITYLING_IMAGE_API_BASE_URL:-https://api-image.charaboard.com}"
IMAGE_API_KEY="${CITYLING_IMAGE_API_KEY:-${CITYLING_LLM_API_KEY:-}}"
IMAGE_MODEL="${CITYLING_IMAGE_MODEL:-seedream-4-0-250828}"
APP_ID="${CITYLING_LLM_APP_ID:-4}"
PLATFORM_ID="${CITYLING_LLM_PLATFORM_ID:-5}"
MAX_TIME="${CITYLING_IMAGE_MAX_TIME:-60}"
CONNECT_TIMEOUT="${CITYLING_IMAGE_CONNECT_TIMEOUT:-10}"
CURL_MAX_TIME="${CITYLING_IMAGE_CURL_MAX_TIME:-120}"
REQUESTS="${CITYLING_IMAGE_BENCH_REQUESTS:-5}"
IMAGE_INPUT="${1:-}"
PROMPT="${CITYLING_IMAGE_PROMPT:-基于参考图生成儿童向二次元拟人角色，保留主体特征与配色，明亮柔和插画风。}"
OUT_DIR="${CITYLING_IMAGE_TEST_OUT_DIR:-$ROOT_DIR/test_screenshots}"
OUT_FILE="$OUT_DIR/image_i2i_bench_$(date +%Y%m%d_%H%M%S).csv"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
  set +a
  IMAGE_API_BASE_URL="${CITYLING_IMAGE_API_BASE_URL:-$IMAGE_API_BASE_URL}"
  IMAGE_API_KEY="${CITYLING_IMAGE_API_KEY:-${CITYLING_LLM_API_KEY:-$IMAGE_API_KEY}}"
  IMAGE_MODEL="${CITYLING_IMAGE_MODEL:-$IMAGE_MODEL}"
  APP_ID="${CITYLING_LLM_APP_ID:-$APP_ID}"
  PLATFORM_ID="${CITYLING_LLM_PLATFORM_ID:-$PLATFORM_ID}"
  MAX_TIME="${CITYLING_IMAGE_MAX_TIME:-$MAX_TIME}"
  CONNECT_TIMEOUT="${CITYLING_IMAGE_CONNECT_TIMEOUT:-$CONNECT_TIMEOUT}"
  CURL_MAX_TIME="${CITYLING_IMAGE_CURL_MAX_TIME:-$CURL_MAX_TIME}"
  REQUESTS="${CITYLING_IMAGE_BENCH_REQUESTS:-$REQUESTS}"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1"
    exit 1
  fi
}

require_cmd curl
require_cmd jq

if [[ -z "$IMAGE_INPUT" ]]; then
  echo "用法: scripts/bench-image-i2i-latency.sh <image_url_or_data_url>"
  exit 1
fi

if [[ -z "$IMAGE_API_KEY" ]]; then
  echo "缺少 API Key，请设置 CITYLING_IMAGE_API_KEY 或 CITYLING_LLM_API_KEY"
  exit 1
fi

if [[ "$REQUESTS" -le 0 ]]; then
  echo "CITYLING_IMAGE_BENCH_REQUESTS 必须 > 0"
  exit 1
fi

if [[ "$IMAGE_INPUT" != http* && "$IMAGE_INPUT" != data:image/* ]]; then
  echo "本脚本仅支持 image_url 或 data:image 输入"
  exit 1
fi

mkdir -p "$OUT_DIR"
tmp_resp="$(mktemp)"
tmp_req="$(mktemp)"
trap 'rm -f "$tmp_resp" "$tmp_req"' EXIT

jq -n \
  --arg model "$IMAGE_MODEL" \
  --arg prompt "$PROMPT" \
  --arg image "$IMAGE_INPUT" \
  '{
    model: $model,
    prompt: $prompt,
    image: $image,
    n: 1,
    response_format: "url",
    size: "2K",
    stream: false,
    watermark: false
  }' >"$tmp_req"

echo "idx,http_code,total_s,connect_s,starttransfer_s,size_download,url_nonempty,error" >"$OUT_FILE"
echo "开始测速: requests=$REQUESTS"
echo "endpoint=${IMAGE_API_BASE_URL}/v1/byteplus/images/generations"
echo "output=$OUT_FILE"

ok_count=0
for i in $(seq 1 "$REQUESTS"); do
  err_msg=""
  metrics="$(curl -sS -o "$tmp_resp" \
    -w "%{http_code},%{time_total},%{time_connect},%{time_starttransfer},%{size_download}" \
    --connect-timeout "${CONNECT_TIMEOUT}" \
    --max-time "${CURL_MAX_TIME}" \
    -X POST "${IMAGE_API_BASE_URL}/v1/byteplus/images/generations" \
    -H "Authorization: Bearer ${IMAGE_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "x-app-id: ${APP_ID}" \
    -H "x-platform-id: ${PLATFORM_ID}" \
    -H "x-max-time: ${MAX_TIME}" \
    --data-binary "@${tmp_req}")" || {
      metrics="000,${CURL_MAX_TIME},0,0,0"
      err_msg="curl_failed"
    }

  http_code="$(echo "$metrics" | cut -d',' -f1)"
  total_s="$(echo "$metrics" | cut -d',' -f2)"
  connect_s="$(echo "$metrics" | cut -d',' -f3)"
  starttransfer_s="$(echo "$metrics" | cut -d',' -f4)"
  size_download="$(echo "$metrics" | cut -d',' -f5)"

  url_nonempty="0"
  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    if jq -e '.data[0].url | select(type=="string" and length>0)' "$tmp_resp" >/dev/null 2>&1; then
      url_nonempty="1"
      ok_count=$((ok_count + 1))
    else
      err_msg="empty_url"
    fi
  elif [[ -z "$err_msg" ]]; then
    err_msg="http_${http_code}"
  fi

  echo "${i},${http_code},${total_s},${connect_s},${starttransfer_s},${size_download},${url_nonempty},${err_msg}" >>"$OUT_FILE"
  echo "[$i/$REQUESTS] code=$http_code total=${total_s}s ttfb=${starttransfer_s}s url_ok=$url_nonempty"
done

requests_count="$(awk -F',' 'NR>1 {count++} END {print count+0}' "$OUT_FILE")"
ok_count_csv="$(awk -F',' 'NR>1 && $7=="1" {count++} END {print count+0}' "$OUT_FILE")"
avg_total="$(awk -F',' 'NR>1 {sum+=$3; c++} END {if (c==0) print "0"; else printf "%.3f", sum/c}' "$OUT_FILE")"

sorted_tmp="$(mktemp)"
trap 'rm -f "$tmp_resp" "$tmp_req" "$sorted_tmp"' EXIT
awk -F',' 'NR>1 {print $3}' "$OUT_FILE" | sort -n >"$sorted_tmp"

min_total="$(sed -n '1p' "$sorted_tmp")"
max_total="$(tail -n 1 "$sorted_tmp")"
p50_idx=$(( (requests_count + 1) / 2 ))
p95_idx=$(( (requests_count * 95 + 99) / 100 ))
if [[ "$p95_idx" -lt 1 ]]; then
  p95_idx=1
fi
p50_total="$(sed -n "${p50_idx}p" "$sorted_tmp")"
p95_total="$(sed -n "${p95_idx}p" "$sorted_tmp")"

if [[ -z "$min_total" ]]; then min_total="0"; fi
if [[ -z "$max_total" ]]; then max_total="0"; fi
if [[ -z "$p50_total" ]]; then p50_total="0"; fi
if [[ -z "$p95_total" ]]; then p95_total="0"; fi

success_rate="$(awk -v ok="$ok_count_csv" -v total="$requests_count" 'BEGIN { if (total==0) print "0.00"; else printf "%.2f", (ok*100.0)/total }')"
summary="requests=${requests_count} success=${ok_count_csv} success_rate=${success_rate}% avg=${avg_total}s min=${min_total}s p50=${p50_total}s p95=${p95_total}s max=${max_total}s"

echo "$summary"
echo "测速明细已保存: $OUT_FILE"

if [[ "$ok_count" -eq 0 ]]; then
  echo "FAIL: 没有成功返回可用 URL 的请求"
  exit 2
fi

echo "PASS: 图生图接口测速完成"
