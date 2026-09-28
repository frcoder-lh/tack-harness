#!/bin/sh
# git-worktree-helper.sh — Git worktree 辅助脚本
#
# 多仓库布局：每个仓库的 worktree 位于 space/<branch>/repo/<repo-name>
#
# Usage:
#   sh git-worktree-helper.sh create <root-path> <branch> <repo-name>
#   sh git-worktree-helper.sh remove <root-path> <branch> [repo-name]
#   sh git-worktree-helper.sh list   <root-path>

set -e

ACTION="$1"
ROOT="${2:-.}"

if [ -z "$ACTION" ]; then
    echo "Usage: $0 <create|remove|list> <root-path> [branch] [repo-name]"
    exit 1
fi

cd "$ROOT"
# 绝对根路径：git -C 会改变相对路径的解析基准，worktree 路径必须用绝对路径
ABS_ROOT="$(pwd)"

case "$ACTION" in
    create|Create)
        BRANCH="$3"
        REPO_NAME="$4"

        if [ -z "$BRANCH" ] || [ -z "$REPO_NAME" ]; then
            echo "Error: <branch> and <repo-name> are required for create"
            echo "Usage: $0 create <root-path> <branch> <repo-name>"
            exit 1
        fi

        REPO_PATH="repo/$REPO_NAME"
        WORKTREE_PATH="$ABS_ROOT/space/$BRANCH/repo/$REPO_NAME"

        if [ ! -d "$REPO_PATH" ]; then
            echo "Error: Repo not found at $REPO_PATH"
            echo "Run /tack init first."
            exit 1
        fi

        # 存在性以目录为准（不依赖 worktree list 文本——Git for Windows 输出的是 C:/ 形式，
        # 而 MSYS shell 内是 /tmp 形式，字符串匹配会失效）
        if [ -d "$WORKTREE_PATH" ]; then
            echo "Worktree already exists: $WORKTREE_PATH"
        else
            echo "Creating worktree: $BRANCH -> $WORKTREE_PATH"
            mkdir -p "$ABS_ROOT/space/$BRANCH/repo"
            if git -C "$REPO_PATH" worktree add "$WORKTREE_PATH" "$BRANCH" 2>/dev/null; then
                echo "Worktree created successfully."
            else
                echo "Branch doesn't exist yet, creating new branch..."
                git -C "$REPO_PATH" worktree add -b "$BRANCH" "$WORKTREE_PATH"
            fi
        fi
        ;;

    remove|Remove)
        BRANCH="$3"
        REPO_NAME="$4"

        if [ -z "$BRANCH" ]; then
            echo "Error: <branch> is required for remove"
            echo "Usage: $0 remove <root-path> <branch> [repo-name]"
            exit 1
        fi

        # 指定仓库只处理该仓库；否则遍历 root/repo 下全部仓库
        if [ -n "$REPO_NAME" ]; then
            set -- "$REPO_NAME"
        else
            set -- $(ls -1 repo 2>/dev/null)
        fi

        FOUND=0
        for name in "$@"; do
            repo_dir="repo/$name"
            [ -d "$repo_dir" ] || continue
            WT="$ABS_ROOT/space/$BRANCH/repo/$name"
            # 同样以目录存在为准；直接让 git 执行 remove，失败则 prune 登记信息
            if [ -d "$WT" ]; then
                echo "Removing worktree from $name..."
                if git -C "$repo_dir" worktree remove --force "$WT" 2>/dev/null; then
                    echo "  removed: $WT"
                    FOUND=1
                else
                    echo "  git remove 失败，尝试 prune 登记信息"
                    git -C "$repo_dir" worktree prune 2>/dev/null
                fi
            fi
        done

        [ "$FOUND" -eq 1 ] || echo "No worktree found for branch: $BRANCH"
        ;;

    list|List)
        if [ ! -d "repo" ] || [ -z "$(ls -A repo 2>/dev/null)" ]; then
            echo "No repos found in repo/ directory."
            exit 0
        fi

        echo ""
        echo "Git Worktrees:"
        echo "=============="

        for repo_dir in repo/*/; do
            [ -d "$repo_dir" ] || continue
            echo ""
            echo "[$(basename "$repo_dir")]"
            git -C "$repo_dir" worktree list 2>/dev/null || echo "  (no worktrees)"
        done
        ;;

    *)
        echo "Error: Unknown action '$ACTION'"
        echo "Valid actions: create, remove, list"
        exit 1
        ;;
esac
