#!/bin/sh
# git-diff-context.sh — 导出当前分支相对目标分支的三点 diff 审查上下文
#
# 为 code-review / release-check 命令提供确定性事实（语义分析由命令完成）：
#   1. 解析目标分支 ref（参数指定，或自动探测 master/main；本地缺失回退 origin/<branch>）
#   2. 计算 merge-base（三点 diff 的固定点）
#   3. 导出完整 diff 与 --stat 到输出目录
#
# 用法:
#   sh git-diff-context.sh <repo-path> <out-dir> [target-branch]
#   - repo-path:     代码仓库路径（$work/repo/<repo-name>）
#   - out-dir:       diff/stat 输出目录（不存在自动创建；建议 $root/.tack/tmp/review/，不入库）
#   - target-branch: 目标分支（可选，默认自动探测 master/main）
#
# 输出（label: value 格式，便于 AI 解析）：
#   repo:           仓库名（路径 basename）
#   target_ref:     实际使用的目标 ref
#   merge_base:     merge-base commit hash（完整）
#   head:           当前 HEAD commit hash（完整）
#   empty:          true=与目标无差异 / false=有差异
#   files_changed:  改动文件数
#   insertions:     新增行数
#   deletions:      删除行数
#   diff_file:      完整 diff 文件路径
#   stat_file:      diff --stat 文件路径
#
# 退出码: 0 成功；1 仓库/目标 ref 不存在或无 merge-base；2 用法错误

set -eu

if [ $# -lt 2 ]; then
    echo "Usage: $0 <repo-path> <out-dir> [target-branch]" >&2
    exit 2
fi

REPO="$1"
OUT_DIR="$2"
TARGET_BRANCH="${3:-}"

if [ ! -d "${REPO}" ]; then
    echo "Error: repo not found: ${REPO}" >&2
    exit 1
fi

# 物化 out-dir 为绝对路径（cd 进仓库前），兼容 POSIX 路径与 Windows 盘符路径
case "${OUT_DIR}" in
    /* | [A-Za-z]:/*) : ;;
    *) OUT_DIR="$(pwd)/${OUT_DIR}" ;;
esac

cd "${REPO}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: not a git repository: ${REPO}" >&2
    exit 1
fi

# 解析分支为可用 ref：本地分支优先，其次 origin/<branch>
resolve_ref() {
    if git rev-parse --verify --quiet "$1" >/dev/null; then
        echo "$1"
        return 0
    fi
    if git rev-parse --verify --quiet "origin/$1" >/dev/null; then
        echo "origin/$1"
        return 0
    fi
    return 1
}

if [ -n "${TARGET_BRANCH}" ]; then
    if ! TARGET_REF="$(resolve_ref "${TARGET_BRANCH}")"; then
        echo "Error: target branch not found: ${TARGET_BRANCH} (neither local nor origin/)" >&2
        exit 1
    fi
else
    TARGET_REF=""
    for b in master main; do
        if TARGET_REF="$(resolve_ref "${b}")"; then
            break
        fi
        TARGET_REF=""
    done
    if [ -z "${TARGET_REF}" ]; then
        echo "Error: cannot auto-detect target branch (tried master/main); please specify explicitly" >&2
        exit 1
    fi
fi

HEAD_SHA="$(git rev-parse HEAD)"
if ! MERGE_BASE="$(git merge-base "${TARGET_REF}" HEAD)"; then
    echo "Error: no merge-base between ${TARGET_REF} and HEAD" >&2
    exit 1
fi

mkdir -p "${OUT_DIR}"

REPO_NAME="$(basename "${REPO}")"
SAFE_TARGET="$(printf '%s' "${TARGET_REF}" | tr '/' '-')"
OUT_BASE="${OUT_DIR}/${REPO_NAME}-vs-${SAFE_TARGET}"
DIFF_FILE="${OUT_BASE}.diff"
STAT_FILE="${OUT_BASE}.stat"

git diff "${MERGE_BASE}...HEAD" > "${DIFF_FILE}"
git diff --stat "${MERGE_BASE}...HEAD" > "${STAT_FILE}"

# 汇总统计（numstat 对二进制文件输出 "-"，awk 转数值按 0 计）
STATS="$(git diff --numstat "${MERGE_BASE}...HEAD" | awk '{ i += $1; d += $2; n++ } END { printf "%d %d %d", n + 0, i + 0, d + 0 }')"
# 刻意利用分词拆三元组（STATS 形如 "3 10 5"）
set -- ${STATS}
FILES_CHANGED="$1"
INSERTIONS="$2"
DELETIONS="$3"

if [ "${FILES_CHANGED}" -eq 0 ]; then
    EMPTY=true
else
    EMPTY=false
fi

echo "repo: ${REPO_NAME}"
echo "target_ref: ${TARGET_REF}"
echo "merge_base: ${MERGE_BASE}"
echo "head: ${HEAD_SHA}"
echo "empty: ${EMPTY}"
echo "files_changed: ${FILES_CHANGED}"
echo "insertions: ${INSERTIONS}"
echo "deletions: ${DELETIONS}"
echo "diff_file: ${DIFF_FILE}"
echo "stat_file: ${STAT_FILE}"
