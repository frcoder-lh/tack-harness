#!/bin/sh
# scan-secrets.sh — 空间文档凭据明文扫描（space.sh commit 前的硬门禁）
#
# 扫描 $root/wiki 与 $root/space 下的文档（*.md *.yaml *.yml），
# 显式排除 repo 工作区（.gitignore 已忽略，双保险）与 .git；
# 命中高置信凭据模式即报告「文件:行号: 内容」并退出 1，阻断自动提交。
#
# 与 rule/security.md 的分工：security.md 是面向【用户代码】的安全编码规则；
# 本脚本只守护【空间自身文档】（wiki 公共知识、工作区产物），落实
# 「wiki 只记凭据获取方式、不记明文」的硬门禁。
#
# 误报处理（高精度优先，宁可漏报低置信线索也不刷假告警）：
#   - 行内含豁免标记 `tack:allow-secret`：跳过该行（审阅时可审计）
#   - 占位/示例值不告警：sk-xxx、your-、example、sample、dummy、fake、xxxx、
#     ***、${...}、<...> 模板变量、中文「占位/待补充/获取方式」
#   - 紧急情况可用 TACK_SECRET_SCAN=off 显式跳过（输出提示，责任自负）
#
# Usage:
#   sh scan-secrets.sh <root>                # 空间文档（wiki/、space/，*.md *.yaml *.yml）
#   sh scan-secrets.sh <root> --changed      # 本次 Git 变更文件 + 根 AGENTS.md
#     --changed 覆盖新增/修改的 cmd、workflow、rule、reference、run/*.sh、
#     .ps1/.py 等入库脚本与其他文本变更文件；忽略 run/local/、.tack/、
#     repo/ 与 space/*/repo/（以及 Git 已忽略路径）
#     Git 状态记录按 NUL 分隔读取，文件名含中文、空格、引号时不会丢路径；
#     rename 只取新的目标路径
# Windows: powershell -ExecutionPolicy Bypass -File run.ps1 scan-secrets <root> [--changed]
# 退出码: 0 无命中（或显式跳过）/ 1 命中凭据明文 / 2 用法错误

ROOT="$1"
MODE="${2:-}"

if [ -z "${ROOT}" ] || [ ! -d "${ROOT}" ]; then
    echo "Error: tack space root not found: ${ROOT}" >&2
    echo "Usage: sh scan-secrets.sh <root> [--changed]" >&2
    exit 2
fi
if [ -n "${MODE}" ] && [ "${MODE}" != "--changed" ]; then
    echo "Error: 未知参数: ${MODE}（仅支持 --changed）" >&2
    echo "Usage: sh scan-secrets.sh <root> [--changed]" >&2
    exit 2
fi

if [ "${TACK_SECRET_SCAN:-}" = "off" ]; then
    echo "scan-secrets: 已通过 TACK_SECRET_SCAN=off 跳过凭据扫描（请确认本次提交不含敏感信息）"
    exit 0
fi

# 临时文件统一放空间 .tack/tmp/（不写系统 temp），退出即清；目录空时顺手移除
TMP_DIR="${ROOT}/.tack/tmp"
mkdir -p "${TMP_DIR}"
TMP_HITS="${TMP_DIR}/scan-secrets.$$.hits"
TMP_FILES="${TMP_DIR}/scan-secrets.$$.files"
trap 'rm -f "${TMP_HITS}" "${TMP_FILES}"; rmdir "${TMP_DIR}" 2>/dev/null || true' EXIT INT TERM
: > "${TMP_HITS}"
: > "${TMP_FILES}"

# 高置信凭据模式（ERE；两侧显式边界字符类，兼容 GNU/BSD grep）
P_PEM='-----BEGIN [A-Z ]*PRIVATE KEY-----'
P_AWS='(^|[^A-Z0-9])(AKIA|ASIA)[0-9A-Z]{16}([^0-9A-Z]|$)'
P_GH='(^|[^A-Za-z0-9])gh[pousr]_[A-Za-z0-9]{36,}([^A-Za-z0-9_]|$)'
P_OPENAI='(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}([^A-Za-z0-9_-]|$)'
P_GOOG='(^|[^A-Za-z0-9])AIza[0-9A-Za-z_-]{35}([^0-9A-Za-z_-]|$)'
P_SLACK='(^|[^A-Za-z0-9])xox[baprs]-[0-9A-Za-z-]{10,}([^0-9A-Za-z-]|$)'
# 赋值型：password/token/secret/api_key 等 = 或 : 后紧跟 8+ 非空白值（含引号包裹）
P_ASSIGN='(password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key)["]?[[:space:]]*[:=][[:space:]]*[^[:space:]"<>]{8,}'

