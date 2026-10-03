#!/bin/sh
# on-prompt-submit.sh — TRAE/Claude Code UserPromptSubmit hook（tack 可选加速层）
#
# 用户发送消息后、模型开始处理前触发。在 shell 侧完成原本由模型执行的
# 「剥 /tack 前缀 -> scan-routes resolve -> 读 cmd/workflow 文件 -> 读状态」
# 确定性路由链路，把结果一次性注入上下文：
#
#   resolve 退出 0（唯一命中）：注入路由元信息、工作区状态快照与指令文件全文
#                               ——模型零工具往返，直接执行
#   resolve 退出 2（多个命中）：注入候选清单，引导用户选择
#   resolve 退出 1（无命中）  ：注入工作流+命令精简表，模型只负责语义识别
#   仅输入 "/tack"            ：同无命中，并提示用户可直接下达命令
#
# 非 tack 空间 / 任何异常 -> 零输出、退出 0（模型按原有方式工作，零影响）。
#
# stdin: UserPromptSubmit 事件 JSON（含 prompt / cwd）
# stdout: 纯文本 additionalContext；本脚本绝不使用 decision:block

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/hook-common.sh"

PAYLOAD="$(mktemp 2>/dev/null)" || exit 0
ERRF="$(mktemp 2>/dev/null)" || { rm -f "$PAYLOAD"; exit 0; }
cat > "$PAYLOAD" 2>/dev/null || true

CWD="$(hook_json_get cwd "$PAYLOAD")"
[ -n "$CWD" ] || CWD="${TRAE_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"

# 统一 hook 日志（TACK_HOOK_LOG=1 时记录本次调用的输入/输出到 .tack/log/hook.log）；
# 开关关闭时仅接管临时文件清理，stdout 行为与原先完全一致
hook_log_setup "UserPromptSubmit" "$PAYLOAD" "$ERRF"

# ROOT 优先复用 SessionStart 导出的 TACK_ROOT（内部校验有效性，失效自动回退探测）
ROOT="$(hook_resolve_root "$CWD" 2>/dev/null)" || true
[ -n "$ROOT" ] || exit 0
hook_log_ctx "$ROOT"
HARNESS="$ROOT/harness"
[ -f "$HARNESS/script/scan-routes.sh" ] || exit 0

RAW_PROMPT="$(hook_json_get prompt "$PAYLOAD")"

