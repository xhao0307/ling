#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  scripts/codex-loop.sh <次数> [选项]

说明:
  循环调用 Codex 执行开发任务，每轮写日志，并在需要时自动补一次 commit。

参数:
  <次数>                         循环次数，必须是正整数

选项:
  --runner <执行器>              codex | claude（默认 codex）
  --prompt-file <文件>           使用外部 prompt 文件
  --approval-mode <模式>         codex: suggest | auto-edit | full-auto（默认 full-auto）
  --claude-permission-mode <模式> claude: default | acceptEdits | bypassPermissions | dontAsk ...（默认 bypassPermissions）
  --dangerous                    codex: --dangerously-auto-approve-everything；claude: --dangerously-skip-permissions
  --model <模型>                 透传给执行器 --model（默认 codex 为 gpt-5.2-codex）
  --provider <提供方>            仅 codex 生效（默认 openai）
  --log-dir <目录>               日志目录（默认 .codex-loop-logs）
  --continue-on-error            单轮失败后继续下一轮
  --allow-dirty-start            允许在非干净工作区启动（默认不允许）
  --dry-run                      仅打印将执行的命令，不实际调用 codex
  -h, --help                     显示帮助

示例:
  scripts/codex-loop.sh 5
  scripts/codex-loop.sh 3 --approval-mode full-auto --prompt-file prompts/loop.txt
  scripts/codex-loop.sh 10 --dangerous --continue-on-error
  scripts/codex-loop.sh 2 --runner claude --model sonnet
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "缺少命令: $1"
    exit 1
  fi
}

is_positive_int() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

default_prompt() {
  cat <<'EOF'
你是 Codex。请在当前仓库执行一次“单功能增量开发”会话，并严格遵循 AGENTS.md。

硬性要求：
1. 先读取 agent-progress.md 与 feature_list.json。
2. 只选择 1 个最高优先级且 passes=false 的功能项推进（不可并行多个大项）。
3. 完成实现 + 验证（至少给出端到端或关键命令验证结果）。
4. 仅在验证通过后把该功能 passes 改为 true；若失败，明确记录阻塞与复现步骤。
5. 更新 agent-progress.md，写清本轮改动、验证、风险、下一步。
6. 进行 git 提交（commit message 需包含 feature id）。

输出结尾请包含：
- 本轮 feature id
- 是否验证通过
- commit hash
EOF
}

auto_commit_if_needed() {
  local iter="$1"
  local total="$2"
  local log_file="$3"
  local log_root="$4"

  if git diff --quiet && git diff --cached --quiet; then
    return 0
  fi

  git add -A
  # 避免把循环日志目录纳入自动提交。
  git reset -q -- "$log_root" >/dev/null 2>&1 || true
  if git diff --cached --quiet; then
    return 0
  fi

  local msg
  msg="chore(codex-loop): iteration ${iter}/${total} auto-commit"
  if git commit -m "$msg" >>"$log_file" 2>&1; then
    log "检测到未提交改动，已自动补提交通知: $msg"
  else
    log "自动补提交失败，请手动检查 git 状态"
    return 1
  fi
}

context_failed_by_output() {
  local log_file="$1"
  # 某些 codex 失败场景会返回 0，但输出里有明确错误，需要主动识别。
  if grep -Eiq 'OpenAI rejected the request|Network error while contacting OpenAI|ERROR Raw mode is not supported|Status:[[:space:]]*404|Status:[[:space:]]*403|Client not allowed' "$log_file"; then
    return 0
  fi
  return 1
}

