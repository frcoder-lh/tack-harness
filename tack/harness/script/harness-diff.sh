#!/bin/sh
# harness-diff.sh — 固化 harness 更新差异分类（update 的确定性前置）
#
# 只做分类，不覆盖任何文件；是否采用、保留或融合由模型与用户决定。
#
# Usage:
#   sh harness-diff.sh <incoming-harness> <local-harness> --profile update
#
# 输出（TAB 分隔，按路径排序）:
#   ADDED      incoming 有、local 无
#   CHANGED    两者都有且内容不同
#   SAME       两者都有且内容一致
#   LOCAL_ONLY local 有、incoming 无
#   PROTECTED  profile=update 下 rule/ 内的文件（永不自动覆盖）
#
# 退出码: 0 分类完成；1 目录无效或读取失败；2 用法错误

set -eu

INCOMING="${1:-}"
LOCAL="${2:-}"
PROFILE="${3:-}"

if [ -z "${INCOMING}" ] || [ -z "${LOCAL}" ] || [ "${PROFILE}" != "--profile" ] || [ "${4:-}" != "update" ]; then
    echo "Usage: sh harness-diff.sh <incoming-harness> <local-harness> --profile update" >&2
    exit 2
fi

if [ ! -d "${INCOMING}" ]; then
    echo "Error: incoming harness dir not found: ${INCOMING}" >&2
    exit 1
fi
if [ ! -d "${LOCAL}" ]; then
    echo "Error: local harness dir not found: ${LOCAL}" >&2
    exit 1
fi

TMP_A="$(mktemp "${TMPDIR:-/tmp}/tack-hdiff-a.XXXXXX")"
TMP_B="$(mktemp "${TMPDIR:-/tmp}/tack-hdiff-b.XXXXXX")"
TMP_ALL="$(mktemp "${TMPDIR:-/tmp}/tack-hdiff-all.XXXXXX")"
trap 'rm -f "${TMP_A}" "${TMP_B}" "${TMP_ALL}"' EXIT HUP INT TERM

( cd "${INCOMING}" && find . -type f -print ) | sed 's|^\./||' | sort > "${TMP_A}"
( cd "${LOCAL}" && find . -type f -print ) | sed 's|^\./||' | sort > "${TMP_B}"
sort -u "${TMP_A}" "${TMP_B}" > "${TMP_ALL}"

n_added=0; n_changed=0; n_same=0; n_local=0; n_protected=0
while IFS= read -r rel; do
    [ -n "${rel}" ] || continue
    case "${rel}" in
        rule/*)
            printf 'PROTECTED\t%s\n' "${rel}"
            n_protected=$((n_protected + 1))
            continue
            ;;
    esac
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

echo "harness-diff: added=${n_added} changed=${n_changed} same=${n_same} local_only=${n_local} protected=${n_protected}" >&2
exit 0
