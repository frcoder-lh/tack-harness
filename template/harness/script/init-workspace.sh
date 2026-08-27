#!/bin/sh
# init-workspace.sh — 初始化工作区目录结构
# Usage: sh harness/script/init-workspace.sh <root-path>
#
# 从 skill 的 template/ 复制模板文件到项目中

set -e

ROOT="${1:-.}"

if [ -z "$ROOT" ]; then
    echo "Usage: $0 <root-path>"
    exit 1
fi

# 解析脚本所在目录，定位 template 目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../template" && pwd)"

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "Error: template directory not found at $TEMPLATE_DIR"
    exit 1
fi

cd "$ROOT"

# 定义目录结构
DIRS="wiki harness harness/rule harness/doc harness/script work repo"

# 创建目录
for dir in $DIRS; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo "Created: $dir"
    else
        echo "Exists: $dir"
    fi
done

# 从 template 目录复制模板文件
# 使用 cp -r 保持目录结构，只在目标文件不存在时复制
copy_if_missing() {
    src="$1"
    dst="$2"
    if [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        echo "Created: $dst"
    else
        echo "Exists: $dst"
    fi
}

# 根目录文件
copy_if_missing "$TEMPLATE_DIR/AGENTS.md" "AGENTS.md"
copy_if_missing "$TEMPLATE_DIR/.gitignore" ".gitignore"

# wiki/
copy_if_missing "$TEMPLATE_DIR/wiki/manifest.md" "wiki/manifest.md"
copy_if_missing "$TEMPLATE_DIR/wiki/business-understanding.md" "wiki/business-understanding.md"
copy_if_missing "$TEMPLATE_DIR/wiki/code-understanding.md" "wiki/code-understanding.md"

# harness/rule/
copy_if_missing "$TEMPLATE_DIR/harness/rule/coding-standards.md" "harness/rule/coding-standards.md"

# harness/doc/
copy_if_missing "$TEMPLATE_DIR/harness/doc/prd-template.md" "harness/doc/prd-template.md"
copy_if_missing "$TEMPLATE_DIR/harness/doc/tech-design-template.md" "harness/doc/tech-design-template.md"
copy_if_missing "$TEMPLATE_DIR/harness/doc/test-plan-template.md" "harness/doc/test-plan-template.md"

# harness/script/ (脚本也从模板复制)
copy_if_missing "$TEMPLATE_DIR/harness/script/init-workspace.sh" "harness/script/init-workspace.sh"
copy_if_missing "$TEMPLATE_DIR/harness/script/init-repos.sh" "harness/script/init-repos.sh"
copy_if_missing "$TEMPLATE_DIR/harness/script/new-req.sh" "harness/script/new-req.sh"
copy_if_missing "$TEMPLATE_DIR/harness/script/git-worktree-helper.sh" "harness/script/git-worktree-helper.sh"

# harness/rule/ — 开发流程说明
copy_if_missing "$TEMPLATE_DIR/harness/rule/development-workflow.md" "harness/rule/development-workflow.md"

# harness/template/work/ — 需求工作区模板（供 new-req.sh 引用）
mkdir -p "harness/template/work"
copy_if_missing "$TEMPLATE_DIR/work/repo_readme.md" "harness/template/work/repo_readme.md"
copy_if_missing "$TEMPLATE_DIR/work/status.yaml" "harness/template/work/status.yaml"

echo ""
echo "Workspace initialized at: $(pwd)"
echo "Run /tack init-context next to set up global context."