#!/bin/sh
# work.sh — 新建工作区（space/<YYYYMMDD>-<branch>/）
#
# Usage:
#   sh work.sh [--no-worktree] <root> <project> <branch> [repo-name ...]
#     project 必须已在 AGENTS.md projects 数组中登记（work 条目与项目 wiki 的归属依据）
#     repo-name 可传多个；不传则默认为 root/repo 下的全部仓库创建 worktree
#     --no-worktree：只建目录骨架与模板文件，不创建任何 worktree
#       （branch-op 工作流使用，临时分支 worktree 由 branch-op.sh prepare 另行创建）
#
#   sh work.sh purge <root> <workspace>
#     删除已关闭工作区目录 space/<workspace>（close 收尾用）。
#     安全门禁：workspace 必须是单层目录名；目标物理路径必须位于 <root>/space/ 内；
#     目录内 repo/ 下不得残留有效 git worktree（须先经 close 第 6 步 / branch-op cleanup 移除）。
#     本动作只删目录，AGENTS.md 工作条目的移除由 project.sh work-remove 负责；不自动提交
#     （由 close 收尾的 space.sh commit 统一记录删除）。
#
# 目录命名：工作区目录名 = 创建日期(YYYYMMDD) + '-' + 安全化分支名，如 20261001-user-login。
#   日期前缀使 space/ 下「按目录名排序」即「按创建时间排序」；git 分支名本身不带日期，
#   目录（空间管理概念）与分支名由此解耦。
#
# 结果行（stdout 末尾输出 KEY=VALUE，供调用方解析实际工作区路径）：
#   WORKSPACE=<工作区目录名>   BRANCH=<安全化分支名>
#
# 工作区结构（扁平，工作区级文档放 wiki/）：
#   space/<YYYYMMDD>-<branch>/
#   ├── status.yaml        # 工作区状态（属性 + 当前任务/进度/下一步），由模板复制 + sed 替换
#   ├── input.md           # 原始需求输入
#   ├── wiki/              # 工作区级代码理解产物（ask 命令产出，如 <repo>-analysis.md、问答文档）
#   └── repo/<repo-name>/  # 各仓库的 git worktree（无仓库时为占位目录）
#
# 注意：本脚本只负责目录、模板文件与 worktree；
#       在 AGENTS.md 项目信息区块登记工作条目由 project.sh work-add 完成（见 work 命令）。

set -e

