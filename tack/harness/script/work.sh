#!/bin/sh
# work.sh — 新建工作区（space/<branch>/）
#
# Usage:
#   sh work.sh <root> <branch> [repo-name ...]
#     repo-name 可传多个；不传则默认为 root/repo 下的全部仓库创建 worktree
#
# 工作区结构（扁平，工作区级文档放 wiki/）：
#   space/<branch>/
#   ├── status.yaml        # 工作区状态（属性 + 当前任务/进度/下一步），由模板复制 + sed 替换
#   ├── input.md           # 原始需求输入
#   ├── wiki/              # 工作区级代码理解产物（ask 命令产出，如 <repo>-analysis.md、问答文档）
#   └── repo/<repo-name>/  # 各仓库的 git worktree（无仓库时为占位目录）
#
# 注意：本脚本只负责目录、模板文件与 worktree；
#       在 AGENTS.md 项目信息区块登记工作条目由 project.sh work-add 完成（见 work 命令）。

set -e

ROOT="${1:-.}"
BRANCH="$2"

if [ -z "$BRANCH" ]; then
    echo "Usage: sh work.sh <root> <branch> [repo-name ...]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 工作区模板位于 harness/template/（文件复制 + sed 占位替换，不做字符串拼接）
TEMPLATE_DIR="$SCRIPT_DIR/../template"

cd "$ROOT"

# 分支名安全化（只保留字母数字 _ - /；- 置于字符类末尾按字面量处理，/ 不需转义）
SAFE_BRANCH=$(echo "$BRANCH" | sed 's/[^a-zA-Z0-9/_-]/_/g')
BRANCH_DIR="space/$SAFE_BRANCH"

if [ -d "$BRANCH_DIR" ]; then
    echo "工作区已存在: $BRANCH_DIR"
    exit 0
fi

# 1. 目录骨架（工作区级文档放 wiki/；仅预建 repo 占位）
mkdir -p "$BRANCH_DIR/repo" "$BRANCH_DIR/wiki"
echo "已创建: $BRANCH_DIR/"

# 2. 确定要建 worktree 的仓库列表
shift 2
REPO_NAMES="$*"
if [ -z "$REPO_NAMES" ] && [ -d "repo" ]; then
    REPO_NAMES=$(ls -1 "repo" 2>/dev/null)
fi

# 3. 逐仓库创建 worktree
WORKTREE_CREATED=0
if [ -n "$REPO_NAMES" ]; then
    for name in $REPO_NAMES; do
        if [ -d "repo/$name" ] && git -C "repo/$name" rev-parse --git-dir >/dev/null 2>&1; then
            echo "为仓库 '$name' 创建 worktree（分支 $SAFE_BRANCH）..."
            if sh "$SCRIPT_DIR/git-worktree-helper.sh" create "$ROOT" "$SAFE_BRANCH" "$name"; then
                WORKTREE_CREATED=1
            fi
        else
            echo "跳过（不是有效 git 仓库）: repo/$name"
        fi
    done
fi

# 4. 无可用仓库时保留空 repo/ 占位目录
if [ "$WORKTREE_CREATED" -eq 0 ]; then
    echo "提示: $BRANCH_DIR/repo/ 为占位目录（当前无可用 git 仓库，稍后可用 worktree 命令补建）"
fi

# 5. status.yaml + input.md（模板复制 + sed 占位替换）
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
if [ -f "$TEMPLATE_DIR/work-status.yaml" ]; then
    cp "$TEMPLATE_DIR/work-status.yaml" "$BRANCH_DIR/status.yaml"
    sed -i.bak "s/{{BRANCH}}/$SAFE_BRANCH/g; s/{{CREATED_AT}}/$CREATED_AT/g" "$BRANCH_DIR/status.yaml"
    rm -f "$BRANCH_DIR/status.yaml.bak"
    echo "已创建: status.yaml"
else
    echo "Warn: 未找到 work-status.yaml，status.yaml 未生成" >&2
fi
if [ -f "$TEMPLATE_DIR/work-input.md" ]; then
    cp "$TEMPLATE_DIR/work-input.md" "$BRANCH_DIR/input.md"
    echo "已创建: input.md"
else
    echo "Warn: 未找到 work-input.md，input.md 未生成" >&2
fi

echo ""
echo "工作区已就绪: space/$SAFE_BRANCH"

# 框架自动提交空间仓库（space/*/repo/ 已被 .gitignore 排除，只提交工作区文档）
sh "$SCRIPT_DIR/space.sh" commit "$ROOT" "chore(tack): create workspace $SAFE_BRANCH"

echo "下一步: 1) 执行 project.sh work-add 登记工作  2) 向 input.md 录入原始需求  3) 执行 spec"
