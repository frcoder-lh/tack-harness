#!/bin/sh
# branch-op.sh — 分支级操作（branch-op 工作流的机械流程脚本）
#
# 场景：把源分支 A merge 到目标分支 B，或把 A rebase onto B。
# A、B 可能正被其他 worktree 检出，故不占用原分支：
#   1. fetch 后按「<原分支名>-<时间戳>」创建两个临时分支，分别指向 origin/A、origin/B
#      （远端不存在该分支时回退引用本地同名分支）
#   2. 只为「工作分支」创建一个 worktree（位于 $work/repo/<repo-name>）：
#        merge  → 检出 B-ts，在其上 merge A-ts，最后普通推送 B-ts → B
#        rebase → 检出 A-ts，在其上 rebase B-ts，最后 --force-with-lease 推送 A-ts → A
#   3. 临时分支与 worktree 保留到 close 时由 cleanup 统一清理
#
# 安全约束：
#   - rebase 推送属于改写远端历史，必须同时满足：
#       ① 命令层已向用户取得当次明确授权；
#       ② 环境变量 BRANCH_OP_FORCE_AUTHORIZED=1。
#     缺一不可，脚本直接拒绝；禁止裸 --force。
#   - 退出码 10 表示出现合并/变基冲突，调用方应据此转 solve（merge-conflict/branch-op 工作流）。
#
# Usage:
#   sh branch-op.sh prepare <root> <workspace> <repo> <op> <source> <target>
#       workspace 为相对 root 的工作区目录（space/<YYYYMMDD>-<branch>）；输出 KEY=VALUE 结果行
#   sh branch-op.sh integrate <root> <workspace> <repo> <op> <source-tmp> <target-tmp>
#   sh branch-op.sh continue <root> <workspace> <repo> <op>
#   sh branch-op.sh abort <root> <workspace> <repo> <op>
#   sh branch-op.sh push <root> <workspace> <repo> <op> <source> <target> <source-tmp> <target-tmp>
#   sh branch-op.sh cleanup <root> <workspace> <repo> <source-tmp> <target-tmp> [force]
#
# Windows 经 run.ps1 调用；参数一律使用正斜杠路径。

set -e

fail() {
    echo "branch-op: $*" >&2
    exit 1
}

# 判定 worktree 内是否处于冲突状态（unmerged paths / MERGE_HEAD / rebase 进行中）
conflict_present() {
    wt="$1"
    [ -n "$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null)" ] && return 0
    mh="$(git -C "$wt" rev-parse --git-path MERGE_HEAD 2>/dev/null)" && { [ -f "$mh" ] && return 0; }
    rm_dir="$(git -C "$wt" rev-parse --git-path rebase-merge 2>/dev/null)" && { [ -d "$rm_dir" ] && return 0; }
    ra_dir="$(git -C "$wt" rev-parse --git-path rebase-apply 2>/dev/null)" && { [ -d "$ra_dir" ] && return 0; }
    return 1
}

paths() {
    ROOT="$1"; WS="$2"; REPO="$3"
    REPO_PATH="$ROOT/repo/$REPO"
    WT_PATH="$ROOT/$WS/repo/$REPO"
    [ -d "$REPO_PATH" ] || fail "仓库不存在: $REPO_PATH（先 init 接入）"
}

run_prepare() {
    ROOT="$1"; WS="$2"; REPO="$3"; OP="$4"; SRC="$5"; TGT="$6"
    [ "$OP" = merge ] || [ "$OP" = rebase ] || fail "op 必须是 merge 或 rebase: $OP"
    [ -n "$SRC" ] && [ -n "$TGT" ] || fail "source/target 分支名不能为空"
    paths "$ROOT" "$WS" "$REPO"
    [ -d "$WT_PATH" ] && fail "worktree 目录已存在: $WT_PATH"

    git -C "$REPO_PATH" fetch origin --prune || fail "fetch origin 失败（远端不可达？）"

    # 基准解析：优先远端最新，远端无此分支则引用本地分支（只读引用，不占用其 worktree）
    resolve_base() {
        b="$1"
        if git -C "$REPO_PATH" rev-parse --verify -q "origin/$b" >/dev/null; then
            echo "origin/$b"
        elif git -C "$REPO_PATH" rev-parse --verify -q "$b" >/dev/null; then
            echo "$b"
        else
            fail "分支在远端与本地均不存在: $b（仓库 $REPO）"
        fi
    }
    SRC_BASE="$(resolve_base "$SRC")"
    TGT_BASE="$(resolve_base "$TGT")"

    TS="$(date +%Y%m%d%H%M%S)"
    SRC_TMP="$SRC-$TS"
    TGT_TMP="$TGT-$TS"
    # branch -f：同一秒重跑时覆盖同名临时分支；不触碰原 A、B 分支
    git -C "$REPO_PATH" branch -f "$SRC_TMP" "$SRC_BASE"
    git -C "$REPO_PATH" branch -f "$TGT_TMP" "$TGT_BASE"

    if [ "$OP" = merge ]; then WORK="$TGT_TMP"; else WORK="$SRC_TMP"; fi
    mkdir -p "$ROOT/$WS/repo"
    git -C "$REPO_PATH" worktree add "$WT_PATH" "$WORK"

    echo "BRANCH_OP_TS=$TS"
    echo "BRANCH_OP_SOURCE_TMP=$SRC_TMP"
    echo "BRANCH_OP_TARGET_TMP=$TGT_TMP"
    echo "BRANCH_OP_WORKING=$WORK"
}

