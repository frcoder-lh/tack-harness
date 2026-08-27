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

for sub in wiki harness plan repo; do
    mkdir -p "$BRANCH_DIR/$sub"
    echo "  Created: $sub/"
done

# 生成时间戳
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

# 从模板复制 status.yaml 并替换占位符
cp "$TEMPLATE_DIR/work/status.yaml" "$BRANCH_DIR/status.yaml"
sed -i "s/{{BRANCH}}/$BRANCH/g" "$BRANCH_DIR/status.yaml"
sed -i "s/{{CREATED_AT}}/$CREATED_AT/g" "$BRANCH_DIR/status.yaml"
echo "  Created: status.yaml"

# 从 template 复制 repo README
cp "$TEMPLATE_DIR/work/repo_readme.md" "$BRANCH_DIR/repo/README.md"
echo "  Created: repo/README.md"

echo ""
echo "Requirement workspace created: work/$SAFE_BRANCH"
echo "Next: /tack req-context <prd-path> to input requirement context."
