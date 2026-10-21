#!/bin/sh
# git-commit-helper.sh — 单仓库提交的事实采集与机械执行
#
# 脚本只负责仓库状态、机械提交与结构化结果；阅读 diff、生成 Conventional Commit
# message、决定多仓库策略等语义工作由 cmd 完成。
#
# Usage:
#   sh git-commit-helper.sh inspect <repo-path>
#     输出 git-facts.sh status 的全部事实，并追加：
#       staged_files / unstaged_files / untracked_files / has_staged
#   sh git-commit-helper.sh commit <repo-path> <message>
#     仅提交已暂存内容（不自动 add）；成功后输出 COMMIT=<hash> 与 COMMIT_RESULT=ok
#
# 退出码: 0 成功；1 执行失败；2 用法错误；3 无可提交内容；
#         10 存在冲突；11 detached HEAD（需人工介入）

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Usage: sh git-commit-helper.sh <inspect|commit> <repo-path> [message]" >&2
}

ACTION="${1:-}"
REPO="${2:-}"
[ -n "${ACTION}" ] && [ -n "${REPO}" ] || { usage; exit 2; }

if [ ! -d "${REPO}" ]; then
    echo "Error: repo path not found: ${REPO}" >&2
    exit 1
fi
if ! git -C "${REPO}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: not a git repository: ${REPO}" >&2
    exit 1
fi

count_lines() {
    grep -c . 2>/dev/null || true
}

case "${ACTION}" in
inspect)
    set +e
    FACTS="$(sh "${SCRIPT_DIR}/git-facts.sh" status "${REPO}")"
    RC=$?
    set -e
    printf '%s\n' "${FACTS}"
    staged="$(git -C "${REPO}" diff --cached --name-only 2>/dev/null | count_lines)"
    unstaged="$(git -C "${REPO}" diff --name-only 2>/dev/null | count_lines)"
    untracked="$(git -C "${REPO}" ls-files --others --exclude-standard 2>/dev/null | count_lines)"
    staged="${staged:-0}"; unstaged="${unstaged:-0}"; untracked="${untracked:-0}"
    if [ "${staged}" -gt 0 ]; then has_staged=true; else has_staged=false; fi
    echo "staged_files: ${staged}"
    echo "unstaged_files: ${unstaged}"
    echo "untracked_files: ${untracked}"
    echo "has_staged: ${has_staged}"
    exit "${RC}"
    ;;
commit)
    MSG="${3:-}"
    if [ -z "${MSG}" ]; then
        echo "Usage: sh git-commit-helper.sh commit <repo-path> <message>" >&2
        exit 2
    fi
    if [ -n "$(git -C "${REPO}" diff --name-only --diff-filter=U 2>/dev/null)" ]; then
        echo "Error: 存在未解决冲突，先执行 solve" >&2
        echo "COMMIT_RESULT=conflict"
        exit 10
    fi
    if ! git -C "${REPO}" symbolic-ref --short HEAD >/dev/null 2>&1; then
        echo "Error: detached HEAD，需人工介入" >&2
        echo "COMMIT_RESULT=detached"
        exit 11
    fi
    if git -C "${REPO}" diff --cached --quiet 2>/dev/null; then
        echo "Error: 没有已暂存内容（脚本不自动 add）" >&2
        echo "COMMIT_RESULT=nothing-staged"
        exit 3
    fi
    if ! git -C "${REPO}" commit -m "${MSG}" >/dev/null; then
        echo "Error: git commit 失败" >&2
        echo "COMMIT_RESULT=failed"
        exit 1
    fi
    echo "COMMIT=$(git -C "${REPO}" rev-parse HEAD)"
    echo "COMMIT_RESULT=ok"
    exit 0
    ;;
*)
    usage
    exit 2
    ;;
esac
