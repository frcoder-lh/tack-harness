#!/bin/sh
# git-worktree-helper.sh — Git worktree 辅助脚本
#
# 多仓库布局：每个仓库的 worktree 位于 space/<workspace>/repo/<repo-name>，
#   <workspace> 为工作区目录名（<YYYYMMDD>-<branch>，由 work.sh 生成）；
#   worktree 实际检出的 git 分支由 <branch> 参数指定（不带日期前缀）。
#
# Usage:
#   sh git-worktree-helper.sh create <root-path> <workspace> <branch> <repo-name>
#   sh git-worktree-helper.sh remove <root-path> <workspace> [repo-name]
#   sh git-worktree-helper.sh list   <root-path>
#   sh git-worktree-helper.sh branch-remove  <root-path> <repo-name> <branch> [force]
#   sh git-worktree-helper.sh branch-merged  <root-path> <repo-name> <branch> <target>
#
# create 输出结果行 BRANCH_CREATED=0|1（0=分支已存在，1=新建分支），供调用方登记到 branches 列表
# branch-remove：force 时 git branch -D，否则 git branch -d（仅删已合并分支，未合并退出码 2）

set -e

ACTION="$1"
ROOT="${2:-.}"

if [ -z "${ACTION}" ]; then
    echo "Usage: $0 <create|remove|list> <root-path> [workspace] [branch] [repo-name]"
    exit 1
fi

cd "${ROOT}"
# 绝对根路径：git -C 会改变相对路径的解析基准，worktree 路径必须用绝对路径
ABS_ROOT="$(pwd)"

