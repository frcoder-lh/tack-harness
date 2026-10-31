#!/bin/sh
# harness-diff.sh — 固化 harness 更新差异分类（update 的确定性前置）
#
# 只做分类，不覆盖任何文件；是否采用、保留或融合由模型与用户决定。
#
# Usage:
#   sh harness-diff.sh <incoming-harness> <local-harness> --profile update [--base <original-harness>]
#
# 输出（TAB 分隔，按路径排序）:
#   ADDED      incoming 有、local 无（含新增的 rule/ 文件）
#   CHANGED    两者都有且内容不同（rule/ 下文件同样分类，由 update 逐文件交用户裁决）
#   SAME       两者都有且内容一致
#   LOCAL_ONLY local 有、incoming 无
#
# 说明: 本脚本只分类、不做任何覆盖决策；rule/ 下的文件不特殊跳过，必须由 update 列入候选并经用户选择。
# 临时文件: 在 tack 空间内执行时落 <local-harness 上级>/.tack/tmp/（退出即清）；非 tack 空间回退系统临时目录。
#
# 退出码: 0 分类完成；1 目录无效或读取失败；2 用法错误

set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "${SCRIPT_DIR}/common.sh"

BASE=""
PROFILE=""
remaining=$#
while [ "${remaining}" -gt 0 ]; do
    arg="$1"; shift; remaining=$((remaining - 1))
    case "${arg}" in
        --base|--profile)
            [ "${remaining}" -gt 0 ] || exit 2
            if [ "${arg}" = --base ]; then BASE="$1"; else PROFILE="$1"; fi
            shift; remaining=$((remaining - 1))
            ;;
        --*) exit 2 ;;
        *) set -- "$@" "${arg}" ;;
    esac
done
INCOMING="${1:-}"
LOCAL="${2:-}"

if [ $# -ne 2 ] || [ -z "${INCOMING}" ] || [ -z "${LOCAL}" ] || [ "${PROFILE}" != update ]; then
    echo "Usage: sh harness-diff.sh <incoming-harness> <local-harness> --profile update" >&2
    exit 2
fi
[ -z "${BASE}" ] || [ -d "${BASE}" ] || exit 2

if [ ! -d "${INCOMING}" ]; then
    echo "Error: incoming harness dir not found: ${INCOMING}" >&2
    exit 1
fi
if [ ! -d "${LOCAL}" ]; then
    echo "Error: local harness dir not found: ${LOCAL}" >&2
    exit 1
fi

# 临时集合文件优先落本地 harness 所属空间的 .tack/tmp（update 约束：不写系统临时目录）
LOCAL_ROOT="$(dirname "${LOCAL}")"
TMP_DIR="${LOCAL_ROOT}/.tack/tmp"
if [ -f "${LOCAL_ROOT}/AGENTS.md" ] && mkdir -p "${TMP_DIR}" 2>/dev/null; then
    :
else
    TMP_DIR="${TMPDIR:-/tmp}"
fi
TMP_A="$(mktemp "${TMP_DIR}/tack-hdiff-a.XXXXXX")"
TMP_B="$(mktemp "${TMP_DIR}/tack-hdiff-b.XXXXXX")"
TMP_ALL="$(mktemp "${TMP_DIR}/tack-hdiff-all.XXXXXX")"
trap 'rm -f "${TMP_A}" "${TMP_B}" "${TMP_ALL}"' EXIT HUP INT TERM

( cd "${INCOMING}" && find . -type f -print ) | sed 's|^\./||' | sort > "${TMP_A}"
( cd "${LOCAL}" && find . -type f -print ) | sed 's|^\./||' | sort > "${TMP_B}"
sort -u "${TMP_A}" "${TMP_B}" > "${TMP_ALL}"
if [ -n "${BASE}" ]; then
    (cd "${BASE}" && find . -type f -print) | sed 's|^\./||' >> "${TMP_ALL}"
    sort -u "${TMP_ALL}" > "${TMP_A}"
    mv "${TMP_A}" "${TMP_ALL}"
fi

n_added=0; n_changed=0; n_same=0; n_local=0
while IFS= read -r rel; do
    [ -n "${rel}" ] || continue
    if [ -n "${BASE}" ] && [ -f "${BASE}/${rel}" ]; then
        kind="$(tack_classify_file "${INCOMING}/${rel}" "${LOCAL}/${rel}" "${BASE}/${rel}")"
        printf '%s\t%s\n' "${kind}" "${rel}"
        continue
    fi
    if [ -f "${INCOMING}/${rel}" ] && [ -f "${LOCAL}/${rel}" ]; then
        if cmp -s "${INCOMING}/${rel}" "${LOCAL}/${rel}"; then
            printf 'SAME\t%s\n' "${rel}"
            n_same=$((n_same + 1))
        else
            printf 'CHANGED\t%s\n' "${rel}"
            n_changed=$((n_changed + 1))
        fi
    elif [ -f "${INCOMING}/${rel}" ]; then
        printf 'ADDED\t%s\n' "${rel}"
        n_added=$((n_added + 1))
    else
        printf 'LOCAL_ONLY\t%s\n' "${rel}"
        n_local=$((n_local + 1))
    fi
done < "${TMP_ALL}"

echo "harness-diff: added=${n_added} changed=${n_changed} same=${n_same} local_only=${n_local}" >&2
exit 0
