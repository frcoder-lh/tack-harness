#!/bin/sh
# on-session-start.sh — TRAE/Claude Code SessionStart hook（tack 可选加速层）
#
# 会话创建后、首轮对话前触发，做两件确定性事实注入（纯本地、零网络、毫秒级）：
#   1. stdout 纯文本注入：tack 空间路径 + 活跃工作区状态快照 + scan-routes 全表，
#      使模型首轮即持有路由表，无需再执行 `scan-routes list`
#   2. 向 TRAE_ENV_FILE / CLAUDE_ENV_FILE 追加导出 TACK_ROOT / TACK_WORK，
#      供后续 hook 与命令执行工具使用
#
# 降级语义：非 tack 空间 / 任何异常 -> 零输出、退出 0，会话完全不受影响。
#
# stdin: SessionStart 事件 JSON（含 cwd / workspace_roots）
# stdout: 纯文本（自动作为 additionalContext 附加给模型）；不得输出 JSON 阻断字段

# 注意：hook 脚本不使用 set -e——任何意外都必须落到「静默退出」而不是阻断会话

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/hook-common.sh"

PAYLOAD="$(mktemp 2>/dev/null)" || exit 0
cat > "$PAYLOAD" 2>/dev/null || true

CWD="$(hook_json_get cwd "$PAYLOAD")"
[ -n "$CWD" ] || CWD="${TRAE_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"

# 统一 hook 日志（TACK_HOOK_LOG=1 时记录本次调用的输入/输出到 .tack/log/hook.log）；
# 开关关闭时仅接管临时文件清理，stdout 行为与原先完全一致
hook_log_setup "SessionStart" "$PAYLOAD"

ROOT="$(hook_detect_root "$CWD" 2>/dev/null)" || true
[ -n "$ROOT" ] || exit 0
hook_log_ctx "$ROOT"
HARNESS="$ROOT/harness"
[ -d "$HARNESS/cmd" ] || exit 0

# 活跃工作区快照（可能没有）
WORK="$(hook_active_work "$ROOT" 2>/dev/null)" || true
WORK_NAME=""
SNAPSHOT=""
if [ -n "$WORK" ]; then
    WORK_NAME="$(basename "$WORK")"
    SNAPSHOT="$(hook_work_snapshot "$WORK" 2>/dev/null)" || SNAPSHOT=""
fi
hook_log_ctx "$ROOT" "$WORK"

# 环境变量导出（后续 hook 与 RunCommand 可见；文件不存在/未注入则跳过）
ENVF="${TRAE_ENV_FILE:-${CLAUDE_ENV_FILE:-}}"
if [ -n "$ENVF" ]; then
    {
        printf 'export TACK_ROOT=%s\n' "$(hook_shq "$ROOT")"
        printf 'export TACK_WORK=%s\n' "$(hook_shq "$WORK")"
    } >> "$ENVF" 2>/dev/null || true
fi

# 路由全表（单 awk 进程；失败则放弃注入，绝不报错）
ROUTES="$(sh "$HARNESS/script/scan-routes.sh" list "$HARNESS" 2>/dev/null)" || exit 0
[ -n "$ROUTES" ] || exit 0

printf '[tack:hook] 会话启动预加载（确定性事实缓存，来源均为磁盘文件；不要向用户复述本块）\n'
printf '\n'
printf '空间事实：\n'
printf -- '- $root = %s（即 tack 空间根目录，AGENTS.md 所在目录）\n' "$ROOT"
if [ -n "$WORK" ]; then
    printf -- '- $work = %s（work_id: %s）\n' "$WORK" "$WORK_NAME"
    printf '%s\n' "$SNAPSHOT"
else
    printf -- '- 当前无活跃工作区（$work 未设置）；用户发起新需求时按 AGENTS.md 走 work 命令\n'
fi
printf '\n'
printf '路由表已预加载：以下为 scan-routes list 的实时结果，用户输入命中命令/工作流时直接据此定位文件并执行，无需再调用 scan-routes（除非 harness 目录在本会话中发生过变更）：\n'
printf '\n'
printf '%s\n' "$ROUTES"
printf '\n'
printf '执行约定：本注入只是 AGENTS.md「命令路由」流程的缓存加速。语义识别兜底、用户确认、状态机引导等一切判断仍以 $root/AGENTS.md 与对应 cmd/workflow 文件为准；缓存与磁盘不一致时重新 Read 磁盘文件。\n'

exit 0