# ---------- purge：删除已关闭工作区目录（close 收尾） ----------
if [ "${1:-}" = "purge" ]; then
    ROOT="$2"
    WORKSPACE="$3"
    if [ -z "${ROOT}" ] || [ -z "${WORKSPACE}" ]; then
        echo "Usage: sh work.sh purge <root> <workspace>" >&2
        exit 1
    fi
    # 门禁 1：workspace 必须是单层目录名，拒绝分隔符、空白与父目录跳转
    case "${WORKSPACE}" in
        */*|*'\'*|*" "*|.|..)
            echo "Error: 非法 workspace 名称: ${WORKSPACE}" >&2
            exit 1
            ;;
    esac
    if [ ! -d "${ROOT}" ]; then
        echo "Error: tack 空间根不存在: ${ROOT}" >&2
        exit 1
    fi
    if [ ! -d "${ROOT}/space" ]; then
        echo "Error: ${ROOT}/space 不存在，不是有效的 tack 空间" >&2
        exit 1
    fi
    TARGET="${ROOT}/space/${WORKSPACE}"
    if [ ! -d "${TARGET}" ]; then
        echo "Error: 工作区目录不存在: ${TARGET}" >&2
        exit 1
    fi
    # 门禁 2：目标物理父目录必须等于 space/ 的物理路径（防 symlink 逃逸）
    SPACE_REAL=$(cd "${ROOT}/space" && pwd -P)
    PARENT_REAL=$(cd "${TARGET}/.." && pwd -P)
    if [ "${PARENT_REAL}" != "${SPACE_REAL}" ]; then
        echo "Error: 目标物理路径不在 space/ 内，拒绝删除: ${TARGET}" >&2
        exit 1
    fi
    # 门禁 3：repo/ 下不得残留有效 git worktree（须先经 close 第 6 步移除）
    if [ -d "${TARGET}/repo" ]; then
        for wt in "${TARGET}/repo"/*; do
            [ -d "${wt}" ] || continue
            if git -C "${wt}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                echo "Error: 检测到残留 worktree，拒绝删除: ${wt}" >&2
                echo "请先移除 worktree（git-worktree-helper.sh remove / branch-op.sh cleanup）" >&2
                exit 1
            fi
        done
    fi

    # 离开目标目录后删除（Windows 上 cwd 在目标内会导致删除失败；脚本此前未 cd，此处置保险）
    cd "${ROOT}"
    rm -rf "${TARGET}"
    echo "已删除工作区目录: space/${WORKSPACE}"
    echo "PURGED=${WORKSPACE}"
    exit 0
fi

NO_WORKTREE=0
case "${1:-}" in
  --no-worktree) NO_WORKTREE=1; shift ;;
esac

ROOT="${1:-.}"
PROJECT="$2"
BRANCH="$3"

if [ -z "${PROJECT}" ] || [ -z "${BRANCH}" ]; then
    echo "Usage: sh work.sh <root> <project> <branch> [repo-name ...]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 工作区模板位于 harness/template/（文件复制 + sed 占位替换，不做字符串拼接）
TEMPLATE_DIR="${SCRIPT_DIR}/../template"

# 项目必须已在 AGENTS.md projects 数组中登记（workspace 的 project 字段与项目 wiki 依据）
PROJECTS_LIST="$(sh "${SCRIPT_DIR}/project.sh" project-list "${ROOT}")" || exit 1
if ! printf '%s\n' "${PROJECTS_LIST}" \
    | awk -F"$(printf '\t')" -v want="${PROJECT}" '$1 == want { found=1 } END { exit(found ? 0 : 1) }'; then
    echo "Error: 项目 '${PROJECT}' 未在 AGENTS.md projects 中登记，请先执行 project.sh project-add" >&2
    exit 1
fi

cd "${ROOT}"

# 分支名安全化（只保留字母数字 _ - /；- 置于字符类末尾按字面量处理，/ 不需转义）
SAFE_BRANCH=$(printf '%s' "${BRANCH}" | sed 's/[^a-zA-Z0-9/_-]/_/g')
# 工作区目录名 = 创建日期 + 安全化分支名（目录名带日期前缀便于排序，git 分支名保持纯净）
WORK_BASENAME="$(date +%Y%m%d)-${SAFE_BRANCH}"
BRANCH_DIR="space/${WORK_BASENAME}"

if [ -d "${BRANCH_DIR}" ]; then
    echo "工作区已存在: ${BRANCH_DIR}"
    echo "WORKSPACE=${WORK_BASENAME}"
    echo "BRANCH=${SAFE_BRANCH}"
    exit 0
fi

# 1. 目录骨架（工作区级文档放 wiki/；仅预建 repo 占位）
mkdir -p "${BRANCH_DIR}/repo" "${BRANCH_DIR}/wiki"
echo "已创建: ${BRANCH_DIR}/"

# 2. 确定要建 worktree 的仓库列表
shift 3
REPO_NAMES="$*"
if [ "${NO_WORKTREE}" = 1 ]; then
    REPO_NAMES=""
elif [ -z "${REPO_NAMES}" ] && [ -d "repo" ]; then
    REPO_NAMES=$(ls -1 "repo" 2>/dev/null)
fi

# 3. 逐仓库创建 worktree
WORKTREE_CREATED=0
NEW_BRANCHES=""
if [ -n "${REPO_NAMES}" ]; then
    for name in $REPO_NAMES; do
        if [ -d "repo/${name}" ] && git -C "repo/${name}" rev-parse --git-dir >/dev/null 2>&1; then
            echo "为仓库 '${name}' 创建 worktree（分支 ${SAFE_BRANCH}）..."
            helper_rc=0
            helper_out="$(sh "${SCRIPT_DIR}/git-worktree-helper.sh" create "${ROOT}" "${WORK_BASENAME}" "${SAFE_BRANCH}" "${name}")" || helper_rc=$?
            echo "${helper_out}"
            if [ "${helper_rc}" -eq 0 ]; then
                WORKTREE_CREATED=1
                # 提取 BRANCH_CREATED=1（新建分支的仓库，供调用方登记到 branches）
                if echo "${helper_out}" | grep -q "^BRANCH_CREATED=1$"; then
                    if [ -n "${NEW_BRANCHES}" ]; then NEW_BRANCHES="${NEW_BRANCHES},${name}"; else NEW_BRANCHES="${name}"; fi
                fi
            fi
        else
            echo "跳过（不是有效 git 仓库）: repo/${name}"
        fi
    done
fi

# 4. 无可用仓库时保留空 repo/ 占位目录
if [ "${WORKTREE_CREATED}" -eq 0 ]; then
    if [ "${NO_WORKTREE}" = 1 ]; then
        echo "骨架模式: 未创建 worktree，由调用方（branch-op.sh prepare）接手"
    else
        echo "提示: ${BRANCH_DIR}/repo/ 为占位目录（当前无可用 git 仓库，稍后可用 worktree 命令补建）"
    fi
fi

# 5. status.yaml + input.md（模板复制 + sed 占位替换）
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
if [ -f "${TEMPLATE_DIR}/work-status.yaml" ]; then
    cp "${TEMPLATE_DIR}/work-status.yaml" "${BRANCH_DIR}/status.yaml"
    # sed 分隔符用 | ：目录名/分支名允许含 /（如 feature/x），用 / 作分隔符会误伤替换值；
    # 就地改写走临时文件 + mv（兼容 GNU/BSD，不依赖 sed -i）
    sed "s|{{WORK_DIR}}|${WORK_BASENAME}|g; s|{{PROJECT}}|${PROJECT}|g; s|{{BRANCH}}|${SAFE_BRANCH}|g; s|{{CREATED_AT}}|${CREATED_AT}|g" \
        "${BRANCH_DIR}/status.yaml" > "${BRANCH_DIR}/status.yaml.tmp" \
        && mv "${BRANCH_DIR}/status.yaml.tmp" "${BRANCH_DIR}/status.yaml"
    echo "已创建: status.yaml"
else
    echo "Warn: 未找到 work-status.yaml，status.yaml 未生成" >&2
fi
if [ -f "${TEMPLATE_DIR}/work-input.md" ]; then
    cp "${TEMPLATE_DIR}/work-input.md" "${BRANCH_DIR}/input.md"
    echo "已创建: input.md"
else
    echo "Warn: 未找到 work-input.md，input.md 未生成" >&2
fi

echo ""
echo "工作区已就绪: ${BRANCH_DIR}"
echo "WORKSPACE=${WORK_BASENAME}"
echo "BRANCH=${SAFE_BRANCH}"
echo "NEW_BRANCHES=${NEW_BRANCHES}"

# 框架自动提交空间仓库（space/*/repo/ 已被 .gitignore 排除，只提交工作区文档）
sh "${SCRIPT_DIR}/space.sh" commit "${ROOT}" "chore(tack): create workspace ${WORK_BASENAME}"

echo "下一步: 1) 执行 project.sh work-add 登记工作  2) 向 input.md 录入原始需求  3) 执行 spec"
