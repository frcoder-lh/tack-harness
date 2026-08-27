#!/bin/sh
# new-req.sh — 新建需求
# Usage: sh new-req.sh <root-path> <branch-name>

set -e

ROOT="${1:-.}"
BRANCH="$2"

if [ -z "$BRANCH" ]; then
    echo "Usage: $0 <root-path> <branch-name>"
    exit 1
fi

# 解析脚本所在目录，定位 template 目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../template" && pwd)"

cd "$ROOT"

# 清理分支名称 (替换特殊字符为下划线)
SAFE_BRANCH=$(echo "$BRANCH" | sed 's/[^a-zA-Z0-9_\-\/]/_/g')
WORK_DIR="work"
BRANCH_DIR="$WORK_DIR/$SAFE_BRANCH"

# 检查是否已存在
if [ -d "$BRANCH_DIR" ]; then
    echo "Branch directory already exists: $BRANCH_DIR"
    echo "Use /tack req-context <prd> to add requirement context."
    exit 0
fi

# 创建目录结构
mkdir -p "$BRANCH_DIR"
echo "Created: work/$SAFE_BRANCH"

for sub in wiki harness plan; do
    mkdir -p "$BRANCH_DIR/$sub"
    echo "  Created: $sub/"
done

# 自动创建 worktree（如果 repo/ 下有 git 仓库）
WORKTREE_CREATED=0
if [ -d "repo" ] && [ -n "$(ls -A repo 2>/dev/null)" ]; then
    for repo_dir in repo/*/; do
        [ -d "$repo_dir" ] || continue
        REPO_NAME=$(basename "$repo_dir")
        if git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
            echo ""
            echo "Detected git repo: $REPO_NAME"
            echo "Creating worktree for branch '$SAFE_BRANCH'..."
            if sh "$SCRIPT_DIR/git-worktree-helper.sh" create "$ROOT" "$SAFE_BRANCH" "$REPO_NAME"; then
                WORKTREE_CREATED=1
                echo "  Created: repo/ (git worktree)"
                break
            fi
        fi
    done
fi

if [ "$WORKTREE_CREATED" -eq 0 ]; then
    # 无 git 仓库，创建占位目录
    mkdir -p "$BRANCH_DIR/repo"
    echo "  Created: repo/ (placeholder)"
fi

# 生成时间戳
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

# 从模板复制 status.yaml 并替换占位符
cp "$TEMPLATE_DIR/work/status.yaml" "$BRANCH_DIR/status.yaml"
sed -i "s/{{BRANCH}}/$BRANCH/g" "$BRANCH_DIR/status.yaml"
sed -i "s/{{CREATED_AT}}/$CREATED_AT/g" "$BRANCH_DIR/status.yaml"
echo "  Created: status.yaml"

# 从 template 复制 repo README（仅占位模式）
if [ "$WORKTREE_CREATED" -eq 0 ]; then
    cp "$TEMPLATE_DIR/work/repo_readme.md" "$BRANCH_DIR/repo/README.md"
    echo "  Created: repo/README.md"
fi

echo ""
echo "Requirement workspace created: work/$SAFE_BRANCH"
echo "Next: /tack req-context <prd-path> to input requirement context."
