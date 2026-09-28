#!/bin/sh
# release.sh — 发布新版本
#
# 流程：
#   1) 将本地所有「未推送到远程」的 commit 压缩为一个 commit（soft reset 到
#      origin/<branch>，新提交父节点仍是远端分支头 → 推送为 fast-forward，
#      不使用 force）；被压缩的提交清单保留在新 commit 的 body 中；
#   2) 打 annotated tag（Vx.y.z，匹配 .github/workflows/release.yml 触发规则）；
#   3) 推送分支与 tag；tag 推送后由 CI 自动创建 GitHub Release。
#
# Usage:
#   sh release.sh                     自动递增 patch（基于最新本地 tag）
#   sh release.sh V0.0.2              指定版本号（亦可写 0.0.2，自动补 V）
#   sh release.sh -m "feat: xxx"      指定压缩后的提交信息
#   sh release.sh -y                  跳过确认
#   sh release.sh -n                  dry-run，仅打印发布计划
#
# 前置条件：
#   - 工作区干净（无未提交 / 未跟踪文件）；
#   - 当前分支已存在对应远端分支 origin/<branch>；
#   - 远端没有本地缺失的提交（否则请先 rebase / merge）。
#
# 若执行后反悔，压缩前的提交可通过 reflog 找回，例如：
#   git reflog && git reset --hard <旧提交哈希>

set -eu

REMOTE="origin"
TAG_INPUT=""
MSG=""
ASSUME_YES=0
DRY_RUN=0

usage() {
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -m)
            [ $# -ge 2 ] || { echo "错误：-m 需要参数" >&2; exit 1; }
            MSG="$2"; shift 2 ;;
        -y|--yes)
            ASSUME_YES=1; shift ;;
        -n|--dry-run)
            DRY_RUN=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        --)
            shift; break ;;
        -*)
            echo "错误：未知选项 $1" >&2; usage; exit 1 ;;
        *)
            TAG_INPUT="$1"; shift ;;
    esac
done

# —— 0. 基本检查 ——
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "错误：当前目录不在 Git 仓库内" >&2; exit 1
}
cd "$repo_root"

if [ -n "$(git status --porcelain)" ]; then
    echo "错误：工作区不干净，请先提交 / 暂存 / 清理以下改动：" >&2
    git status -s >&2
    exit 1
fi

branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
    echo "错误：当前处于 detached HEAD 状态，请先切到分支" >&2; exit 1
}
base="$REMOTE/$branch"

echo ">> 同步远端引用（git fetch $REMOTE --tags）"
git fetch "$REMOTE" --tags --quiet

if ! git rev-parse --verify --quiet "$base" >/dev/null; then
    echo "错误：远端分支 $base 不存在，请先执行 git push -u $REMOTE $branch" >&2
    exit 1
fi

# 远端有本地缺失的提交：soft reset 会丢失远端新提交的线索，必须先处理
behind=$(git rev-list --count "HEAD..$base")
if [ "$behind" -gt 0 ]; then
    echo "错误：$base 有 $behind 个本地没有的提交，请先 rebase 或 merge 后再发布" >&2
    exit 1
fi

# —— 1. 收集未推送提交 ——
ahead=$(git rev-list --count "$base..HEAD")
if [ "$ahead" -eq 0 ]; then
    echo "没有未推送的提交（$branch 与 $base 一致），无需发布；如仅需补打 tag，请直接 git tag" >&2
    exit 1
fi
commits_log=$(git log --pretty='- %s (%h)' "$base..HEAD")

# —— 2. 确定版本号 ——
if [ -n "$TAG_INPUT" ]; then
    case "$TAG_INPUT" in
        V*) TAG="$TAG_INPUT" ;;
        *)  TAG="V$TAG_INPUT" ;;
    esac
else
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
    if [ -z "$latest_tag" ]; then
        echo "错误：未找到已有 tag，无法自动递增版本号，请显式指定，如 sh release.sh V0.0.1" >&2
        exit 1
    fi
    ver=${latest_tag#V}
    major=$(printf '%s' "$ver" | cut -d. -f1)
    minor=$(printf '%s' "$ver" | cut -d. -f2)
    patch=$(printf '%s' "$ver" | cut -d. -f3)
    patch=$((patch + 1))
    TAG="V$major.$minor.$patch"
fi

# 严格校验 V数字.数字.数字
case "$TAG" in
    V*.*.*)
        rest=${TAG#V}
        case "$rest" in
            *[!0-9.]*) echo "错误：版本号格式应为 Vx.y.z（纯数字），收到 $TAG" >&2; exit 1 ;;
        esac
        n_dots=$(printf '%s' "$rest" | tr -cd '.' | wc -c)
        [ "$n_dots" -eq 2 ] || { echo "错误：版本号格式应为 Vx.y.z，收到 $TAG" >&2; exit 1; } ;;
    *)
        echo "错误：版本号格式应为 Vx.y.z，收到 $TAG" >&2; exit 1 ;;
esac

if git show-ref --tags --quiet -- "refs/tags/$TAG"; then
    echo "错误：tag $TAG 已存在" >&2; exit 1
fi

# —— 3. 准备提交信息 ——
[ -n "$MSG" ] || MSG="release: $TAG"
msg_file=$(mktemp)
trap 'rm -f "$msg_file"' EXIT INT TERM
{
    printf '%s\n' "$MSG"
    if [ "$ahead" -gt 1 ]; then
        printf '\n整合 %s 个提交：\n' "$ahead"
        printf '%s\n' "$commits_log"
    fi
} > "$msg_file"

# —— 4. 展示计划并确认 ——
echo ""
echo "======== 发布计划 ========"
echo "分支      : $branch（基点 $base）"
echo "版本 tag  : $TAG"
if [ "$ahead" -gt 1 ]; then
    echo "压缩提交  : $ahead 个未推送提交 → 1 个"
else
    echo "压缩提交  : 仅 1 个未推送提交，保持原样"
fi
echo "提交信息  : $MSG"
echo "------ 待发布提交 ------"
printf '%s\n' "$commits_log"
echo "=========================="
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry-run：未执行任何改动。"
    exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    printf '确认执行发布？ [y/N] '
    read -r ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "已取消。"; exit 1 ;;
    esac
fi

# —— 5. 压缩提交（ahead=1 时跳过）——
if [ "$ahead" -gt 1 ]; then
    echo ">> 压缩 $ahead 个提交为 1 个（reset --soft $base）"
    git reset --soft "$base"
    git commit -F "$msg_file" --quiet
fi

# —— 6. 打 tag ——
echo ">> 创建 annotated tag $TAG"
git tag -a "$TAG" -m "Tack Harness $TAG"

# —— 7. 推送（fast-forward）——
echo ">> 推送 $branch → $REMOTE"
git push "$REMOTE" "$branch"

echo ">> 推送 tag $TAG → $REMOTE（将触发 Release CI）"
git push "$REMOTE" "$TAG"

echo ""
echo "✅ 发布完成：$TAG"
echo "   Release 将由 CI 自动创建：https://github.com/frcoder-lh/tack-harness/releases/tag/$TAG"
