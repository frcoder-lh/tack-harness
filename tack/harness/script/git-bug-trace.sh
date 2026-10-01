#!/bin/sh
# git-bug-trace.sh — 缺陷溯源：定位引入缺陷的 commit、对应需求与合并到主干的 MR
#
# 给定代码仓库内的文件与行号，追溯：
#   1. 最后修改该行为「缺陷代码」的 commit（git blame）
#   2. 该 commit 的作者、时间、完整 message
#   3. 从 message 中提取需求/工单 ID（如 #123 / MEEGO-456 / JIRA-789）
#   4. 把该 commit 带入主干（默认 master/main）的合并提交（merge commit）
#   5. 由 remote URL 推导出的 commit 链接与 MR 链接
#
# 用法:
#   sh git-bug-trace.sh <repo-path> <file> <line> [end-line] [target-branch]
#   - repo-path:    代码仓库路径（$work/repo/<repo-name>）
#   - file:         缺陷所在文件（相对 repo-path 或绝对路径）
#   - line:         缺陷起始行号
#   - end-line:     缺陷结束行号（可选，默认等于 line）
#   - target-branch: 目标主干分支（可选，默认自动探测 master/main）
#
# 输出（label: value 格式，便于 AI 解析）：
#   commit:        引入缺陷的 commit hash（完整）
#   author:        作者
#   date:          提交时间（ISO 8601）
#   subject:       提交标题
#   body:          提交正文（多行，每行前缀 BODY|）
#   requirement:   提取到的需求/工单 ID（空格分隔，无则空）
#   commit_url:    commit 链接（由 remote 推导）
#   target_branch: 实际使用的目标主干分支
#   merge_commit:  把该 commit 带入主干的最近合并提交 hash（无则空）
#   merge_subject: 合并提交标题（通常含 MR/PR 编号）
#   merge_url:     合并提交对应的 MR/PR 链接（能推导时给出）
#   note:          附加说明（如未找到合并提交的原因）
#
# 退出码: 0 成功；1 仓库/文件不存在或 git 操作失败；2 用法错误

set -eu

