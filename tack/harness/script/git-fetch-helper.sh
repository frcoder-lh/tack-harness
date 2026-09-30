#!/bin/sh
# git-fetch-helper.sh — 仓库远端同步辅助脚本
#
# 单仓库内顺序执行：fetch -> 检查并修复上游跟踪 -> pull -> 汇报状态
# 上游目标固定为 origin/<同当前分支名>：
#   - 已正确跟踪同名分支：直接通过
#   - 缺失上游 / 跟踪了不同名分支：远端同名分支存在时自动改为跟踪同名分支
#   - 远端无同当前分支名：停止并列出候选分支（避免从错误的上游 pull）
#
# Usage:
#   sh git-fetch-helper.sh sync <repo-path>

set -e

ACTION="$1"
REPO_PATH="$2"

if [ "$ACTION" != "sync" ] || [ -z "$REPO_PATH" ]; then
    echo "Usage: $0 sync <repo-path>" >&2
    exit 2
fi

if [ ! -d "$REPO_PATH" ]; then
    echo "Error: repo path not found: $REPO_PATH" >&2
    exit 1
fi

# 必须是 git 仓库（worktree 或普通仓库）
if ! git -C "$REPO_PATH" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: not a git repository: $REPO_PATH" >&2
    exit 1
fi

# 当前分支名；detached HEAD 时退出
BRANCH=$(git -C "$REPO_PATH" symbolic-ref --short HEAD 2>/dev/null || true)
if [ -z "$BRANCH" ]; then
    echo "Error: detached HEAD in $REPO_PATH, skip sync." >&2
    exit 1
fi

echo "=== $REPO_PATH (branch: $BRANCH) ==="

# 1) 拉取远端
echo "[1/4] git fetch --all --prune"
git -C "$REPO_PATH" fetch --all --prune

# 2) 检查并修复上游跟踪（目标固定为 origin/<当前分支名>）
#    rev-parse 在无上游时退出非零且无 stdout 输出；用 || true 兜底为空字符串
UPSTREAM=$(git -C "$REPO_PATH" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
if [ "$UPSTREAM" = '@{upstream}' ]; then
    UPSTREAM=""
fi

if [ "$UPSTREAM" = "origin/$BRANCH" ]; then
    echo "[2/4] upstream tracking ok: $UPSTREAM"
elif git -C "$REPO_PATH" rev-parse --verify "refs/remotes/origin/$BRANCH" >/dev/null 2>&1; then
    # 上游缺失，或跟踪的是不同名分支：远端同名分支存在，统一改为跟踪同名分支
    if [ -z "$UPSTREAM" ]; then
        echo "[2/4] no upstream tracking, setting to origin/$BRANCH"
    else
        echo "[2/4] upstream '$UPSTREAM' differs from local branch '$BRANCH', resetting to origin/$BRANCH"
    fi
    git -C "$REPO_PATH" branch --set-upstream-to="origin/$BRANCH"
    echo "  upstream set: origin/$BRANCH"
else
    echo "  Error: origin/$BRANCH not found on remote, cannot track same-name branch." >&2
    if [ -n "$UPSTREAM" ]; then
        echo "  Current upstream '$UPSTREAM' differs from local branch; pull aborted to avoid merging wrong branch." >&2
    fi
    echo "  Candidate remote branches (first 20):" >&2
    git -C "$REPO_PATH" branch -r 2>/dev/null | head -n 20 >&2 || true
    echo "  Push first: git push -u origin $BRANCH  —  or set upstream manually:" >&2
    echo "  git -C $REPO_PATH branch --set-upstream-to=origin/<branch>" >&2
    exit 1
fi

# 3) 拉取并合并
echo "[3/4] git pull"
if ! git -C "$REPO_PATH" pull; then
    echo "  git pull failed (likely merge conflict). Resolve via /tack solve" >&2
    exit 1
fi

# 4) 汇报状态
echo "[4/4] status:"
git -C "$REPO_PATH" status -sb