# 白名单（占位符/示例/中文模板语）——命中后二次过滤
WHITELIST='sk-xxx|your[-_]|example|sample|dummy|fake|xxxx|\*\*\*|\$\{|<[^>]*>|占位|待补充|获取方式|凭据.*方式|redacted|REDACTED'

if [ "${MODE}" = "--changed" ]; then
    if [ ! -d "${ROOT}/.git" ]; then
        echo "Error: ${ROOT} 不是 Git 仓库，无法使用 --changed" >&2
        exit 1
    fi
    # 本次变更文件（含未跟踪）+ 根 AGENTS.md；忽略 run/local/、.tack/、repo 工作区。
    # -z 输出为 NUL 分隔记录：文件名中的中文、空格、引号原样保留，不按空白拆词；
    # 每条记录独立解析，rename 的第二条记录是源路径（无状态前缀），自动跳过
    git -C "${ROOT}" -c core.quotePath=false status --porcelain -z \
        --untracked-files=all 2>/dev/null |
    xargs -0 sh -c '
        root="$1"
        shift
        for rec in "$@"; do
            [ -n "${rec}" ] || continue
            # 记录形态：两位状态码 + 空格；rename 的第二条记录（源路径）不满足
            c1="${rec%"${rec#?}"}"
            rest="${rec#?}"
            c2="${rest%"${rest#?}"}"
            c3="${rest#?}"
            c3="${c3%"${c3#?}"}"
            case "${c1}" in
                M|A|D|R|C|U|T|X|"?"|"!"|" ") ;;
                *) continue ;;
            esac
            case "${c2}" in
                M|A|D|R|C|U|T|X|"?"|"!"|" ") ;;
                *) continue ;;
            esac
            [ "${c3}" = " " ] || continue
            p="${rec#???}"
            case "${p}" in
                repo/*|space/*/repo/*|.tack/*|run/local/*|*/run/local/*) continue ;;
            esac
            case "${p##*.}" in
                md|yaml|yml|sh|ps1|py|js|ts|json|toml|ini|conf|txt|bat|cmd|go|java|kt|rs|rb|php|c|h|cpp|hpp|sql|html|css) ;;
                *) continue ;;
            esac
            [ -f "${root}/${p}" ] || continue
            printf "%s\0" "${root}/${p}"
        done
    ' sh "${ROOT}" >> "${TMP_FILES}"
    [ -f "${ROOT}/AGENTS.md" ] && printf '%s\0' "${ROOT}/AGENTS.md" >> "${TMP_FILES}"
else
    # 待扫描目录（均为空间文档目录；不存在则跳过）
    set --
    [ -d "${ROOT}/wiki" ]  && set -- "$@" "${ROOT}/wiki"
    [ -d "${ROOT}/space" ] && set -- "$@" "${ROOT}/space"
    if [ "$#" -eq 0 ]; then
        echo "scan-secrets: 无 wiki/space 文档目录，跳过"
        exit 0
    fi
    # 枚举空间文档：修剪 .git 与所有 repo/ 工作区目录；-print0 支持特殊文件名
    find "$@" \
        \( -type d \( -name .git -o -name repo \) -prune \) -o \
        -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) -print0 2>/dev/null >> "${TMP_FILES}"
fi

# 批量扫描：文件清单 NUL 分隔直接交给 grep，文件名含空格/引号/中文时不被拆词或转义
xargs -0 grep -EnH \
    -e "${P_PEM}" -e "${P_AWS}" -e "${P_GH}" -e "${P_OPENAI}" \
    -e "${P_GOOG}" -e "${P_SLACK}" -e "${P_ASSIGN}" \
    -- < "${TMP_FILES}" 2>/dev/null |
grep -v 'tack:allow-secret' |
grep -viE "${WHITELIST}" |
while IFS= read -r hit; do
    # 截断超长内容，避免整段文档刷屏
    if [ "${#hit}" -gt 160 ]; then
        hit="$(printf '%s' "${hit}" | cut -c1-160)..."
    fi
    printf 'SECRET_HIT %s\n' "${hit}"
done >> "${TMP_HITS}"

CNT=$(grep -c '^SECRET_HIT' "${TMP_HITS}" 2>/dev/null || true)
CNT=${CNT:-0}

if [ "${CNT}" -gt 0 ]; then
    echo "scan-secrets: 发现 ${CNT} 处疑似凭据明文，已阻断提交：" >&2
    sed 's/^SECRET_HIT /  /' "${TMP_HITS}" >&2
    echo "" >&2
    echo "处理方式：1) 删除明文、只保留凭据获取位置；2) 确属误报可在行内加标记 tack:allow-secret；" >&2
    echo "          3) 紧急情况设置 TACK_SECRET_SCAN=off 跳过（不推荐，泄露后必须轮换凭据）。" >&2
    exit 1
fi

echo "scan-secrets: 未发现凭据明文"
exit 0