if [ $# -lt 3 ]; then
    echo "Usage: $0 <repo-path> <file> <line> [end-line] [target-branch]" >&2
    exit 2
fi

REPO="$1"
FILE="$2"
LINE="$3"
END="${4:-$3}"
TARGET_BRANCH="${5:-}"

if [ ! -d "$REPO" ]; then
    echo "Error: repo not found: $REPO" >&2
    exit 1
fi

# 归一化文件路径：如果是绝对路径且以 REPO 开头，转相对；否则直接用
case "$FILE" in
    /*)
        # 绝对路径：尝试去掉 REPO 前缀
        REPO_ABS="$(cd "$REPO" && pwd)"
        case "$FILE" in
            "$REPO_ABS"/*) FILE="${FILE#"$REPO_ABS"/}" ;;
        esac
        ;;
esac

cd "$REPO"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: not a git repo: $REPO" >&2
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "Error: file not found in repo: $FILE" >&2
    exit 1
fi

# ---- 1. git blame 定位引入 commit ----
# 取该范围内出现次数最多的 commit（通常就是引入缺陷的那个）
BLAME_OUT="$(git blame -L "${LINE},${END}" --porcelain "$FILE" 2>/dev/null)" || {
    echo "Error: git blame failed for $FILE:$LINE-$END" >&2
    exit 1
}

# porcelain 格式每个块第一行是 commit hash，统计出现频次取最高
INTRO_COMMIT="$(printf '%s\n' "$BLAME_OUT" | awk '
/^[0-9a-f]{40} / {
    hash = $1
    cnt[hash]++
    if (cnt[hash] > max) { max = cnt[hash]; top = hash }
}
END { print top }
')"

if [ -z "$INTRO_COMMIT" ]; then
    echo "Error: cannot determine introducing commit" >&2
    exit 1
fi

# ---- 2. 取 commit 详情 ----
COMMIT_INFO="$(git show -s --format='%H%n%an%n%ad%n%s%n%b' --date=iso-strict "$INTRO_COMMIT" 2>/dev/null)" || {
    echo "Error: git show failed for $INTRO_COMMIT" >&2
    exit 1
}

FULL_HASH="$(printf '%s\n' "$COMMIT_INFO" | sed -n '1p')"
AUTHOR="$(printf '%s\n' "$COMMIT_INFO" | sed -n '2p')"
DATE="$(printf '%s\n' "$COMMIT_INFO" | sed -n '3p')"
SUBJECT="$(printf '%s\n' "$COMMIT_INFO" | sed -n '4p')"
BODY="$(printf '%s\n' "$COMMIT_INFO" | sed -n '5,$p')"

# ---- 3. 提取需求/工单 ID ----
# 匹配常见模式：#123（issue 号）、MEEGO-456 / JIRA-789 / ABC-123（工单号）
REQUIREMENT="$(printf '%s\n%s\n' "$SUBJECT" "$BODY" | awk '
{
    n = split($0, a, /[^A-Za-z0-9_#-]/)
    for (i = 1; i <= n; i++) {
        tok = a[i]
        if (tok ~ /^#[0-9]+$/) print tok
        else if (tok ~ /^[A-Z][A-Z0-9]+-[0-9]+$/) print tok
    }
}' | sort -u | tr '\n' ' ' | sed 's/ $//')"

# ---- 4. 推导目标主干分支 ----
if [ -z "$TARGET_BRANCH" ]; then
    if git show-ref --verify --quiet refs/heads/master; then
        TARGET_BRANCH="master"
    elif git show-ref --verify --quiet refs/heads/main; then
        TARGET_BRANCH="main"
    else
        # 回退：取 origin 的默认分支
        TARGET_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/origin/||' || true)"
        [ -z "$TARGET_BRANCH" ] && TARGET_BRANCH="master"
    fi
fi

# ---- 5. 查找把该 commit 带入主干的合并提交 ----
# --ancestry-path 限定在 commit..target 的路径上；--merges 只看合并提交
# 取最近的一个（离 target 最近的 merge 最先被 log 输出）
MERGE_INFO="$(git log --merges --ancestry-path --format='%H%n%s' "$INTRO_COMMIT..$TARGET_BRANCH" 2>/dev/null | head -2 || true)"
MERGE_COMMIT=""
MERGE_SUBJECT=""
NOTE=""
if [ -n "$MERGE_INFO" ]; then
    MERGE_COMMIT="$(printf '%s\n' "$MERGE_INFO" | sed -n '1p')"
    MERGE_SUBJECT="$(printf '%s\n' "$MERGE_INFO" | sed -n '2p')"
fi

if [ -z "$MERGE_COMMIT" ]; then
    NOTE="未在 $INTRO_COMMIT..$TARGET_BRANCH 路径上找到合并提交（可能该 commit 仍在特性分支、或被 rebase/cherry-pick 改写）"
fi

# ---- 6. 由 remote URL 推导 commit / MR 链接 ----
REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
COMMIT_URL=""
MERGE_URL=""

if [ -n "$REMOTE_URL" ]; then
    # 归一化 remote URL → host + path（去掉 .git 后缀、协议、git@ 前缀）
    NORMALIZED="$(printf '%s' "$REMOTE_URL" | sed -e 's|^https\?://||' -e 's|^git@||' -e 's|^ssh://git@||' -e 's|:|/|' -e 's|\.git$||')"
    HOST="$(printf '%s' "$NORMALIZED" | cut -d'/' -f1)"
    REPO_PATH="$(printf '%s' "$NORMALIZED" | cut -d'/' -f2-)"

    if [ -n "$HOST" ] && [ -n "$REPO_PATH" ]; then
        # commit URL：GitLab 用 /-/commit/，其余用 /commit/
        case "$HOST" in
            *gitlab*|*jihulab*|*gitlab.*)
                COMMIT_URL="https://$HOST/$REPO_PATH/-/commit/$FULL_HASH"
                ;;
            *bitbucket*)
                COMMIT_URL="https://$HOST/$REPO_PATH/commits/$FULL_HASH"
                ;;
            *)
                COMMIT_URL="https://$HOST/$REPO_PATH/commit/$FULL_HASH"
                ;;
        esac

        # MR/PR 链接：从 merge_subject 提取编号（如 !123 / #123 / PR #123）
        MR_NUM="$(printf '%s' "$MERGE_SUBJECT" | grep -oE '(!|#)[0-9]+' | head -1 | sed 's/^[!#]//' || true)"
        if [ -n "$MR_NUM" ] && [ -n "$MERGE_COMMIT" ]; then
            case "$HOST" in
                *gitlab*|*jihulab*|*gitlab.*)
                    MERGE_URL="https://$HOST/$REPO_PATH/-/merge_requests/$MR_NUM"
                    ;;
                *bitbucket*)
                    MERGE_URL="https://$HOST/$REPO_PATH/pull-requests/$MR_NUM"
                    ;;
                *)
                    MERGE_URL="https://$HOST/$REPO_PATH/pull/$MR_NUM"
                    ;;
            esac
        fi
    fi
fi

# ---- 7. 输出 ----
echo "commit: $FULL_HASH"
echo "author: $AUTHOR"
echo "date: $DATE"
echo "subject: $SUBJECT"
if [ -n "$BODY" ]; then
    printf '%s\n' "$BODY" | while IFS= read -r bline; do
        echo "BODY| $bline"
    done
fi
echo "requirement: $REQUIREMENT"
echo "commit_url: $COMMIT_URL"
echo "target_branch: $TARGET_BRANCH"
echo "merge_commit: $MERGE_COMMIT"
echo "merge_subject: $MERGE_SUBJECT"
echo "merge_url: $MERGE_URL"
echo "note: $NOTE"

exit 0
