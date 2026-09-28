#!/bin/sh
# space.sh — tack 空间根仓库的框架自动 Git 操作（唯一入口）
#
# 【Git 双层边界】
#   - $root（tack 空间根仓库）：保存 harness/、wiki/、AGENTS.md、
#     space/<branch>/ 下的工作文档（status.yaml、spec.md、plan.md 等）。
#     它的全部 Git 操作由框架自动完成，用户不需要也不允许直接对 $root 执行 git。
#   - 用户的 Git 操作只作用于工作区代码仓库 $work/repo/<repo-name>/（git worktree），
#     由 fetch/commit/push/merge/solve 命令在人工确认下执行。
#     .gitignore 已排除 repo/ 与 space/*/repo/，代码仓库内容永不进入空间仓库。
#
# Usage:
#   sh space.sh commit <root> [message]
#     暂存并提交空间内全部变更（git add -A）；无变更时跳过，退出码恒为 0（无错误时）。
#     若本机未配置任何 git 身份，写入【仓库级 local】框架身份兜底
#     （tack-harness <tack-harness@local>），不触碰用户全局配置，也不触碰代码仓库。

set -e

ACTION="$1"
ROOT="$2"

if [ -z "$ACTION" ] || [ -z "$ROOT" ]; then
    echo "Usage: sh space.sh <commit> <root> [message]" >&2
    exit 1
fi

if [ ! -d "$ROOT/.git" ]; then
    echo "Error: $ROOT 不是 Git 仓库，请先执行 init-tack.sh 初始化" >&2
    exit 1
fi

cd "$ROOT"

case "$ACTION" in
commit)
    MSG="$3"
    if [ -z "$MSG" ]; then
        MSG="chore(tack): auto snapshot $(date '+%Y-%m-%d %H:%M')"
    fi

    # 身份兜底：effective 配置（local 优先，回落 global）缺失时只写仓库级 local。
    # 空间仓库是框架自用仓库，不伪造用户代码仓库的作者信息。
    if ! git config user.name >/dev/null 2>&1; then
        git config user.name "tack-harness"
        git config user.email "tack-harness@local"
    fi

    # 凭据硬门禁：wiki/space 文档命中凭据明文时阻断本次提交（set -e 生效）。
    # 误报处理与 TACK_SECRET_SCAN=off 紧急开关见 scan-secrets.sh 头部说明。
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    sh "$SCRIPT_DIR/scan-secrets.sh" "$ROOT"

    git add -A
    if git diff --cached --quiet; then
        echo "空间仓库无变更，跳过自动提交"
        exit 0
    fi

    git commit -m "$MSG" >/dev/null
    echo "空间仓库已自动提交: $MSG"
    ;;
*)
    echo "Error: 未知动作 '$ACTION'（目前仅支持 commit）" >&2
    exit 1
    ;;
esac
