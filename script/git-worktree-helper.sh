#!/bin/sh
# git-worktree-helper.sh — Git worktree 辅助脚本
# Usage:
#   sh git-worktree-helper.sh create  <root-path> <branch> <repo-name>
#   sh git-worktree-helper.sh remove  <root-path> <branch>
#   sh git-worktree-helper.sh list    <root-path>

set -e

ACTION="$1"
ROOT="${2:-.}"

if [ -z "$ACTION" ]; then
    echo "Usage: $0 <create|remove|list> <root-path> [branch] [repo-name]"
    exit 1
fi

cd "$ROOT"

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
        WORKTREE_PATH="work/$BRANCH/repo"

        if [ ! -d "$REPO_PATH" ]; then
            echo "Error: Repo not found at $REPO_PATH"
            echo "Run /tack init-repos first."
            exit 1
        fi

        # 检查 worktree 是否已存在
        if git -C "$REPO_PATH" worktree list 2>/dev/null | grep -q "$WORKTREE_PATH"; then
            echo "Worktree already exists: $WORKTREE_PATH"
        else
            echo "Creating worktree: $BRANCH -> $WORKTREE_PATH"
            git -C "$REPO_PATH" worktree add "$WORKTREE_PATH" "$BRANCH" 2>/dev/null
            if [ $? -ne 0 ]; then
                # 尝试基于新分支创建
                echo "Branch doesn't exist yet, creating new branch..."
                git -C "$REPO_PATH" worktree add -b "$BRANCH" "$WORKTREE_PATH"
            fi

            if [ $? -eq 0 ]; then
                echo "Worktree created successfully."
            else
                echo "Failed to create worktree."
                exit 1
            fi
        fi
        ;;

    remove|Remove)
        BRANCH="$3"

        if [ -z "$BRANCH" ]; then
            echo "Error: <branch> is required for remove"
            echo "Usage: $0 remove <root-path> <branch>"
            exit 1
        fi

        WORKTREE_PATH="work/$BRANCH/repo"
        FOUND=0

        # 查找对应的 repo
        for repo_dir in repo/*/; do
            [ -d "$repo_dir" ] || continue
            if git -C "$repo_dir" worktree list 2>/dev/null | grep -q "$WORKTREE_PATH"; then
                echo "Removing worktree from $(basename "$repo_dir")..."
                git -C "$repo_dir" worktree remove --force "$WORKTREE_PATH" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "Worktree removed successfully."
                fi
                FOUND=1
                break
            fi
        done

        if [ "$FOUND" -eq 0 ]; then
            echo "No worktree found at: $WORKTREE_PATH"
        fi
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
