#!/bin/sh
# repo.sh — 代码仓库接入（扫描本地 / 软链已有 / 克隆远端）
#
# Usage:
#   sh repo.sh scan  <root> <scan-dir>         # 深度 <= 5 扫描本地 git 仓库，逐行输出绝对路径
#   sh repo.sh link  <root> <local-path> ...   # 将本地仓库软链到 <root>/repo/<repo-name>
#   sh repo.sh clone <root> <git-url>  ...     # 克隆远端仓库到 <root>/repo/<repo-name>
#                                                     clone 支持 -force 覆盖已存在仓库

set -e

ACTION="$1"
ROOT="$2"

if [ -z "$ACTION" ] || [ -z "$ROOT" ]; then
    echo "Usage: sh repo.sh <scan|link|clone> <root> [args...]" >&2
    exit 1
fi

# 解析仓库名：路径末段，去掉 .git
get_repo_name() {
    name="${1##*/}"
    name="${name%.git}"
    echo "$name"
}

case "$ACTION" in

    scan)
        SCAN_DIR="$3"
        if [ -z "$SCAN_DIR" ] || [ ! -d "$SCAN_DIR" ]; then
            echo "Error: 扫描目录不存在: $SCAN_DIR" >&2
            exit 1
        fi
        # -maxdepth 5：只向下最多 5 层；-prune 避免钻进仓库内部继续扫描
        find "$SCAN_DIR" -maxdepth 5 -type d -name .git -prune 2>/dev/null | while IFS= read -r gitdir; do
            dirname "$gitdir"
        done
        ;;

    link)
        shift 2
        if [ $# -lt 1 ]; then
            echo "Usage: sh repo.sh link <root> <local-path> ..." >&2
            exit 1
        fi
        mkdir -p "$ROOT/repo"
        for src in "$@"; do
            [ -d "$src" ] || { echo "跳过（目录不存在）: $src"; continue; }
            abs="$(cd "$src" && pwd)"
            name=$(get_repo_name "$abs")
            target="$ROOT/repo/$name"
            if [ -e "$target" ]; then
                echo "已存在，跳过: repo/$name"
                continue
            fi
            ln -s "$abs" "$target" && echo "已软链: repo/$name -> $abs"
        done
        ;;

    clone)
        shift 2
        if [ $# -lt 1 ]; then
            echo "Usage: sh repo.sh clone <root> <git-url> ... [-force]" >&2
            exit 1
        fi
        mkdir -p "$ROOT/repo"

        FORCE=0
        for arg in "$@"; do
            [ "$arg" = "-force" ] || [ "$arg" = "--force" ] && FORCE=1
        done

        for repo in "$@"; do
            [ "$repo" = "-force" ] || [ "$repo" = "--force" ] && continue

            repo_name=$(get_repo_name "$repo")
            target_dir="$ROOT/repo/$repo_name"

            if [ -d "$target_dir" ]; then
                if [ "$FORCE" -eq 1 ]; then
                    echo "覆盖已有仓库: $repo_name"
                    rm -rf "$target_dir"
                else
                    echo "仓库已存在: $repo_name（加 -force 可重新克隆），尝试拉取更新..."
                    git -C "$target_dir" pull 2>/dev/null || echo "  拉取失败，跳过"
                    continue
                fi
            fi

            echo "克隆: $repo -> repo/$repo_name"
            if git clone "$repo" "$target_dir"; then
                echo "  成功: $repo_name"
            else
                echo "  失败: $repo_name"
                rm -rf "$target_dir" 2>/dev/null
            fi
        done
        ;;

    *)
        echo "Error: 未知动作 '$ACTION'（支持 scan / link / clone）" >&2
        exit 1
        ;;
esac