case "${ACTION}" in
    create|Create)
        WORKSPACE="$3"
        BRANCH="$4"
        REPO_NAME="$5"

        if [ -z "${WORKSPACE}" ] || [ -z "${BRANCH}" ] || [ -z "${REPO_NAME}" ]; then
            echo "Error: <workspace> <branch> and <repo-name> are required for create"
            echo "Usage: $0 create <root-path> <workspace> <branch> <repo-name>"
            exit 1
        fi

        REPO_PATH="repo/${REPO_NAME}"
        WORKTREE_PATH="${ABS_ROOT}/space/${WORKSPACE}/repo/${REPO_NAME}"

        if [ ! -d "${REPO_PATH}" ]; then
            echo "Error: Repo not found at ${REPO_PATH}"
            echo "Run /tack init first."
            exit 1
        fi

        # 存在性以目录为准（不依赖 worktree list 文本——Git for Windows 输出的是 C:/ 形式，
        # 而 MSYS shell 内是 /tmp 形式，字符串匹配会失效）
        if [ -d "${WORKTREE_PATH}" ]; then
            echo "Worktree already exists: ${WORKTREE_PATH}"
            echo "BRANCH_CREATED=0"
        else
            echo "Creating worktree: ${BRANCH} -> ${WORKTREE_PATH}"
            mkdir -p "${ABS_ROOT}/space/${WORKSPACE}/repo"
            if git -C "${REPO_PATH}" worktree add "${WORKTREE_PATH}" "${BRANCH}" 2>/dev/null; then
                echo "Worktree created successfully."
                echo "BRANCH_CREATED=0"
            else
                echo "Branch doesn't exist yet, creating new branch..."
                git -C "${REPO_PATH}" worktree add -b "${BRANCH}" "${WORKTREE_PATH}"
                echo "BRANCH_CREATED=1"
            fi
        fi
        ;;

    remove|Remove)
        WORKSPACE="$3"
        REPO_NAME="$4"

        if [ -z "${WORKSPACE}" ]; then
            echo "Error: <workspace> is required for remove"
            echo "Usage: $0 remove <root-path> <workspace> [repo-name]"
            exit 1
        fi

        # 指定仓库只处理该仓库；否则遍历 root/repo 下全部仓库
        if [ -n "${REPO_NAME}" ]; then
            set -- "${REPO_NAME}"
        else
            set -- $(ls -1 repo 2>/dev/null)
        fi

        FOUND=0
        for name in "$@"; do
            repo_dir="repo/${name}"
            [ -d "${repo_dir}" ] || continue
            WT="${ABS_ROOT}/space/${WORKSPACE}/repo/${name}"
            # 同样以目录存在为准；直接让 git 执行 remove，失败则 prune 登记信息
            if [ -d "${WT}" ]; then
                echo "Removing worktree from ${name}..."
                if git -C "${repo_dir}" worktree remove --force "${WT}" 2>/dev/null; then
                    echo "  removed: ${WT}"
                    FOUND=1
                else
                    echo "  git remove 失败，尝试 prune 登记信息"
                    git -C "${repo_dir}" worktree prune 2>/dev/null
                fi
            fi
        done

        [ "${FOUND}" -eq 1 ] || echo "No worktree found for workspace: ${WORKSPACE}"
        ;;

    list|List)
        if [ ! -d "repo" ] || [ -z "$(ls -A repo 2>/dev/null)" ]; then
            echo "No repos found in repo/ directory."
            exit 0
        fi

        echo ""
        echo "Git Worktrees:"
        echo "=============="

        for repo_dir in repo/*/; do
            [ -d "${repo_dir}" ] || continue
            echo ""
            echo "[$(basename "${repo_dir}")]"
            git -C "${repo_dir}" worktree list 2>/dev/null || echo "  (no worktrees)"
        done
        ;;

    branch-remove|BranchRemove)
        REPO_NAME="$3"
        BRANCH="$4"
        FORCE="${5:-}"
        if [ -z "${REPO_NAME}" ] || [ -z "${BRANCH}" ]; then
            echo "Error: <repo-name> and <branch> are required for branch-remove"
            echo "Usage: $0 branch-remove <root-path> <repo-name> <branch> [force]"
            exit 1
        fi
        REPO_PATH="repo/${REPO_NAME}"
        if [ ! -d "${REPO_PATH}" ]; then
            echo "Error: Repo not found at ${REPO_PATH}"
            exit 1
        fi
        # 分支不存在则跳过（close 幂等清理，多次调用安全）
        if ! git -C "${REPO_PATH}" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
            echo "Branch not found, skip: ${BRANCH}"
            exit 0
        fi
        if [ "${FORCE}" = force ]; then
            git -C "${REPO_PATH}" branch -D "${BRANCH}"
            echo "Force removed branch: ${BRANCH}"
        else
            # -d 仅删已合并分支，未合并时 git 返回非 0；set -e 下 if 内命令失败不退出
            if git -C "${REPO_PATH}" branch -d "${BRANCH}" 2>/dev/null; then
                echo "Removed merged branch: ${BRANCH}"
            else
                echo "Branch not merged, keep: ${BRANCH}"
                exit 2
            fi
        fi
        ;;

    branch-merged|BranchMerged)
        REPO_NAME="$3"
        BRANCH="$4"
        TARGET="$5"
        if [ -z "${REPO_NAME}" ] || [ -z "${BRANCH}" ] || [ -z "${TARGET}" ]; then
            echo "Error: <repo-name> <branch> <target> are required for branch-merged"
            echo "Usage: $0 branch-merged <root-path> <repo-name> <branch> <target>"
            exit 1
        fi
        REPO_PATH="repo/${REPO_NAME}"
        if [ ! -d "${REPO_PATH}" ]; then
            echo "Error: Repo not found at ${REPO_PATH}"
            exit 1
        fi
        # 分支已不存在视为可清理（输出 1）
        if ! git -C "${REPO_PATH}" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
            echo "1"
            exit 0
        fi
        # TARGET 不存在则保守视为未合并（输出 0）
        if ! git -C "${REPO_PATH}" rev-parse --verify -q "${TARGET}" >/dev/null 2>&1; then
            echo "0"
            exit 0
        fi
        # BRANCH 相对 TARGET 的独有提交数；0 表示 BRANCH 的提交都在 TARGET 中（已合并）
        ahead=$(git -C "${REPO_PATH}" rev-list --count "${TARGET}..${BRANCH}" 2>/dev/null || echo "?")
        if [ "${ahead}" = "0" ]; then
            echo "1"
        else
            echo "0"
        fi
        ;;

    *)
        echo "Error: Unknown action '${ACTION}'"
        echo "Valid actions: create, remove, list, branch-remove, branch-merged"
        exit 1
        ;;
esac
