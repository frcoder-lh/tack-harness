#!/bin/sh
# branch-clean.sh — 安全清理工作区登记的分支
#
# 只处理 status.yaml 的 branches 列表中登记的条目：
#   - role=tmp（临时分支）：移除 worktree 后清理
#   - role=main（工作区主分支）：仅当已合并进主干时清理
# 以下情况只列出并阻断，不删除，交人工决定：
#   - 未合并进主干的主分支
#   - 主干/保护分支（main、master、origin/HEAD 指向的默认分支）
#   - 当前检出的分支，或被任一 worktree 占用的分支
#   - 无法确定主干、仓库缺失或条目 role 未知
# 远端分支一律不自动删除（需人工在平台确认后处理），仅在输出中提示。
#
# 默认 dry-run：只输出计划，不改动任何分支；带 --apply 才实际删除本地分支。
# 主分支的合并判定基于本地引用，执行前请先 fetch 主干，避免用陈旧引用判断。
#
# Usage:
#   sh branch-clean.sh <root> <workspace> [--apply] [--trunk <name>]
#     <workspace> 为 space/ 下的相对路径（通常为 <YYYYMMDD>-<branch>）
#     --trunk 指定所有仓库的合并判定主干；缺省时按仓库自动识别
#             （本地 main → 本地 master → origin/HEAD 指向的分支）
#
# 退出码: 0 无阻断项；1 运行失败；2 用法错误；3 存在未清理项
#
# 最小用例:
#   sh branch-clean.sh /path/to/space 20261001-feat-x
#   sh branch-clean.sh /path/to/space 20261001-feat-x --apply

set -e

usage() {
    echo "branch-clean: 用法:" >&2
    echo "  sh branch-clean.sh <root> <workspace> [--apply] [--trunk <name>]" >&2
}

fail() {
    echo "branch-clean: $*" >&2
    exit 1
}

[ $# -ge 2 ] || { usage; exit 2; }
ROOT="$1"
WORKSPACE="$2"
shift 2

APPLY=0
TRUNK_OVERRIDE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --apply)
            APPLY=1
            ;;
        --trunk)
            [ $# -ge 2 ] || { usage; exit 2; }
            TRUNK_OVERRIDE="$2"
            shift
            ;;
        *)
            echo "branch-clean: 未知参数: $1" >&2
            usage
            exit 2
            ;;
    esac
    shift
done

[ -d "${ROOT}" ] || fail "tack 空间根不存在: ${ROOT}"
ROOT_ABS="$(cd "${ROOT}" && pwd -P)"
SPACE_DIR="${ROOT_ABS}/space"
[ -d "${SPACE_DIR}" ] || fail "${SPACE_DIR} 不存在，不是有效的 tack 空间"