print_error_hint_if_known() {
  local log_file="$1"
  local model="$2"
  if grep -Eiq 'Status:[[:space:]]*403|Client not allowed' "$log_file"; then
    log "提示: 检测到 403 Client not allowed，通常是模型权限问题。"
    log "提示: 当前模型为 ${model}，请改用有权限模型或向网关开通该模型权限。"
  fi
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COUNT="$1"
shift

if ! is_positive_int "$COUNT"; then
  log "错误: <次数> 必须是正整数，当前为: $COUNT"
  exit 1
fi

# API Key 默认值（可通过环境变量 CODEX_API_KEY 覆盖）
# 说明：仅用于本机自动化，避免每次手动输入。
DEFAULT_CODEX_API_KEY="cr_2b076919e75b5571406cc5685effbb3ece417a55cdae4c7215699ae01299837a"
DEFAULT_CODEX_BASE_URL="https://apikey.soxio.me/openai/v1"
DEFAULT_CODEX_MODEL="gpt-5.2-codex"
DEFAULT_CLAUDE_MODEL="sonnet"

RUNNER="codex"
PROMPT_FILE=""
APPROVAL_MODE="full-auto"
CLAUDE_PERMISSION_MODE="bypassPermissions"
DANGEROUS=false
MODEL=""
PROVIDER="openai"
LOG_ROOT=".codex-loop-logs"
CONTINUE_ON_ERROR=false
ALLOW_DIRTY_START=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runner)
      RUNNER="${2:-}"
      shift 2
      ;;
    --prompt-file)
      PROMPT_FILE="${2:-}"
      shift 2
      ;;
    --approval-mode)
      APPROVAL_MODE="${2:-}"
      shift 2
      ;;
    --claude-permission-mode)
      CLAUDE_PERMISSION_MODE="${2:-}"
      shift 2
      ;;
    --dangerous)
      DANGEROUS=true
      shift
      ;;
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --log-dir)
      LOG_ROOT="${2:-}"
      shift 2
      ;;
    --continue-on-error)
      CONTINUE_ON_ERROR=true
      shift
      ;;
    --allow-dirty-start)
      ALLOW_DIRTY_START=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "未知参数: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -n "$PROMPT_FILE" && ! -f "$PROMPT_FILE" ]]; then
  log "prompt 文件不存在: $PROMPT_FILE"
  exit 1
fi

case "$RUNNER" in
  codex|claude) ;;
  *)
    log "runner 非法: $RUNNER（可选: codex|claude）"
    exit 1
    ;;
esac

case "$APPROVAL_MODE" in
  suggest|auto-edit|full-auto) ;;
  *)
    log "approval mode 非法: $APPROVAL_MODE（可选: suggest|auto-edit|full-auto）"
    exit 1
    ;;
esac

require_cmd git
require_cmd tee
if [[ "$RUNNER" == "codex" ]]; then
  require_cmd codex
else
  require_cmd claude
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "当前目录不是 git 仓库"
  exit 1
fi

if [[ "$RUNNER" == "codex" ]]; then
  CODEX_API_KEY="${CODEX_API_KEY:-$DEFAULT_CODEX_API_KEY}"
  if [[ -z "$CODEX_API_KEY" ]]; then
    log "API key 为空，请设置 CODEX_API_KEY 或修改脚本内默认值"
    exit 1
  fi
  CODEX_BASE_URL="${CODEX_BASE_URL:-$DEFAULT_CODEX_BASE_URL}"
  if [[ -z "$CODEX_BASE_URL" ]]; then
    log "BASE URL 为空，请设置 CODEX_BASE_URL 或修改脚本内默认值"
    exit 1
  fi
  if [[ -z "$MODEL" ]]; then
    MODEL="${CODEX_MODEL:-$DEFAULT_CODEX_MODEL}"
  fi

  # 与 ~/.codex/config.toml 中 env_key = "CRS_OAI_KEY" 对齐，确保走 API Key 模式。
  export CRS_OAI_KEY="$CODEX_API_KEY"
  # 兼容 codex CLI 的 API key 读取逻辑，避免出现交互式登录提示。
  export OPENAI_API_KEY="$CODEX_API_KEY"
  export OPENAI_BASE_URL="$CODEX_BASE_URL"
else
  if [[ -z "$MODEL" ]]; then
    MODEL="${CLAUDE_MODEL:-$DEFAULT_CLAUDE_MODEL}"
  fi
fi

