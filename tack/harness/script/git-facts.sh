#!/bin/sh
# git-facts.sh — 只读 Git 事实层（命令与脚本共用的确定性事实来源）
#
# 本脚本只采集事实，不做任何写操作；语义判断（是否合并、如何解决冲突、消息内容）
# 仍由 cmd/workflow 完成。
#
# Usage:
#   sh git-facts.sh repos <work-dir>
#     列出 <work-dir>/repo/ 下有效的 git worktree/仓库，TAB 分隔：name<TAB>path
#   sh git-facts.sh status <repo-path>
#     输出 label: value 形式的事实：
#       repo / branch / detached / remote / upstream / ahead / behind /
#       dirty / changed_files / conflicts / operation
#   sh git-facts.sh default-branch <repo-path>
#     输出默认主干名（origin/HEAD 优先，其次 main / master）
#   sh git-facts.sh conflicts <repo-path>
#     输出未解决冲突文件（一行一个，相对仓库路径）
#   sh git-facts.sh freshness <repo-path> <base-commit>
#     文档/分支相对基准 commit 的新鲜度：
#       head / base / ahead / behind / fresh（behind=0 时 fresh=true）
#
# 退出码（统一事实层协议）:
#   0  成功取得事实
#   1  执行失败、路径无效或文件损坏
#   2  调用参数错误
#   3  目标不存在或无匹配项
#   10 存在冲突，需要语义处理
#   11 缺少 remote、upstream 或默认主干，需要介入

set -eu

usage() {
    echo "Usage: sh git-facts.sh <repos|status|default-branch|conflicts|freshness> <args...>" >&2
}

ACTION="${1:-}"
[ -n "${ACTION}" ] || { usage; exit 2; }

require_repo() {
    if [ -z "${1:-}" ] || [ ! -d "${1}" ]; then
        echo "Error: repo path not found: ${1:-}" >&2
        exit 1
    fi
    if ! git -C "$1" rev-parse --git-dir >/dev/null 2>&1; then
        echo "Error: not a git repository: $1" >&2
        exit 1
    fi
}

count_conflicts() {
    git -C "$1" diff --name-only --diff-filter=U 2>/dev/null | grep -c . 2>/dev/null || true
}

operation_of() {
    gitdir="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null || true)"
    if [ -z "${gitdir}" ]; then
        echo "none"
    elif [ -f "${gitdir}/MERGE_HEAD" ]; then
        echo "merge"
    elif [ -d "${gitdir}/rebase-merge" ] || [ -d "${gitdir}/rebase-apply" ]; then
        echo "rebase"
    elif [ -f "${gitdir}/CHERRY_PICK_HEAD" ]; then
        echo "cherry-pick"
    elif [ -f "${gitdir}/REVERT_HEAD" ]; then
        echo "revert"
    else
        echo "none"
    fi
}

case "${ACTION}" in
repos)
    WORK_DIR="${2:-}"
    if [ -z "${WORK_DIR}" ] || [ ! -d "${WORK_DIR}" ]; then
        echo "Error: work dir not found: ${WORK_DIR}" >&2
        exit 2
    fi
    found=0
    for d in "${WORK_DIR}/repo"/*/; do
        [ -d "${d}" ] || continue
        [ -e "${d}/.git" ] || continue
        if git -C "${d}" rev-parse --git-dir >/dev/null 2>&1; then
            printf '%s\t%s\n' "$(basename "${d}")" "${d%/}"
            found=1
        fi
    done
    [ "${found}" -eq 1 ] || exit 3
    exit 0
    ;;
status)
    REPO="${2:-}"
    require_repo "${REPO}"
    branch="$(git -C "${REPO}" symbolic-ref --short HEAD 2>/dev/null || true)"
    if [ -n "${branch}" ]; then detached=false; else detached=true; branch=""; fi
    remote="$(git -C "${REPO}" remote 2>/dev/null | head -n 1 || true)"
    upstream="$(git -C "${REPO}" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
    [ "${upstream}" = "@{upstream}" ] && upstream=""
    ahead=0; behind=0
    if [ -n "${upstream}" ]; then
        ab="$(git -C "${REPO}" rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null || echo "0 0")"
        behind="$(printf '%s' "${ab}" | awk '{print $1}')"
        ahead="$(printf '%s' "${ab}" | awk '{print $2}')"
    fi
    changed="$(git -C "${REPO}" status --porcelain 2>/dev/null | grep -c . 2>/dev/null || true)"
    changed="${changed:-0}"
    if [ "${changed}" -gt 0 ]; then dirty=true; else dirty=false; fi
    conflicts="$(count_conflicts "${REPO}")"
    conflicts="${conflicts:-0}"
    operation="$(operation_of "${REPO}")"
    echo "repo: $(basename "${REPO}")"
    echo "branch: ${branch}"
    echo "detached: ${detached}"
    echo "remote: ${remote}"
    echo "upstream: ${upstream}"
    echo "ahead: ${ahead}"
    echo "behind: ${behind}"
    echo "dirty: ${dirty}"
    echo "changed_files: ${changed}"
    echo "conflicts: ${conflicts}"
    echo "operation: ${operation}"
    [ "${conflicts}" -gt 0 ] && exit 10
    exit 0
    ;;
default-branch)
    REPO="${2:-}"
    require_repo "${REPO}"
    ref="$(git -C "${REPO}" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    if [ -n "${ref}" ]; then
        echo "${ref#origin/}"
        exit 0
    fi
    for b in main master; do
        if git -C "${REPO}" rev-parse --verify --quiet "refs/remotes/origin/${b}" >/dev/null 2>&1 \
            || git -C "${REPO}" rev-parse --verify --quiet "refs/heads/${b}" >/dev/null 2>&1; then
            echo "${b}"
            exit 0
        fi
    done
    echo "Error: cannot determine default branch in ${REPO}" >&2
    exit 11
    ;;
conflicts)
    REPO="${2:-}"
    require_repo "${REPO}"
    files="$(git -C "${REPO}" diff --name-only --diff-filter=U 2>/dev/null || true)"
    if [ -z "${files}" ]; then
        exit 0
    fi
    printf '%s\n' "${files}"
    exit 10
    ;;
freshness)
    REPO="${2:-}"
    BASE="${3:-}"
    if [ -z "${BASE}" ]; then
        usage
        exit 2
    fi
    require_repo "${REPO}"
    if ! base_sha="$(git -C "${REPO}" rev-parse --verify --quiet "${BASE}^{commit}" 2>/dev/null)"; then
        echo "Error: base commit not found: ${BASE}" >&2
        exit 3
    fi
    if ! head_sha="$(git -C "${REPO}" rev-parse --verify HEAD 2>/dev/null)"; then
        echo "Error: HEAD not found in ${REPO}" >&2
        exit 3
    fi
    ahead="$(git -C "${REPO}" rev-list --count "${base_sha}..HEAD")"
    behind="$(git -C "${REPO}" rev-list --count "HEAD..${base_sha}")"
    if [ "${behind}" -eq 0 ]; then fresh=true; else fresh=false; fi
    echo "head: ${head_sha}"
    echo "base: ${base_sha}"
    echo "ahead: ${ahead}"
    echo "behind: ${behind}"
    echo "fresh: ${fresh}"
    exit 0
    ;;
*)
    usage
    exit 2
    ;;
esac
