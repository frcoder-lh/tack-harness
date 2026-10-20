#!/bin/sh
# lint-shell-portability.sh — shell 脚本三平台可移植性机检
#
# Usage:
#   sh lint-shell-portability.sh <harness-dir>
#
# 检查 <harness-dir>/script/*.sh 与 script/hook/*.sh（跳过本脚本）：
#   1. 裸 mktemp（BSD/macOS 要求模板）
#   2. GNU 专有工具选项：sed -i/-r、grep -P、find -printf/-regex、readlink -f、
#      stat -c/--format、date -d、mktemp -p、xargs -r、sort -V、md5sum/sha256sum、
#      realpath、seq
#   3. bashism：[[]]、<<<、set -o pipefail、local、declare/typeset、数组赋值、source
#   4. sed 块内最后一条命令缺少 ;（GNU 宽松解析、BSD 报错）

# 输出：ERROR [脚本相对路径:行号] <原因>: <代码行>；末尾 SUMMARY files=N errors=N
# 退出码：0 无 ERROR / 1 存在 ERROR / 2 用法错误
# 说明：仅做保守的静态字符串检查，命中不等于必然不兼容，需人工确认。

set -eu

HARNESS_DIR="${1:-}"
if [ -z "${HARNESS_DIR}" ] || [ ! -d "${HARNESS_DIR}" ]; then
    echo "Usage: sh lint-shell-portability.sh <harness-dir>" >&2
    exit 2
fi

cd "${HARNESS_DIR}" || {
    echo "Error: 无法进入 harness 目录: ${HARNESS_DIR}" >&2
    exit 2
}

TMP="$(mktemp "${TMPDIR:-/tmp}/tack-lint-shell.XXXXXX")"
trap 'rm -f "${TMP}"' EXIT HUP INT TERM
: > "${TMP}"

FILES=""
N_FILES=0
for f in script/*.sh script/hook/*.sh; do
    [ -f "${f}" ] || continue
    [ "${f}" = "script/lint-shell-portability.sh" ] && continue
    FILES="${FILES} ${f}"
    N_FILES=$((N_FILES + 1))
done

if [ "${N_FILES}" -eq 0 ]; then
    echo "lint-shell-portability: 未找到 shell 脚本: ${HARNESS_DIR}/script" >&2
    exit 2
fi

check() {
    label="$1"
    pattern="$2"
    hits="$(grep -nHE "${pattern}" ${FILES} 2>/dev/null || true)"
    [ -n "${hits}" ] || return 0
    printf '%s\n' "${hits}" | while IFS= read -r hit; do
        file="${hit%%:*}"
        rest="${hit#*:}"
        line="${rest%%:*}"
        code="${rest#*:}"
        code_trim="$(printf '%s' "${code}" | sed 's/^[[:space:]]*//')"
        case "${code_trim}" in
            \#*) continue ;;
        esac
        printf 'ERROR [%s:%s] %s: %s\n' "${file}" "${line}" "${label}" "${code_trim}" >> "${TMP}"
    done
}

check "裸 mktemp（BSD/macOS 要求模板）" \
    'mktemp([[:space:]]+-d)?[[:space:]]*(\)|2>|$|;|\|)'
check "GNU sed -i" \
    '(^|[^a-zA-Z])sed[[:space:]]+-[a-zA-Z]*i([[:space:]]|$)'
check "GNU sed -r" \
    '(^|[^a-zA-Z])sed[[:space:]]+-[a-zA-Z]*r([[:space:]]|$)'
check "GNU grep -P" \
    '(^|[^a-zA-Z])grep[[:space:]]+-[a-zA-Z]*P([[:space:]]|$)'
check "GNU find -printf/-regex" \
    '(^|[^a-zA-Z])find[^;]*-(printf|regex)([[:space:]]|$)'
check "GNU readlink -f" \
    '(^|[^a-zA-Z])readlink[[:space:]]+-[a-zA-Z]*f([[:space:]]|$)'
check "GNU stat -c/--format" \
    '(^|[^a-zA-Z])stat[[:space:]]+(-c|--format)([[:space:]]|=|$)'
check "GNU date -d" \
    '(^|[^a-zA-Z])date[[:space:]]+-d([[:space:]]|$)'
check "GNU mktemp -p" \
    '(^|[^a-zA-Z])mktemp[[:space:]]+-p([[:space:]]|$)'
check "GNU xargs -r" \
    '(^|[^a-zA-Z])xargs[[:space:]]+-r([[:space:]]|$)'
check "GNU sort -V" \
    '(^|[^a-zA-Z])sort[[:space:]]+-V([[:space:]]|$)'
check "GNU md5sum/sha256sum" \
    '(^|[^a-zA-Z_])(md5sum|sha256sum)([^a-zA-Z_]|$)'
check "非 POSIX realpath/seq" \
    '(^|[;&|()])[[:space:]]*(realpath|seq)[[:space:]]'
check "bash [[ ]]" \
    '(^|[^[])\[\[[^:]'
check "bash here-string <<<" \
    '<<<'
check "bash set -o pipefail" \
    'set[[:space:]]+-o[[:space:]]+pipefail'
check "bash local" \
    '^[[:space:]]*local[[:space:]]'
check "bash declare/typeset" \
    '^[[:space:]]*(declare|typeset)[[:space:]]'
check "bash 数组赋值" \
    '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\('
check "bash source" \
    '(^|[;&|])[[:space:]]*source[[:space:]]'
check "sed 块内末命令缺少分号" \
    'sed[^}]*\{[[:space:]][^}]*[^;[:space:]][[:space:]]*\}'

cat "${TMP}"
N_ERR="$(grep -c '^ERROR' "${TMP}" 2>/dev/null || true)"
[ -n "${N_ERR}" ] || N_ERR=0
echo "lint-shell-portability: ${N_FILES} file(s), ${N_ERR} error(s)"
[ "${N_ERR}" -eq 0 ]
