#!/bin/sh
# workspace-archive.sh — close 归档工作区：列出非标准文件、把产物移入 history/<workspace>/
#
# Usage:
#   sh workspace-archive.sh list <root> <workspace>
#   sh workspace-archive.sh move <root> <project> <workspace> <relative-path>...
#
# list: 输出工作区根下除标准产物外的条目，每行 TYPE<TAB>NAME（DIR/FILE）
#      标准产物：status.yaml、context.md、story/、doc/、repo/、run/
# move: 创建 <root>/wiki/<project>/history/<workspace>/，把相对工作区的条目原样移入
#       输出 ARCHIVE_DIR=<路径>，每个成功移动的条目输出 MOVED<TAB><relative-path>
#
# 退出码: 0 成功；1 目录/条目不存在；2 用法或参数非法；3 目标已存在（拒绝覆盖）；4 移动失败

set -eu

ACTION="${1:-}"
ROOT="${2:-}"

usage() {
    echo "Usage:" >&2
    echo "  sh workspace-archive.sh list <root> <workspace>" >&2
    echo "  sh workspace-archive.sh move <root> <project> <workspace> <relative-path>..." >&2
}

valid_workspace() {
    case "$1" in
        ""|.|..|*/*|*\\*|*" "*) return 1 ;;
    esac
    return 0
}

valid_project() {
    case "$1" in
        ""|.|..|*/*|*\\*) return 1 ;;
    esac
    return 0
}

valid_rel() {
    case "$1" in
        ""|.|..|/*|[A-Za-z]:*|*\\*) return 1 ;;
    esac
    case "/$1/" in
        *"/../"*|*"/./"*) return 1 ;;
    esac
    return 0
}

[ -n "${ACTION}" ] && [ -n "${ROOT}" ] || { usage; exit 2; }
[ -d "${ROOT}" ] || { echo "Error: root not found: ${ROOT}" >&2; exit 1; }

if [ "${ACTION}" = "list" ]; then
    WORKSPACE="${3:-}"
    [ -n "${WORKSPACE}" ] && valid_workspace "${WORKSPACE}" || { usage; exit 2; }
    WORK="${ROOT}/space/${WORKSPACE}"
    [ -d "${WORK}" ] || { echo "Error: workspace not found: ${WORK}" >&2; exit 1; }
    for entry in "${WORK}"/* "${WORK}"/.[!.]* "${WORK}"/..?*; do
        [ -e "${entry}" ] || [ -L "${entry}" ] || continue
        name="${entry##*/}"
        case "${name}" in
            status.yaml|context.md|story|doc|repo|run) continue ;;
        esac
        if [ -d "${entry}" ]; then
            printf 'CANDIDATE\tDIR\t%s\n' "${name}"
        else
            printf 'CANDIDATE\tFILE\t%s\n' "${name}"
        fi
    done
    exit 0
fi

if [ "${ACTION}" = "move" ]; then
    PROJECT="${3:-}"
    WORKSPACE="${4:-}"
    [ $# -ge 5 ] || { usage; exit 2; }
    [ -n "${PROJECT}" ] && valid_project "${PROJECT}" || { echo "Error: invalid project: ${PROJECT}" >&2; exit 2; }
    [ -n "${WORKSPACE}" ] && valid_workspace "${WORKSPACE}" || { echo "Error: invalid workspace: ${WORKSPACE}" >&2; exit 2; }
    WORK="${ROOT}/space/${WORKSPACE}"
    [ -d "${WORK}" ] || { echo "Error: workspace not found: ${WORK}" >&2; exit 1; }
    ARCHIVE="${ROOT}/wiki/${PROJECT}/history/${WORKSPACE}"
    mkdir -p "${ARCHIVE}" || { echo "Error: cannot create archive dir: ${ARCHIVE}" >&2; exit 1; }
    printf 'ARCHIVE_DIR=%s\n' "${ARCHIVE}"
    shift 4
    for rel in "$@"; do
        valid_rel "${rel}" || { echo "Error: invalid path: ${rel}" >&2; exit 2; }
        src="${WORK}/${rel}"
        dst="${ARCHIVE}/${rel}"
        [ -e "${src}" ] || [ -L "${src}" ] || { echo "Error: source not found: ${src}" >&2; exit 1; }
        if [ -e "${dst}" ] || [ -L "${dst}" ]; then
            echo "Error: destination already exists: ${dst}" >&2
            exit 3
        fi
        mkdir -p "$(dirname "${dst}")" || { echo "Error: cannot create parent of: ${dst}" >&2; exit 1; }
        if ! mv "${src}" "${dst}"; then
            echo "Error: move failed: ${src} -> ${dst}" >&2
            exit 4
        fi
        printf 'MOVED\t%s\n' "${rel}"
    done
    exit 0
fi

usage
exit 2
