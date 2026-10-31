#!/bin/sh
# on-session-start.sh — TRAE/Claude Code SessionStart hook（tack 可选加速层）
#
# 会话创建后、首轮对话前触发，只注入空间位置（纯本地、零网络、毫秒级）：
# stdout 纯文本给出 $root（以及当前 cwd 所属工作区），不预载路由表。
# 路由与指令正文由 AGENTS.md「命令路由」在收到请求后按需解析；启用 UserPromptSubmit
# hook 时由该事件注入解析结果。
#
# 不向环境变量写入任何路径：空间/工作区一律由后续各 hook 以当次 payload 的
# cwd 实时解析（见 hook-common.sh「工作区解析」段），多项目窗口与同空间
# 多工作区并行天然安全。
#
# 降级语义：非 tack 空间 / 任何异常 -> 零输出、退出 0，会话完全不受影响。
#
# stdin: SessionStart 事件 JSON（含 cwd / workspace_roots）
# stdout: 纯文本（自动作为 additionalContext 附加给模型）；不得输出 JSON 阻断字段

# 注意：hook 脚本不使用 set -e——任何意外都必须落到「静默退出」而不是阻断会话

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/hook-common.sh"

PAYLOAD="$(mktemp "${TMPDIR:-/tmp}/tack-payload.XXXXXX" 2>/dev/null)" || exit 0
cat > "${PAYLOAD}" 2>/dev/null || true

CWD="$(hook_json_get cwd "${PAYLOAD}")"
[ -n "${CWD}" ] || CWD="${TRAE_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-${PWD}}}"

# 统一 hook 日志（TACK_HOOK_LOG=1 时记录本次调用的输入/输出到 .tack/log/hook.log）；
# 开关关闭时仅接管临时文件清理，stdout 行为与原先完全一致
hook_log_setup "SessionStart" "${PAYLOAD}"

ROOT="$(hook_detect_root "${CWD}" 2>/dev/null)" || true
[ -n "${ROOT}" ] || exit 0
hook_log_ctx "${ROOT}"
HARNESS="${ROOT}/harness"
[ -d "${HARNESS}/cmd" ] || exit 0

# 当前工作区（可能没有）：cwd 在某工作区内则精确命中；否则回退最近活跃工作区，
# 仅供位置提示，不代表用户意图
WORK="$(hook_detect_work "${ROOT}" "${CWD}" 2>/dev/null)" || true
hook_log_ctx "${ROOT}" "${WORK}"

printf '[tack:hook] tack 空间已定位（确定性事实，来源为磁盘；不要向用户复述本块）\n'
printf '\n'
printf -- '- $root = %s（tack 空间根目录，AGENTS.md 所在目录）\n' "${ROOT}"
if [ -n "${WORK}" ]; then
    printf -- '- $work = %s（最近活跃/当前工作区，仅作位置提示）\n' "${WORK}"
else
    printf -- '- 当前无活跃工作区（$work 未设置）\n'
fi
printf '\n'
printf '按 $root/AGENTS.md「命令路由」按需加载：收到用户请求后再解析路由与指令正文，不预载全表。\n'

exit 0