if [[ "$ALLOW_DIRTY_START" != true ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    log "检测到未提交改动。为避免自动提交混入无关变更，默认拒绝启动。"
    log "若确认继续，请加参数: --allow-dirty-start"
    exit 1
  fi
fi

if [[ -n "$PROMPT_FILE" ]]; then
  BASE_PROMPT="$(cat "$PROMPT_FILE")"
else
  BASE_PROMPT="$(default_prompt)"
fi

RUN_ID="$(date '+%Y%m%d_%H%M%S')"
RUN_DIR="${LOG_ROOT%/}/${RUN_ID}"
mkdir -p "$RUN_DIR"

log "开始执行 codex 循环，共 ${COUNT} 轮"
log "日志目录: $RUN_DIR"
log "approval_mode: $APPROVAL_MODE, dangerous: $DANGEROUS, dry_run: $DRY_RUN"
log "runner: $RUNNER"
if [[ "$RUNNER" == "codex" ]]; then
  log "provider: $PROVIDER, auth: apikey(CRS_OAI_KEY/OPENAI_API_KEY), base_url: $CODEX_BASE_URL"
else
  log "claude_permission_mode: $CLAUDE_PERMISSION_MODE"
fi
log "model: $MODEL"

for ((i=1; i<=COUNT; i++)); do
  ITER_TAG="$(printf '%03d' "$i")"
  ITER_LOG="${RUN_DIR}/iter_${ITER_TAG}.log"
  ITER_PROMPT_FILE="${RUN_DIR}/iter_${ITER_TAG}.prompt.txt"
  BEFORE_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo 'none')"

  cat >"$ITER_PROMPT_FILE" <<EOF
${BASE_PROMPT}

[循环执行上下文]
- iteration: ${i}/${COUNT}
- run_id: ${RUN_ID}
- 当前分支: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
- 目标: 从任务清单中推进一个“可验证、可提交”的增量。
EOF

  if [[ "$RUNNER" == "codex" ]]; then
    CMD=(codex -q --approval-mode "$APPROVAL_MODE" --full-stdout)
    if [[ -n "$MODEL" ]]; then
      CMD+=(--model "$MODEL")
    fi
    if [[ -n "$PROVIDER" ]]; then
      CMD+=(--provider "$PROVIDER")
    fi
    if [[ "$DANGEROUS" == true ]]; then
      CMD+=(--dangerously-auto-approve-everything)
    fi
  else
    CMD=(claude -p --output-format text --permission-mode "$CLAUDE_PERMISSION_MODE")
    if [[ -n "$MODEL" ]]; then
      CMD+=(--model "$MODEL")
    fi
    if [[ "$DANGEROUS" == true ]]; then
      CMD+=(--dangerously-skip-permissions)
    fi
  fi

  log "第 ${i}/${COUNT} 轮开始，执行前 HEAD=${BEFORE_HEAD}"
  log "本轮日志: $ITER_LOG"

  if [[ "$DRY_RUN" == true ]]; then
    {
      echo "DRY_RUN=true"
      echo "COMMAND: ${CMD[*]} \"<prompt from $ITER_PROMPT_FILE>\""
    } | tee -a "$ITER_LOG"
    CONTEXT_EXIT=0
  else
    set +e
    "${CMD[@]}" "$(cat "$ITER_PROMPT_FILE")" 2>&1 | tee "$ITER_LOG"
    CONTEXT_EXIT=${PIPESTATUS[0]}
    set -e
    if context_failed_by_output "$ITER_LOG"; then
      CONTEXT_EXIT=1
      log "第 ${i}/${COUNT} 轮检测到模型返回错误（日志关键字命中），按失败处理"
      if [[ "$RUNNER" == "codex" ]]; then
        print_error_hint_if_known "$ITER_LOG" "$MODEL"
      fi
    fi
  fi

  if [[ "$CONTEXT_EXIT" -ne 0 ]]; then
    log "第 ${i}/${COUNT} 轮失败，退出码=${CONTEXT_EXIT}"
    if [[ "$CONTINUE_ON_ERROR" != true ]]; then
      log "未启用 --continue-on-error，流程终止"
      exit "$CONTEXT_EXIT"
    fi
  fi

  if [[ "$DRY_RUN" != true && "$CONTEXT_EXIT" -eq 0 ]]; then
    auto_commit_if_needed "$i" "$COUNT" "$ITER_LOG" "$LOG_ROOT" || {
      if [[ "$CONTINUE_ON_ERROR" != true ]]; then
        exit 1
      fi
    }
  fi

  AFTER_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo 'none')"
  LAST_COMMIT="$(git log -1 --pretty=format:'%h %s' 2>/dev/null || echo 'no-commit')"
  log "第 ${i}/${COUNT} 轮结束，执行后 HEAD=${AFTER_HEAD}"
  log "最近提交: ${LAST_COMMIT}"
done

log "全部执行完成，共 ${COUNT} 轮"
