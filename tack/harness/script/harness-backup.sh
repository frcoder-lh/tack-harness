#!/bin/sh
# harness-backup.sh — harness 修改前的统一备份与恢复（study / update 共用）
#
# 备份内容：$root/harness/、$root/AGENTS.md、$root/tack.yaml、$root/.gitignore（存在时）。
# 备份路径只能位于 $root/.tack/backup/ 下；同秒多次备份自动追加 -2/-3 后缀。
#
# Usage:
#   sh harness-backup.sh backup  <root> <label>
#   sh harness-backup.sh restore <root> <backup-dir>
#   sh harness-backup.sh verify  <root> <backup-dir>
#
# 输出:
#   backup:  BACKUP_DIR=<path> / BACKUP_FILES=<n>
#   restore: RESTORE_RESULT=ok
#   verify:  逐文件 MISMATCH 行；全部一致输出 VERIFY_RESULT=ok
#            恢复前 verify 出现差异属正常（备份反映修改前状态），恢复后应完全一致
#
# 退出码: 0 成功；1 路径/备份无效、恢复或校验失败；2 用法错误

set -eu

ACTION="${1:-}"
ROOT="${2:-}"
ARG3="${3:-}"

usage() {
    echo "Usage: sh harness-backup.sh <backup|restore|verify> <root> <label|backup-dir>" >&2
}

[ -n "${ACTION}" ] && [ -n "${ROOT}" ] && [ -n "${ARG3}" ] || { usage; exit 2; }
if [ ! -d "${ROOT}" ]; then
    echo "Error: tack space root not found: ${ROOT}" >&2
    exit 1
fi
if [ ! -d "${ROOT}/harness" ]; then
    echo "Error: harness dir not found: ${ROOT}/harness" >&2
    exit 1
fi

BACKUP_BASE="${ROOT}/.tack/backup"
mkdir -p "${BACKUP_BASE}"

write_manifest() {
    dir="$1"
    ( cd "${dir}" && find . -type f ! -name manifest.txt -print ) | sed 's|^\./||' | sort > "${dir}/manifest.txt"
}

case "${ACTION}" in
backup)
    LABEL="${ARG3}"
    case "${LABEL}" in
        */*|*'\'*|*" "*|.|..)
            echo "Error: 非法备份标签: ${LABEL}（仅接受字母数字 . _ -）" >&2
            exit 2
            ;;
    esac
    STAMP="$(date '+%Y%m%d-%H%M%S')"
    DEST="${BACKUP_BASE}/${LABEL}-${STAMP}"
    n=2
    while [ -e "${DEST}" ]; do
        DEST="${BACKUP_BASE}/${LABEL}-${STAMP}-${n}"
        n=$((n + 1))
    done
    mkdir -p "${DEST}"
    cp -R "${ROOT}/harness" "${DEST}/harness"
    [ -f "${ROOT}/AGENTS.md" ] && cp "${ROOT}/AGENTS.md" "${DEST}/AGENTS.md"
    [ -f "${ROOT}/tack.yaml" ] && cp "${ROOT}/tack.yaml" "${DEST}/tack.yaml"
    [ -f "${ROOT}/.gitignore" ] && cp "${ROOT}/.gitignore" "${DEST}/.gitignore"
    write_manifest "${DEST}"
    echo "BACKUP_DIR=${DEST}"
    echo "BACKUP_FILES=$(grep -c . "${DEST}/manifest.txt" 2>/dev/null || true)"
    exit 0
    ;;
restore|verify)
    BACKUP_DIR="${ARG3}"
    if [ ! -d "${BACKUP_DIR}" ]; then
        echo "Error: backup dir not found: ${BACKUP_DIR}" >&2
        exit 1
    fi
    BASE_REAL="$(cd "${BACKUP_BASE}" && pwd -P)"
    TARGET_REAL="$(cd "${BACKUP_DIR}" && pwd -P)"
    case "${TARGET_REAL}" in
        "${BASE_REAL}"/*) ;;
        *)
            echo "Error: 备份路径必须位于 ${BACKUP_BASE} 内: ${BACKUP_DIR}" >&2
            exit 1
            ;;
    esac
    if [ ! -f "${TARGET_REAL}/manifest.txt" ]; then
        echo "Error: 备份缺少 manifest.txt: ${TARGET_REAL}" >&2
        exit 1
    fi
    # 备份完整性：manifest 列出的文件必须实际存在
    corrupt=0
    while IFS= read -r rel; do
        [ -n "${rel}" ] || continue
        if [ ! -f "${TARGET_REAL}/${rel}" ]; then
            echo "MISSING_BACKUP	${rel}"
            corrupt=1
        fi
    done < "${TARGET_REAL}/manifest.txt"
    if [ "${corrupt}" -ne 0 ]; then
        echo "VERIFY_RESULT=corrupt"
        exit 1
    fi

    if [ "${ACTION}" = "restore" ]; then
        if [ ! -d "${TARGET_REAL}/harness" ]; then
            echo "Error: 备份缺少 harness/: ${TARGET_REAL}" >&2
            exit 1
        fi
        rm -rf "${ROOT}/harness"
        cp -R "${TARGET_REAL}/harness" "${ROOT}/harness"
        [ -f "${TARGET_REAL}/AGENTS.md" ] && cp "${TARGET_REAL}/AGENTS.md" "${ROOT}/AGENTS.md"
        [ -f "${TARGET_REAL}/tack.yaml" ] && cp "${TARGET_REAL}/tack.yaml" "${ROOT}/tack.yaml"
        [ -f "${TARGET_REAL}/.gitignore" ] && cp "${TARGET_REAL}/.gitignore" "${ROOT}/.gitignore"
        echo "RESTORE_RESULT=ok"
        echo "请执行 verify 校验逐文件一致：sh harness-backup.sh verify ${ROOT} ${TARGET_REAL}"
        exit 0
    fi

    # verify：备份 vs 当前 root 逐文件比较
    mismatch=0
    while IFS= read -r rel; do
        [ -n "${rel}" ] || continue
        if [ ! -f "${ROOT}/${rel}" ]; then
            echo "MISSING_ROOT	${rel}"
            mismatch=1
            continue
        fi
        if ! cmp -s "${TARGET_REAL}/${rel}" "${ROOT}/${rel}"; then
            echo "DIFF	${rel}"
            mismatch=1
        fi
    done < "${TARGET_REAL}/manifest.txt"

    # root 侧多出的文件（只比较 harness 树，以及备份包含的顶层文件）
    TMP_ROOT_LIST="$(mktemp "${TMPDIR:-/tmp}/tack-backup-verify.XXXXXX")"
    trap 'rm -f "${TMP_ROOT_LIST}"' EXIT HUP INT TERM
    ( cd "${ROOT}" && find harness -type f -print ) | sort > "${TMP_ROOT_LIST}"
    while IFS= read -r rel; do
        [ -n "${rel}" ] || continue
        if ! grep -qxF "${rel}" "${TARGET_REAL}/manifest.txt"; then
            echo "EXTRA_ROOT	${rel}"
            mismatch=1
        fi
    done < "${TMP_ROOT_LIST}"

    if [ "${mismatch}" -ne 0 ]; then
        echo "VERIFY_RESULT=mismatch"
        exit 1
    fi
    echo "VERIFY_RESULT=ok"
    exit 0
    ;;
*)
    usage
    exit 2
    ;;
esac
