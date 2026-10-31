#!/bin/sh
# git-root.sh — 供 Git helpers source 的仓库根校验，兼容 worktree 与软链。
# 两侧均经 shell pwd -P 归一，兼容 Git for Windows 的盘符路径。
tack_is_repo_root() (
    [ -d "${1:-}" ] || exit 1
    target="$(cd "$1" && pwd -P)" || exit 1
    top="$(git -C "${target}" rev-parse --show-toplevel 2>/dev/null)" || exit 1
    top="$(cd "${top}" && pwd -P)" || exit 1
    [ "${target}" = "${top}" ]
)