# workspace 必须是 space/ 下的相对路径：拒绝绝对路径、反斜杠、父目录跳转
case "${WORKSPACE}" in
    ""|/*|*\\*|.|..)
        echo "branch-clean: 非法 workspace: ${WORKSPACE}" >&2
        exit 2
        ;;
esac
case "/${WORKSPACE}/" in
    */../*)
        echo "branch-clean: 非法 workspace: ${WORKSPACE}" >&2
        exit 2
        ;;
esac

WS_PATH="${SPACE_DIR}/${WORKSPACE}"
[ -d "${WS_PATH}" ] || fail "工作区目录不存在: ${WS_PATH}"
WS_REAL="$(cd "${WS_PATH}" && pwd -P)"
SPACE_REAL="$(cd "${SPACE_DIR}" && pwd -P)"
case "${WS_REAL}" in
    "${SPACE_REAL}"/*) ;;
    *) fail "工作区物理路径不在 space/ 内: ${WS_REAL}" ;;
esac

STATUS="${WS_REAL}/status.yaml"
[ -f "${STATUS}" ] || fail "status.yaml 不存在: ${STATUS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCHES="$(sh "${SCRIPT_DIR}/work-status.sh" "${STATUS}" branch list)"

# 本地分支是否存在
branch_exists() {
    git -C "$1" show-ref --verify --quiet "refs/heads/$2"
}

# 分支是否被任一 worktree 检出，或为仓库当前分支
branch_checked_out() {
    REPO_PATH="$1"
    NAME="$2"
    if git -C "${REPO_PATH}" worktree list --porcelain 2>/dev/null \
        | grep -Fx -e "branch refs/heads/${NAME}" >/dev/null 2>&1; then
        return 0
    fi
    CUR="$(git -C "${REPO_PATH}" symbolic-ref -q --short HEAD 2>/dev/null || true)"
    [ "${CUR}" = "${NAME}" ]
}

# 主干/保护分支：main、master、origin/HEAD 指向的默认分支
branch_protected() {
    REPO_PATH="$1"
    NAME="$2"
    case "${NAME}" in
        main|master) return 0 ;;
    esac
    DEF="$(git -C "${REPO_PATH}" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    DEF="${DEF#origin/}"
    [ -n "${DEF}" ] && [ "${NAME}" = "${DEF}" ]
}

# 解析仓库的合并判定主干；无法确定时返回非 0
resolve_trunk() {
    REPO_PATH="$1"
    if [ -n "${TRUNK_OVERRIDE}" ]; then
        git -C "${REPO_PATH}" rev-parse --verify -q "${TRUNK_OVERRIDE}" >/dev/null 2>&1 || return 1
        printf '%s\n' "${TRUNK_OVERRIDE}"
        return 0
    fi
    if git -C "${REPO_PATH}" rev-parse --verify -q "refs/heads/main" >/dev/null 2>&1; then
        printf '%s\n' "main"
        return 0
    fi
    if git -C "${REPO_PATH}" rev-parse --verify -q "refs/heads/master" >/dev/null 2>&1; then
        printf '%s\n' "master"
        return 0
    fi
    DEF="$(git -C "${REPO_PATH}" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    if [ -n "${DEF}" ] && git -C "${REPO_PATH}" rev-parse --verify -q "${DEF}" >/dev/null 2>&1; then
        printf '%s\n' "${DEF}"
        return 0
    fi
    return 1
}

# 分支是否已合并进主干（主干是分支的祖先）
branch_merged() {
    git -C "$1" merge-base --is-ancestor "$2" "$3" >/dev/null 2>&1
}

# 远端是否存在同名分支（只提示，不删除）
remote_exists() {
    git -C "$1" rev-parse --verify -q "refs/remotes/origin/$2" >/dev/null 2>&1
}

CLEANED=0
BLOCKED=0
FAILED=0

while IFS='|' read -r REPO NAME ROLE SRC CLEANED_FLAG; do
    [ -n "${REPO}" ] || continue
    [ -n "${NAME}" ] || continue

    REPO_PATH="${ROOT_ABS}/repo/${REPO}"
    if [ ! -d "${REPO_PATH}" ] || ! git -C "${REPO_PATH}" rev-parse --git-dir >/dev/null 2>&1; then
        echo "[blocked] ${REPO}/${NAME}: 仓库不存在或不是 git 仓库（${REPO_PATH}）"
        BLOCKED=$((BLOCKED + 1))
        continue
    fi

    if ! branch_exists "${REPO_PATH}" "${NAME}"; then
        echo "[skip] ${REPO}/${NAME}: 本地分支已不存在"
        continue
    fi

    if branch_protected "${REPO_PATH}" "${NAME}"; then
        echo "[blocked] ${REPO}/${NAME}: 主干/保护分支，不自动删除"
        BLOCKED=$((BLOCKED + 1))
        continue
    fi

    if branch_checked_out "${REPO_PATH}" "${NAME}"; then
        echo "[blocked] ${REPO}/${NAME}: 分支已被 worktree 检出，先移除 worktree"
        BLOCKED=$((BLOCKED + 1))
        continue
    fi

    case "${ROLE}" in
        tmp)
            REASON="临时分支"
            ;;
        main)
            if ! TRUNK="$(resolve_trunk "${REPO_PATH}")"; then
                echo "[blocked] ${REPO}/${NAME}: 无法确定主干，保留待人工处理"
                BLOCKED=$((BLOCKED + 1))
                continue
            fi
            if ! branch_merged "${REPO_PATH}" "${NAME}" "${TRUNK}"; then
                echo "[blocked] ${REPO}/${NAME}: 未合并进 ${TRUNK}，保留待人工决定"
                BLOCKED=$((BLOCKED + 1))
                continue
            fi
            REASON="已合并进 ${TRUNK}"
            ;;
        *)
            echo "[blocked] ${REPO}/${NAME}: 未知 role（${ROLE}），保留待人工处理"
            BLOCKED=$((BLOCKED + 1))
            continue
            ;;
    esac

    REMOTE_NOTE=""
    if remote_exists "${REPO_PATH}" "${NAME}"; then
        REMOTE_NOTE="；远端 origin/${NAME} 仍存在，需人工确认后在平台删除"
    fi

    if [ "${APPLY}" -eq 0 ]; then
        echo "[plan] ${REPO}/${NAME}: 将删除（${REASON}）${REMOTE_NOTE}"
        CLEANED=$((CLEANED + 1))
        continue
    fi

    if git -C "${REPO_PATH}" branch -D "${NAME}" >/dev/null 2>&1; then
        echo "[delete] ${REPO}/${NAME}: 已删除（${REASON}）${REMOTE_NOTE}"
        CLEANED=$((CLEANED + 1))
    else
        echo "[failed] ${REPO}/${NAME}: 删除失败（${REASON}）"
        FAILED=$((FAILED + 1))
    fi
done <<EOF
${BRANCHES}
EOF

if [ "${APPLY}" -eq 1 ]; then
    MODE="apply"
else
    MODE="dry-run"
fi
echo "SUMMARY mode=${MODE} cleaned=${CLEANED} blocked=${BLOCKED} failed=${FAILED}"

if [ "${FAILED}" -gt 0 ]; then
    exit 1
fi
if [ "${BLOCKED}" -gt 0 ]; then
    exit 3
fi
exit 0
