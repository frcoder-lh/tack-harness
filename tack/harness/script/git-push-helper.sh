#!/bin/sh
# git-push-helper.sh — 单仓库推送的事实采集与机械执行
#
# 脚本只负责仓库状态、机械推送与结构化结果；是否推送、MR/PR 地址与风险解释
# 由 cmd 决定。本脚本拒绝任何 force 参数（多余参数一律按用法错误拒绝）。
#
# Usage:
#   sh git-push-helper.sh inspect <repo-path>
#   sh git-push-helper.sh push <repo-path>
#
# 输出结果行：PUSH_RESULT=ok|first-push|no-upstream-set|non-fast-forward|failed|detached|no-remote|conflict
# 退出码: 0 成功；1 普通失败；2 用法错误；10 存在冲突；
#         11 detached / 无 remote / 无同名远端分支；12 non-fast-forward

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Usage: sh git-push-helper.sh <inspect|push> <repo-path>" >&2
}

ACTION="${1:-}"
REPO="${2:-}"
if [ -z "${ACTION}" ] || [ -z "${REPO}" ]; then
    usage
    exit 2
fi
# 任何额外参数（含 --force/-f/--force-with-lease）都拒绝
if [ $# -gt 2 ]; then
    echo "Error: 不支持额外参数（含任何 force 选项）: $*" >&2
    usage
    exit 2
fi

if [ ! -d "${REPO}" ]; then
    echo "Error: repo path not found: ${REPO}" >&2
    exit 1
fi
if ! git -C "${REPO}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: not a git repository: ${REPO}" >&2
    exit 1
fi

case "${ACTION}" in
inspect)
    set +e
    FACTS="$(sh "${SCRIPT_DIR}/git-facts.sh" status "${REPO}")"
    RC=$?
    set -e
    printf '%s\n' "${FACTS}"
    branch="$(printf '%s\n' "${FACTS}" | awk -F': ' '/^branch:/ { print $2; exit }')"
    remote="$(printf '%s\n' "${FACTS}" | awk -F': ' '/^remote:/ { print $2; exit }')"
    upstream="$(printf '%s\n' "${FACTS}" | awk -F': ' '/^upstream:/ { print $2; exit }')"
    can_push=true
    if [ -z "${remote}" ]; then can_push=false; fi
    if [ -z "${branch}" ]; then can_push=false; fi
    echo "can_push: ${can_push}"
    echo "first_push: $(if [ -z "${upstream}" ] && [ -n "${branch}" ]; then echo true; else echo false; fi)"
    exit "${RC}"
    ;;
push)
    set +e
    FACTS="$(sh "${SCRIPT_DIR}/git-facts.sh" status "${REPO}")"
    RC=$?
    set -e
    if [ "${RC}" -eq 10 ]; then
        echo "Error: 存在未解决冲突，先执行 solve" >&2
        echo "PUSH_RESULT=conflict"
        exit 10
    fi
    branch="$(printf '%s\n' "${FACTS}" | awk -F': ' '/^branch:/ { print $2; exit }')"
    remote="$(printf '%s\n' "${FACTS}" | awk -F': ' '/^remote:/ { print $2; exit }')"
    upstream="$(printf '%s\n' "${FACTS}" | awk -F': ' '/^upstream:/ { print $2; exit }')"
    if [ -z "${branch}" ]; then
        echo "Error: detached HEAD，需人工介入" >&2
        echo "PUSH_RESULT=detached"
        exit 11
    fi
    if [ -z "${remote}" ]; then
        echo "Error: 未配置 remote" >&2
        echo "PUSH_RESULT=no-remote"
        exit 11
    fi

    if [ -n "${upstream}" ]; then
        set +e
        OUT="$(git -C "${REPO}" push 2>&1)"
        rc=$?
        set -e
        if [ "${rc}" -ne 0 ]; then
            printf '%s\n' "${OUT}" >&2
            case "${OUT}" in
                *non-fast-forward*|*"fetch first"*|*"\[rejected\]"*)
                    echo "PUSH_RESULT=non-fast-forward"
                    exit 12
                    ;;
                *)
                    echo "PUSH_RESULT=failed"
                    exit 1
                    ;;
            esac
        fi
        echo "PUSH_RESULT=ok"
        exit 0
    fi

    # 无 upstream：远端同名分支存在则补跟踪后普通推送，否则首次推送建立跟踪
    if git -C "${REPO}" rev-parse --verify --quiet "refs/remotes/${remote}/${branch}" >/dev/null 2>&1; then
        if ! git -C "${REPO}" branch --set-upstream-to="${remote}/${branch}" >/dev/null 2>&1; then
            echo "Error: 设置 upstream 失败: ${remote}/${branch}" >&2
            echo "PUSH_RESULT=no-upstream-set"
            exit 11
        fi
        set +e
        OUT="$(git -C "${REPO}" push 2>&1)"
        rc=$?
        set -e
        if [ "${rc}" -ne 0 ]; then
            printf '%s\n' "${OUT}" >&2
            case "${OUT}" in
                *non-fast-forward*|*"fetch first"*|*"\[rejected\]"*)
                    echo "PUSH_RESULT=non-fast-forward"
                    exit 12
                    ;;
                *)
                    echo "PUSH_RESULT=failed"
                    exit 1
                    ;;
            esac
        fi
        echo "PUSH_RESULT=ok"
        exit 0
    fi

    set +e
    OUT="$(git -C "${REPO}" push -u "${remote}" "${branch}" 2>&1)"
    rc=$?
    set -e
    if [ "${rc}" -ne 0 ]; then
        printf '%s\n' "${OUT}" >&2
        case "${OUT}" in
            *non-fast-forward*|*"fetch first"*|*"\[rejected\]"*)
                echo "PUSH_RESULT=non-fast-forward"
                exit 12
                ;;
            *)
                echo "PUSH_RESULT=failed"
                exit 1
                ;;
        esac
    fi
    echo "PUSH_RESULT=first-push"
    exit 0
    ;;
*)
    usage
    exit 2
    ;;
esac