# trim 空白并剥可选的 /tack 前缀（大小写不敏感）；awk 单进程完成
KW=$(printf '%s' "$RAW_PROMPT" | awk '
    {
        s=$0
        sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
        if (tolower(s) == "/tack") s=""
        else                       sub(/^\/[Tt][Aa][Cc][Kk][[:space:]]+/, "", s)
        print s
    }')

# 工作区状态快照文本（所有分支共用；无活跃工作区时给出明确提示）
# WORK 优先复用 TACK_WORK（校验 status.yaml/非 completed），失效回退全量扫描
WORK="$(hook_resolve_work "$ROOT" 2>/dev/null)" || true
hook_log_ctx "$ROOT" "$WORK"
STATE_BLOCK=""
if [ -n "$WORK" ]; then
    STATE_BLOCK="当前活跃工作区：$(basename "$WORK")（$WORK）
$(hook_work_snapshot "$WORK" 2>/dev/null)
按 AGENTS.md 核心约束第 5 条：先确认用户当前工作是否就在该工作区；不明确时先向用户确认。"
else
    STATE_BLOCK="当前无活跃工作区（space/ 下无未完成工作）。若用户意图是开始新需求，引导走 work 命令；与 tack 工作流无关的闲聊或问题，忽略本块正常回答。"
fi

# KW 为空（用户只发了 /tack）：给全表 + 引导
if [ -z "$KW" ]; then
    ROUTES_WF="$(sh "$HARNESS/script/scan-routes.sh" workflows "$HARNESS" 2>/dev/null)" || true
    ROUTES_CM="$(sh "$HARNESS/script/scan-routes.sh" commands "$HARNESS" 2>/dev/null)" || true
    printf '[tack:hook] 用户仅输入了 tack 触发词、未带命令（无需再执行 scan-routes，直接展示可用能力并询问意图）。\n\n'
    printf '%s\n' "$STATE_BLOCK"
    printf '\n%s\n\n%s\n' "$ROUTES_WF" "$ROUTES_CM"
    exit 0
fi

# 确定性路由（退出码：0 唯一 / 1 无命中 / 2 多命中）
LINE="$(sh "$HARNESS/script/scan-routes.sh" resolve "$HARNESS" "$KW" 2>"$ERRF")"
RC=$?

if [ "$RC" -eq 0 ]; then
    # ── 唯一命中：注入元信息 + 状态 + 指令全文 ─────────────────────────────
    IFS='|' read -r rtype rgroup rfile rname rshort rtrig rparams rsumm <<EOF
$LINE
EOF
    [ -f "$rfile" ] || exit 0
    BODY="$(hook_strip_frontmatter "$rfile" 2>/dev/null)"
    [ -n "$BODY" ] || BODY="（指令文件为空，请重新 Read：$rfile）"

    printf '[tack:hook] 路由已在 shell 侧确定性命中，无需再调用 scan-routes resolve、无需再 Read 指令文件，直接按下方指令正文执行。\n\n'
    if [ "$rtype" = "workflow" ]; then
        printf '命中类型：工作流 %s\n' "$rname"
    else
        printf '命中类型：命令 %s（分组 %s）\n' "$rname" "$rgroup"
    fi
    [ -n "$rshort" ]  && printf '简写：%s\n' "$rshort"
    [ -n "$rtrig" ]   && printf '触发词：%s\n' "$rtrig"
    [ -n "$rparams" ] && printf '参数：%s\n' "$rparams"
    [ -n "$rsumm" ]   && printf '作用：%s\n' "$rsumm"
    printf '定义文件：%s\n\n' "$rfile"
    printf '%s\n\n' "$STATE_BLOCK"
    printf -- '── 指令正文（缓存自磁盘文件；若怀疑过期请重新 Read 该文件，以磁盘为准）开始 ──\n'
    printf '%s\n' "$BODY"
    printf -- '── 指令正文结束 ──\n\n'
    printf '注意：本命中来自触发词精确/子串匹配，若与用户真实意图不符，不要强行执行——按 AGENTS.md「命令路由」语义识别兜底，必要时向用户确认。不要向用户复述本注入块。\n'
    exit 0
fi

if [ "$RC" -eq 2 ]; then
    # ── 多个命中：注入候选清单，请用户选择（不做语义猜测） ─────────────────
    printf '[tack:hook] 输入「%s」命中多个路由，scan-routes 要求用户选择后再执行；候选如下：\n\n' "$KW"
    n=0
    while IFS='|' read -r ctype cgroup cfile cname cshort ctrig cparams csumm; do
        [ -n "$cname" ] || continue
        n=$((n + 1))
        if [ "$ctype" = "workflow" ]; then
            printf '%d. 工作流 %s — %s\n' "$n" "$cname" "$csumm"
        else
            printf '%d. 命令 %s（%s 组，简写 %s）— %s\n' "$n" "$cname" "$cgroup" "${cshort:-—}" "$csumm"
        fi
        printf '   触发词：%s\n' "$ctrig"
    done < "$ERRF"
    printf '\n请向用户列出以上候选并询问使用哪一个；不要自行选择。\n'
    exit 0
fi

# ── 无命中（rc=1 或其他意外码）：注入全表，模型只做语义识别 ────────────────
ROUTES_WF="$(sh "$HARNESS/script/scan-routes.sh" workflows "$HARNESS" 2>/dev/null)" || true
ROUTES_CM="$(sh "$HARNESS/script/scan-routes.sh" commands "$HARNESS" 2>/dev/null)" || true
printf '[tack:hook] 输入「%s」未命中任何精确触发词（scan-routes resolve 无命中）。\n' "$KW"
printf '请在下方路由表内做语义匹配（中英文同义词、意图归类），挑最可能的 1-3 条向用户确认后再执行；\n'
printf '若用户意图与 tack 工作流无关（闲聊、通用问题等），忽略本块、正常回答，不得强行路由。\n\n'
printf '%s\n' "$STATE_BLOCK"
printf '\n%s\n\n%s\n' "$ROUTES_WF" "$ROUTES_CM"
exit 0
