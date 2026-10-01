#!/bin/sh
# install-hooks.sh — 物化 agent hook 声明到 tack 空间根（可选加速层）
#
# 输出：
#   <root>/.trae/hooks.json        — TRAE（TraeCode）项目级 hook 声明
#   <root>/.claude/settings.json   — Claude Code 项目级 hook 声明（TRAE 也会读取）
#
# 行为：
#   - 按当前平台渲染 command（Windows 经 run.ps1 转 Git Bash；macOS/Linux 直调 sh），
#     路径使用 agent 注入的 CLAUDE_PROJECT_DIR（TRAE 兼容注入同名变量），空间可整体迁移
#   - 已存在的声明文件跳过不覆盖（与 init-tack 的 -n 语义一致，保护用户自定义）
#   - 幂等，可重复执行；物化后需用户在 TRAE 设置 > Hooks 中手动确认启用（平台安全要求）
#
# Usage: sh install-hooks.sh <root>
# 退出码: 0 成功（含跳过）/ 非 0 参数或模板缺失错误

set -eu

ROOT="${1:-}"
[ -n "$ROOT" ] || { echo "Usage: sh install-hooks.sh <root>" >&2; exit 2; }
[ -f "$ROOT/AGENTS.md" ] || { echo "Error: 不是 tack 空间（缺 AGENTS.md）: $ROOT" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPL_DIR="$(cd "$SCRIPT_DIR/../../template/hook" && pwd)"

# 按平台准备三条命令（JSON 转义：先反斜杠后双引号；本仓命令只用正斜杠，无反斜杠载荷）
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        # hook 宿主为 PowerShell：嵌套 powershell -Bypass 启动 run.ps1（与 AGENTS.md 约定一致），
        # run.ps1 接受 script/ 下相对子路径 hook/<name>，stdin 由进程链自然透传
        CMD_SESSION='powershell -ExecutionPolicy Bypass -File "$env:CLAUDE_PROJECT_DIR/harness/script/run.ps1" hook/on-session-start'
        CMD_PROMPT='powershell -ExecutionPolicy Bypass -File "$env:CLAUDE_PROJECT_DIR/harness/script/run.ps1" hook/on-prompt-submit'
        CMD_PRETOOL='powershell -ExecutionPolicy Bypass -File "$env:CLAUDE_PROJECT_DIR/harness/script/run.ps1" hook/on-pre-tool-use'
        ;;
    *)
        CMD_SESSION='sh "$CLAUDE_PROJECT_DIR/harness/script/hook/on-session-start.sh"'
        CMD_PROMPT='sh "$CLAUDE_PROJECT_DIR/harness/script/hook/on-prompt-submit.sh"'
        CMD_PRETOOL='sh "$CLAUDE_PROJECT_DIR/harness/script/hook/on-pre-tool-use.sh"'
        ;;
esac

json_escape() {
    sed 's/\\/\\\\/g; s/"/\\"/g'
}

# render <template> <output> —— awk 经 ENVIRON 取值替换占位（避免 sed 替换串 & / 反斜杠陷阱）
render() {
    _tmpl="$1"; _out="$2"
    [ -f "$_tmpl" ] || { echo "Error: hook 模板缺失: $_tmpl" >&2; exit 1; }
    if [ -e "$_out" ]; then
        echo "hook 声明已存在，跳过: $_out"
        return 0
    fi
    E_CS="$(printf '%s' "$CMD_SESSION" | json_escape)" \
    E_CP="$(printf '%s' "$CMD_PROMPT" | json_escape)" \
    E_CP2="$(printf '%s' "$CMD_PRETOOL" | json_escape)" \
    awk '
        function inject(line,   out, p) {
            out=""
            while ((p = index(line, "@@CMD_SESSION@@")) > 0) {
                out = out substr(line, 1, p-1) ENVIRON["E_CS"]
                line = substr(line, p+15)
            }
            while ((p = index(line, "@@CMD_PROMPT@@")) > 0) {
                out = out substr(line, 1, p-1) ENVIRON["E_CP"]
                line = substr(line, p+14)
            }
            while ((p = index(line, "@@CMD_PRETOOL@@")) > 0) {
                out = out substr(line, 1, p-1) ENVIRON["E_CP2"]
                line = substr(line, p+15)
            }
            return out line
        }
        { print inject($0) }
    ' "$_tmpl" > "$_out"
    echo "hook 声明已物化: $_out"
}

mkdir -p "$ROOT/.trae" "$ROOT/.claude"
render "$TMPL_DIR/hooks.json.tmpl"    "$ROOT/.trae/hooks.json"
render "$TMPL_DIR/settings.json.tmpl" "$ROOT/.claude/settings.json"

echo "提示: hook 为可选加速层；TRAE 需在 设置 > Hooks 中确认启用项目级 hook，Claude Code 自动读取 .claude/settings.json。"