# merge/rebase 执行；rc 非 0 时区分冲突（10）与其他错误（1）
exec_integrate() {
    WT="$1"; OP="$2"; SRC_TMP="$3"; TGT_TMP="$4"
    set +e
    if [ "$OP" = merge ]; then
        git -C "$WT" merge --no-edit "$SRC_TMP"
        rc=$?
    else
        git -C "$WT" rebase "$TGT_TMP"
        rc=$?
    fi
    set -e
    if [ "$rc" -ne 0 ]; then
        if conflict_present "$WT"; then
            echo "branch-op: 出现冲突，转 solve 处理后执行 continue" >&2
            exit 10
        fi
        fail "integrate 失败（退出码 $rc），非冲突类错误，见上方 git 输出"
    fi
}

run_integrate() {
    ROOT="$1"; WS="$2"; REPO="$3"; OP="$4"; SRC_TMP="$5"; TGT_TMP="$6"
    paths "$ROOT" "$WS" "$REPO"
    exec_integrate "$WT_PATH" "$OP" "$SRC_TMP" "$TGT_TMP"
    echo "branch-op: integrate 完成（$OP，仓库 $REPO）"
}

run_continue() {
    ROOT="$1"; WS="$2"; REPO="$3"; OP="$4"
    paths "$ROOT" "$WS" "$REPO"
    set +e
    if [ "$OP" = merge ]; then
        GIT_EDITOR=true git -C "$WT_PATH" merge --continue
        rc=$?
    else
        GIT_EDITOR=true git -C "$WT_PATH" rebase --continue
        rc=$?
    fi
    set -e
    if [ "$rc" -ne 0 ]; then
        if conflict_present "$WT_PATH"; then
            echo "branch-op: 仍有冲突，继续 solve 后再次 continue" >&2
            exit 10
        fi
        fail "continue 失败（退出码 $rc），见上方 git 输出"
    fi
    echo "branch-op: continue 完成（$OP，仓库 $REPO）"
}

run_abort() {
    ROOT="$1"; WS="$2"; REPO="$3"; OP="$4"
    paths "$ROOT" "$WS" "$REPO"
    if [ "$OP" = merge ]; then
        git -C "$WT_PATH" merge --abort
    else
        git -C "$WT_PATH" rebase --abort
    fi
    echo "branch-op: 已中止（$OP，仓库 $REPO）"
}

run_push() {
    ROOT="$1"; WS="$2"; REPO="$3"; OP="$4"
    SRC="$5"; TGT="$6"; SRC_TMP="$7"; TGT_TMP="$8"
    paths "$ROOT" "$WS" "$REPO"
    if [ "$OP" = merge ]; then
        git -C "$WT_PATH" push origin "$TGT_TMP:$TGT"
    else
        [ "${BRANCH_OP_FORCE_AUTHORIZED:-0}" = 1 ] \
            || fail "rebase 推送需用户当次明确授权并设置 BRANCH_OP_FORCE_AUTHORIZED=1"
        # 以 fetch 后记录的 origin/SRC 旧值作为租约，远端被他人更新时推送自动失败
        EXPECT="$(git -C "$REPO_PATH" rev-parse "origin/$SRC")"
        git -C "$WT_PATH" push --force-with-lease="$SRC:$EXPECT" origin "$SRC_TMP:$SRC"
    fi
    echo "branch-op: push 完成（$OP，仓库 $REPO → $([ "$OP" = merge ] && echo "$TGT" || echo "$SRC")）"
}

run_cleanup() {
    ROOT="$1"; WS="$2"; REPO="$3"; SRC_TMP="$4"; TGT_TMP="$5"; FORCE="${6:-}"
    paths "$ROOT" "$WS" "$REPO"
    if [ -d "$WT_PATH" ]; then
        set +e
        if [ "$FORCE" = force ]; then
            git -C "$REPO_PATH" worktree remove --force "$WT_PATH"
        else
            git -C "$REPO_PATH" worktree remove "$WT_PATH"
        fi
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "worktree 移除失败（存在未提交改动？经用户确认后以 force 重试）"
        echo "已移除 worktree: $WT_PATH"
    else
        echo "worktree 不存在，跳过: $WT_PATH"
    fi
    for b in "$SRC_TMP" "$TGT_TMP"; do
        if git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/$b"; then
            git -C "$REPO_PATH" branch -D "$b"
            echo "已删除临时分支: $b"
        fi
    done
}

ACTION="$1"
[ -n "$ACTION" ] || fail "缺少子命令（prepare|integrate|continue|abort|push|cleanup）"
shift

case "$ACTION" in
    prepare)   run_prepare "$@" ;;
    integrate) run_integrate "$@" ;;
    continue)  run_continue "$@" ;;
    abort)     run_abort "$@" ;;
    push)      run_push "$@" ;;
    cleanup)   run_cleanup "$@" ;;
    *) fail "未知子命令: $ACTION（prepare|integrate|continue|abort|push|cleanup）" ;;
esac
