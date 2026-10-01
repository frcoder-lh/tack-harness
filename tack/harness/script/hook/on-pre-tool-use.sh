#!/bin/sh
# on-pre-tool-use.sh — TRAE/Claude Code PreToolUse hook（tack 边界层，接口预留）
#
# 当前状态：观察模式（observe）——默认零输出、零拦截、零磁盘写入，对会话行为
# 没有任何影响，只用于在未来启用强制前，以真实 payload 校准工具名与命令形态。
#
# 模式开关（环境变量，在 hooks.json 的 command 或会话环境中设置）：
#   TACK_HOOK_LOG=1      观察日志：命令类工具调用与命中的边界规则追加到
#                        $root/.tack/log/hook-observe.log（探针用途，确认 RunCommand/Bash
#                        等真实工具名与 tool_input 形态）
#   TACK_HOOK_ENFORCE=1  【预留，暂不要启用】对命中规则的调用输出 deny JSON 阻断；
#                        未设置时即使命中规则也只记录、不拦截
#
# 预留的边界规则（判定逻辑已就位，与 AGENTS.md / git-boundary.md 软约束同源）：
#   R1  Git 双层边界：在 $root 下但不在 $root/space/、$root/repo/ 内执行 git 写操作
#        （commit/push/merge/rebase/reset/checkout -b/branch -D/tag/stash drop 等）；
#        经 sh 调用 harness/script 框架脚本（space.sh / branch-op.sh 等）一律放行
#   R2  强推：git push 带 --force（--force-with-lease 记为 R2L，branch-op 有授权双验）
#   R3  跳过钩子：git 命令带 --no-verify / --no-hooks
#
# stdin: PreToolUse 事件 JSON（tool_name / tool_input.command / tool_input.cwd / cwd）
# stdout: 观察模式恒为空；ENFORCE 模式才输出 permissionDecision:deny 的 JSON

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/hook-common.sh"

PAYLOAD="$(mktemp 2>/dev/null)" || exit 0
trap 'rm -f "$PAYLOAD"' EXIT HUP INT TERM
cat > "$PAYLOAD" 2>/dev/null || true

TOOL_NAME="$(hook_json_get tool_name "$PAYLOAD")"
CWD="$(hook_json_get cwd "$PAYLOAD")"
[ -n "$CWD" ] || CWD="${TRAE_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"

ROOT="$(hook_detect_root "$CWD" 2>/dev/null)" || exit 0
[ -n "$ROOT" ] || exit 0

# 只观察命令执行类工具（TRAE 实测工具名为 RunCommand，Claude Code 为 Bash；
# 真实形态以 TACK_HOOK_LOG 探针记录为准）；其余工具一律放行
case "$TOOL_NAME" in
    RunCommand|Bash) ;;
    *) exit 0 ;;
esac

CMD="$(hook_json_get command "$PAYLOAD")"
# tool_input.cwd 与顶层 cwd 同名（顶层在前），取第 2 个；缺失时回退顶层 cwd
CMD_CWD="$(hook_json_get cwd "$PAYLOAD" 2 2>/dev/null || true)"
[ -n "$CMD_CWD" ] || CMD_CWD="$CWD"
CMD_CWD="$(printf '%s' "$CMD_CWD" | tr '\\' '/')"
ROOT_N="$(printf '%s' "$ROOT" | tr '\\' '/')"

# ── 规则判定（命中即向 stdout 追加一行 RULE<TAB>原因；纯函数式收集） ──────────
HITS=""

# 归一化命令用于匹配（小写判定，原始命令保留给日志）
CMD_LC="$(printf '%s' "$CMD" | tr 'A-Z' 'a-z')"

is_git_write() {
    # R1 前置：命令行中出现 git 写动词（允许前置 shell 连接符/空白；
    # git 与动词间允许直接相邻「git commit」或夹带选项「git -C dir commit」）
    printf '%s' "$CMD_LC" | grep -Eq '(^|[;&|()[:space:]])git[[:space:]](.*[[:space:]])?(commit|push|merge|rebase|reset|stash)([[:space:]]|$)' \
        || printf '%s' "$CMD_LC" | grep -Eq '(^|[;&|()[:space:]])git[[:space:]](.*[[:space:]])?(checkout[[:space:]]+-b|branch[[:space:]]+-d|tag[[:space:]])'
}

