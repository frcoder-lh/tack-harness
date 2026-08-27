#!/bin/sh
# init-repos.sh — 初始化代码仓库
# Usage: sh init-repos.sh <root-path> <repo1> [repo2] ...

set -e

ROOT="${1:-.}"
shift

if [ $# -lt 1 ]; then
    echo "Usage: $0 <root-path> <repo1> [repo2] ..."
    echo "  repo can be a git URL or a local directory path"
    exit 1
fi

cd "$ROOT"
REPO_DIR="repo"

if [ ! -d "$REPO_DIR" ]; then
    mkdir -p "$REPO_DIR"
fi

# 解析仓库名：从路径末尾提取，去掉 .git 后缀
get_repo_name() {
    repo="$1"
    name="${repo##*/}"
    name="${name%.git}"
    echo "$name"
}

FORCE=0
# 检查是否有 -force 标志
for arg in "$@"; do
    if [ "$arg" = "-force" ] || [ "$arg" = "--force" ]; then
        FORCE=1
    fi
done

for repo in "$@"; do
    # 跳过 -force 参数
    if [ "$repo" = "-force" ] || [ "$repo" = "--force" ]; then
        continue
    fi

    repo_name=$(get_repo_name "$repo")
    target_dir="$REPO_DIR/$repo_name"

    if [ -d "$target_dir" ]; then
        if [ "$FORCE" -eq 1 ]; then
            echo "Removing existing repo: $repo_name"
            rm -rf "$target_dir"
        else
            echo "Repo exists: $repo_name (use -force to re-clone)"
            echo "  Pulling latest changes..."
            git -C "$target_dir" pull 2>/dev/null || echo "  Pull failed, skipping."
            continue
        fi
    fi

    echo "Cloning: $repo -> $target_dir"

    # 判断是本地路径还是 git URL
    if [ -d "$repo" ] || [ -d "$repo/.git" ]; then
        # 本地仓库：直接复制
        cp -r "$repo" "$target_dir" 2>/dev/null || {
            echo "  Local copy failed, trying git clone..."
            git clone "$repo" "$target_dir"
        }
    else
        # Git URL
        git clone "$repo" "$target_dir"
    fi

    if [ $? -eq 0 ]; then
        echo "  Success: $repo_name"
    else
        echo "  Failed: $repo_name"
        # 清理失败的目录
        rm -rf "$target_dir" 2>/dev/null
    fi
done

echo ""
echo "Repos initialized in: $(pwd)/$REPO_DIR"
