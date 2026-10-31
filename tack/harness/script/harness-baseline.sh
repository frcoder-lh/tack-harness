#!/bin/sh
# harness-baseline.sh — 保存出厂原件、三方分类并应用无定制冲突的更新
# Usage:
#   sh harness-baseline.sh seed <root> <incoming-tack>
#   sh harness-baseline.sh classify <root> <incoming-tack>
#   sh harness-baseline.sh apply-clean <root> <incoming-tack>
#   sh harness-baseline.sh record <root> <incoming-tack> <relative-file> [...]
# seed 仅对内容相同且没有基线的文件建基线；record 用于验证后记录已采用/融合的原件。
# 范围限定 harness/、AGENTS.md、.gitignore；删除类候选交由用户决定。
set -eu
ACTION="${1:-}"; ROOT="${2:-}"; INCOMING="${3:-}"
[ -d "${ROOT}" ] && [ -d "${INCOMING}" ] || exit 2
ROOT="$(cd "${ROOT}" && pwd -P)"
INCOMING="$(cd "${INCOMING}" && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "${SCRIPT_DIR}/common.sh"
BASE="${ROOT}/.tack/state/baseline"
. "${SCRIPT_DIR}/space-lock.sh"
tack_space_lock_acquire "${ROOT}"
mkdir -p "${BASE}" "${ROOT}/.tack/tmp"
TMP="$(mktemp "${ROOT}/.tack/tmp/baseline.XXXXXX")"
trap 'rm -f "${TMP}" "${TMP}.paths" "${TMP}.copy"; tack_space_lock_release' EXIT
trap 'exit 130' HUP INT TERM
paths() {
    (cd "$1" && find harness -type f -print)
    for p in AGENTS.md .gitignore; do [ ! -f "$1/${p}" ] || printf '%s\n' "${p}"; done
}
classify() {
    paths "${INCOMING}" > "${TMP}.paths"
    paths "${ROOT}" >> "${TMP}.paths"
    if [ -d "${BASE}/harness" ]; then paths "${BASE}" >> "${TMP}.paths"; fi
    LC_ALL=C sort -u "${TMP}.paths" > "${TMP}"
    while IFS= read -r p; do
        upstream="${INCOMING}/${p}"; current="${ROOT}/${p}"; original="${BASE}/${p}"
        kind="$(tack_classify_file "${upstream}" "${current}" "${original}")"
        printf '%s\t%s\n' "${kind}" "${p}"
    done < "${TMP}"
}
case "${ACTION}" in
    seed)
        paths "${INCOMING}" > "${TMP}"
        while IFS= read -r p; do
            if [ ! -f "${BASE}/${p}" ] && cmp -s "${ROOT}/${p}" "${INCOMING}/${p}"; then
                mkdir -p "$(dirname "${BASE}/${p}")"
                cp "${INCOMING}/${p}" "${BASE}/${p}"
            fi
        done < "${TMP}"
        ;;
    classify) classify ;;
    apply-clean)
        classify > "${TMP}.copy"
        while IFS="$(printf '\t')" read -r kind p; do
            case "${kind}" in
                ADDED|UPSTREAM)
                    mkdir -p "$(dirname "${ROOT}/${p}")"
                    cp "${INCOMING}/${p}" "${ROOT}/${p}"
                    printf 'APPLIED\t%s\n' "${p}"
                    ;;
            esac
        done < "${TMP}.copy"
        ;;
    record)
        shift 3
        [ $# -gt 0 ] || exit 2
        for p in "$@"; do
            case "${p}" in *..*|/*|*\\*) exit 2 ;; esac
            case "${p}" in harness/*|AGENTS.md|.gitignore) ;; *) exit 2 ;; esac
            [ -f "${INCOMING}/${p}" ] && [ -f "${ROOT}/${p}" ] || exit 2
        done
        for p in "$@"; do
            mkdir -p "$(dirname "${BASE}/${p}")"
            cp "${INCOMING}/${p}" "${BASE}/${p}"
        done
        ;;
    *) exit 2 ;;
esac
