#!/bin/sh
# space.sh — tack 空间根仓库的框架自动 Git 操作（唯一入口）
#
# 【Git 双层边界】
#   - $root（tack 空间根仓库）：保存 harness/、wiki/、AGENTS.md、tack.yaml、
#     space/<YYYYMMDD>-<branch>/ 下的工作文档（status.yaml、context.md、story/、doc/ 等）。
#     它的全部 Git 操作由框架自动完成，用户不需要也不允许直接对 $root 执行 git。
#   - 用户的 Git 操作只作用于工作区代码仓库 $work/repo/<repo-name>/（git worktree），
#     由 fetch/commit/push/merge/solve 命令在用户发起下执行（框架不自动执行）；
#     其中 commit 生成提交信息后直接提交、无需二次确认，push 等远端操作仍需用户明确指令。
#     .gitignore 已排除 repo/ 与 space/*/repo/，代码仓库内容永不进入空间仓库。
#
# Usage:
#   sh space.sh commit <root> [message] <path>...
#     暂存并提交空间内本次任务的文件（.tack/ 运行时目录已被 .gitignore 排除）。
#     路径可为 root 内相对路径或 root 内绝对路径；只暂存清单范围（git add -A -- <path>），
#     提交前校验暂存区不含清单外文件；清单中不存在且未被 Git 跟踪的路径自动跳过。
#     未给文件清单、暂存区已有未提交变更或暂存区出现清单外文件时报错退出；
#     无实际变更时跳过，退出码 0。
#     全部动作在空间级锁内串行执行（见 space-lock.sh），并发提交不会互相冲突或混入。
#     若本机未配置任何 git 身份，写入【仓库级 local】框架身份兜底
#     （tack-harness <tack-harness@local>），不触碰用户全局配置，也不触碰代码仓库。

set -e

ACTION="$1"
ROOT="$2"

if [ -z "${ACTION}" ] || [ -z "${ROOT}" ]; then
    echo "Usage: sh space.sh commit <root> [message] <path>..." >&2
    exit 1
fi

if [ ! -d "${ROOT}/.git" ]; then
    echo "Error: ${ROOT} 不是 Git 仓库，请先执行 init-tack.sh 初始化" >&2
    exit 1
fi

cd "${ROOT}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "${SCRIPT_DIR}/space-lock.sh" ]; then
    echo "Error: 缺少空间锁实现: ${SCRIPT_DIR}/space-lock.sh" >&2
    exit 1
fi
. "${SCRIPT_DIR}/space-lock.sh"

case "${ACTION}" in
commit)
    if [ "$#" -ge 3 ]; then
        MSG="$3"
        if [ "$#" -gt 3 ]; then
            shift 3
        else
            shift $#
        fi
    else
        MSG=""
        shift $#
    fi
    if [ -z "${MSG}" ]; then
        MSG="chore(tack): auto snapshot $(date '+%Y-%m-%d %H:%M')"
    fi
    if [ "$#" -eq 0 ]; then
        echo "Error: commit 需要本次任务的文件清单（相对 ${ROOT} 或根内绝对路径），至少一个" >&2
        exit 1
    fi

    # 空间级锁：串行化登记写入之后的暂存与提交；父进程已持锁时自动跳过
    tack_space_lock_acquire "${ROOT}"

    LIST=""
    STAGED=""
    OUTSIDE=""
    trap 'for _f in "${LIST}" "${STAGED}" "${OUTSIDE}"; do [ -n "${_f}" ] && rm -f "${_f}"; done; tack_space_lock_release' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP

    TMP_DIR="${ROOT}/.tack/tmp"
    mkdir -p "${TMP_DIR}"
    LIST="$(mktemp "${TMP_DIR}/space-commit-list.XXXXXX")"
    STAGED="$(mktemp "${TMP_DIR}/space-commit-staged.XXXXXX")"
    OUTSIDE="$(mktemp "${TMP_DIR}/space-commit-outside.XXXXXX")"
    : > "${LIST}"

    for _p in "$@"; do
        case "${_p}" in
            "${ROOT}/"*) _rel="${_p#"${ROOT}/"}" ;;
            /*) echo "Error: 路径不在空间根内: ${_p}" >&2; exit 1 ;;
            *) _rel="${_p}" ;;
        esac
        case "${_rel}" in
            ""|.|./*|../*|*/../*)
                echo "Error: 非法文件清单路径: ${_p}" >&2
                exit 1
                ;;
        esac
        printf '%s\n' "${_rel}" >> "${LIST}"
    done

    # 只暂存清单中真实存在或被 Git 跟踪的路径；本命令未生成的产物自动跳过
    set --
    while IFS= read -r _rel; do
        [ -n "${_rel}" ] || continue
        if [ -e "${ROOT}/${_rel}" ] || git ls-files --error-unmatch -- "${_rel}" >/dev/null 2>&1; then
            set -- "$@" "${_rel}"
        fi
    done < "${LIST}"
    if [ "$#" -eq 0 ]; then
        echo "空间仓库无变更，跳过自动提交"
        exit 0
    fi

    # 暂存区必须为空：不清洗他人遗留的暂存内容，避免把非本次任务文件带入提交
    if [ -n "$(git diff --cached --name-only)" ]; then
        echo "Error: 暂存区已有未提交变更，拒绝提交（避免混入非本次任务文件）:" >&2
        git diff --cached --name-only | sed 's/^/  /' >&2
        exit 1
    fi

    # 凭据硬门禁：本次全部 Git 变更文件命中凭据明文时阻断提交（set -e 生效）。
    # 误报处理与 TACK_SECRET_SCAN=off 紧急开关见 scan-secrets.sh 头部说明。
    sh "${SCRIPT_DIR}/scan-secrets.sh" "${ROOT}" --changed

    git add -A -- "$@"

    if git diff --cached --quiet; then
        echo "空间仓库无变更，跳过自动提交"
        exit 0
    fi

    # 校验暂存区归属：只允许清单内的文件（或清单目录下的文件），否则拒绝提交
    git diff --cached --name-only > "${STAGED}"
    if ! awk -v L="${LIST}" '
        BEGIN {
            n = 0
            while ((getline a < L) > 0) if (a != "") al[++n] = a
        }
        {
            p = $0
            ok = 0
            for (i = 1; i <= n; i++) {
                a = al[i]
                if (p == a || substr(p, 1, length(a) + 1) == a "/") { ok = 1; break }
            }
            if (!ok) { print p; bad = 1 }
        }
        END { exit (bad ? 1 : 0) }
    ' "${STAGED}" > "${OUTSIDE}"; then
        echo "Error: 暂存区出现本次任务清单外的文件，拒绝提交:" >&2
        cat "${OUTSIDE}" >&2
        echo "       非本次任务的文件未被提交，请核对清单后重试" >&2
        exit 1
    fi

    # 身份兜底：effective 配置（local 优先，回落 global）缺失时只写仓库级 local。
    # 空间仓库是框架自用仓库，不伪造用户代码仓库的作者信息。
    if ! git config user.name >/dev/null 2>&1; then
        git config user.name "tack-harness"
        git config user.email "tack-harness@local"
    fi

    git commit -m "${MSG}" >/dev/null
    echo "空间仓库已自动提交: ${MSG}"
    ;;
*)
    echo "Error: 未知动作 '${ACTION}'（目前仅支持 commit）" >&2
    exit 1
    ;;
esac