is_framework_script() {
    # 框架托管操作：经 sh/bash 调用 harness/script 下脚本（含 space.sh 自动提交等）
    printf '%s' "$CMD_LC" | grep -Eq '(^|[;&|()[:space:]])(sh|bash)([[:space:]]+[^;&|]*)?harness/script/'
}

# R1：双层边界（仅判定位置 + git 写；框架脚本豁免）
if is_git_write && ! is_framework_script; then
    case "$CMD_CWD" in
        "$ROOT_N"/space/*|"$ROOT_N"/repo/*) : ;;   # 合法位置：工作区代码仓库 / 只读主仓库周边
        "$ROOT_N"|"$ROOT_N"/*)
            HITS="$HITS
R1	在空间根目录保护区（\$root 下且不在 space/、repo/ 内）执行 git 写操作，违反 Git 双层边界；用户 git 只允许作用于 \$work/repo/<repo>/，空间仓库由 space.sh 托管"
            ;;
    esac
fi

# R2 / R2L：强推
if printf '%s' "$CMD_LC" | grep -Eq '(^|[;&|()[:space:]])git[[:space:]].*push([[:space:]]|=).*--force-with-lease([[:space:]]=|$|[[:space:]])'; then
    HITS="$HITS
R2L	git push --force-with-lease：仅 branch-op 工作流在用户当次授权 + 环境变量双验证下允许"
elif printf '%s' "$CMD_LC" | grep -Eq '(^|[;&|()[:space:]])git[[:space:]].*push([[:space:]]|=).*--force([[:space:]]|=|$)'; then
    HITS="$HITS
R2	git push --force 被禁止（fast-forward 安全模型，严禁 force push）"
fi

# R3：跳过钩子
if printf '%s' "$CMD_LC" | grep -Eq -- '--no-verify|--no-hooks'; then
    HITS="$HITS
R3	Git 命令不得使用 --no-verify / --no-hooks 跳过钩子"
fi

# ── 输出策略 ─────────────────────────────────────────────────────────────────
ENFORCE=0
[ "${TACK_HOOK_ENFORCE:-}" = "1" ] && ENFORCE=1
LOG=0
[ "${TACK_HOOK_LOG:-}" = "1" ] && LOG=1

# JSON 字符串转义（仅 ENFORCE 路径使用）
json_esc() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\r\t' '   '
}

# 去掉前导空行
HITS="$(printf '%s' "$HITS" | sed '/^[[:space:]]*$/d')"

if [ "$LOG" -eq 1 ]; then
    LOGF="$ROOT/.tack/log/hook-observe.log"
    mkdir -p "$ROOT/.tack/log" 2>/dev/null || true
    TS="$(date '+%Y-%m-%d %H:%M:%S')"
    ONELINE="$(printf '%s' "$CMD" | tr '\n\r\t' '   ' | sed 's/  */ /g' | cut -c1-200)"
    {
        if [ -n "$HITS" ]; then
            printf '%s\t%s\t%s\t%s\n' "$TS" "$TOOL_NAME" "$CMD_CWD" "$ONELINE" >> "$LOGF"
            printf '%s\n' "$HITS" | while IFS='	' read -r rid reason; do
                [ -n "$rid" ] && printf '%s\t  HIT %s\t%s\n' "$TS" "$rid" "$reason" >> "$LOGF"
            done
        else
            printf '%s\tprobe\t%s\t%s\t%s\n' "$TS" "$TOOL_NAME" "$CMD_CWD" "$ONELINE" >> "$LOGF"
        fi
    } 2>/dev/null || true
fi

# 预留：强制拦截（当前默认不可达；启用前必须先用 LOG 探针校准误判）
if [ "$ENFORCE" -eq 1 ] && [ -n "$HITS" ]; then
    REASON="$(printf '%s\n' "$HITS" | sed 's/^R[0-9L]*[[:space:]]*//' | sed '/^[[:space:]]*$/d' \
        | awk 'NR>1 { printf "；" } { printf "%s", $0 } END { if (NR > 0) printf "\n" }')"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"[tack:hook] %s"}}\n' \
        "$(json_esc "$REASON")"
fi

exit 0
