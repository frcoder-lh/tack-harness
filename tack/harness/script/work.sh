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
#   sh work.sh rename <root> <old-work-id> <new-work-id> [new-branch] --dry-run|--apply
#     工作区重命名事务：目录（保留日期前缀）、各仓库分支、status.yaml（work_id/work_dir/branch）、
#     AGENTS.md 工作条目、branches[] 一并更新；中途失败自动回滚并输出 ROLLBACK=complete|incomplete。
#     dry-run 只输出变更计划；apply 成功后输出 RENAME_RESULT=applied 与 RECONCILE=ok。
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
#   ├── status.yaml        # 工作区状态（属性 + 当前任务/进度/下一步），由模板复制 + 占位替换
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

# ---------- rename：工作区重命名事务（目录 + 分支 + status.yaml + AGENTS.md + branches） ----------
if [ "${1:-}" = "rename" ]; then
    shift
    ROOT="$1"
    OLD_ID="$2"
    NEW_ID="$3"
    if [ -z "${ROOT}" ] || [ -z "${OLD_ID}" ] || [ -z "${NEW_ID}" ]; then
        echo "Usage: sh work.sh rename <root> <old-work-id> <new-work-id> [new-branch] --dry-run|--apply" >&2
        exit 2
    fi
    shift 3
    MODE=""
    NEW_BRANCH=""
    for a in "$@"; do
        case "${a}" in
            --dry-run|--apply)
                [ -z "${MODE}" ] || { echo "Error: 只能指定一次 --dry-run 或 --apply" >&2; exit 2; }
                MODE="${a}"
                ;;
            --*)
                echo "Error: 未知参数: ${a}" >&2
                exit 2
                ;;
            *)
                [ -z "${NEW_BRANCH}" ] || { echo "Error: 多余的参数: ${a}" >&2; exit 2; }
                NEW_BRANCH="${a}"
                ;;
        esac
    done
    [ -n "${MODE}" ] || { echo "Usage: sh work.sh rename <root> <old-work-id> <new-work-id> [new-branch] --dry-run|--apply" >&2; exit 2; }
    [ -n "${NEW_BRANCH}" ] || NEW_BRANCH="${NEW_ID}"
    case "${NEW_ID}${NEW_BRANCH}" in
        *" "*|*'\'*)
            echo "Error: new-work-id / new-branch 不能包含空白或反斜杠" >&2
            exit 2
            ;;
    esac
    case "${NEW_BRANCH}" in
        *[!A-Za-z0-9._/-]*)
            echo "Error: 非法分支名: ${NEW_BRANCH}" >&2
            exit 2
            ;;
    esac
    if [ ! -d "${ROOT}" ] || [ ! -d "${ROOT}/space" ]; then
        echo "Error: tack 空间根无效: ${ROOT}" >&2
        exit 1
    fi

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    OLD_DIR=""
    OLD_BRANCH=""
    for sf in "${ROOT}/space"/*/status.yaml; do
        [ -f "${sf}" ] || continue
        id="$(awk '
            function v(line,   x) { x=line; sub(/^[^:]*:/,"",x); gsub(/^[[:space:]]+|[[:space:]]+$/,"",x); sub(/[[:space:]]*#.*$/,"",x); gsub(/^"|"$/,"",x); return x }
            /^work_id[[:space:]]*:/ { print v($0); exit }
        ' "${sf}")"
        if [ "${id}" = "${OLD_ID}" ]; then
            d="$(basename "$(dirname "${sf}")")"
            if [ -n "${OLD_DIR}" ] && [ "${OLD_DIR}" != "${d}" ]; then
                echo "Error: 多个工作区使用 work_id '${OLD_ID}': ${OLD_DIR} / ${d}" >&2
                exit 4
            fi
            OLD_DIR="${d}"
        fi
    done
    if [ -z "${OLD_DIR}" ]; then
        echo "Error: 工作区不存在（未找到 work_id '${OLD_ID}'）" >&2
        exit 3
    fi

    OLD_PATH="${ROOT}/space/${OLD_DIR}"
    STATUS="${OLD_PATH}/status.yaml"
    OLD_BRANCH="$(awk '
        function v(line,   x) { x=line; sub(/^[^:]*:/,"",x); gsub(/^[[:space:]]+|[[:space:]]+$/,"",x); sub(/[[:space:]]*#.*$/,"",x); gsub(/^"|"$/,"",x); return x }
        /^branch[[:space:]]*:/ { print v($0); exit }
    ' "${STATUS}")"
    [ -n "${OLD_BRANCH}" ] || OLD_BRANCH="${OLD_ID}"

    DATE_PREFIX="$(printf '%s' "${OLD_DIR}" | cut -c1-8)"
    case "${DATE_PREFIX}" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
        *) DATE_PREFIX="$(date +%Y%m%d)" ;;
    esac
    SAFE_NEW_BRANCH="$(printf '%s' "${NEW_BRANCH}" | sed 's/[^a-zA-Z0-9/_-]/_/g')"
    NEW_DIR="${DATE_PREFIX}-${SAFE_NEW_BRANCH}"
    NEW_PATH="${ROOT}/space/${NEW_DIR}"

    # 冲突检查：新 ID、新目录、新分支
    if [ "${NEW_ID}" != "${OLD_ID}" ] \
        && grep -q "work_id: \"${NEW_ID}\"" "${ROOT}/AGENTS.md" 2>/dev/null; then
        echo "Error: 新 work_id 已被登记: ${NEW_ID}" >&2
        exit 4
    fi
    if [ "${NEW_DIR}" != "${OLD_DIR}" ] && [ -e "${NEW_PATH}" ]; then
        echo "Error: 目标工作区目录已存在: space/${NEW_DIR}" >&2
        exit 4
    fi
    REPOS=""
    for d in "${OLD_PATH}/repo"/*/; do
        [ -d "${d}" ] || continue
        [ -e "${d}/.git" ] || continue
        if git -C "${d}" rev-parse --git-dir >/dev/null 2>&1; then
            REPOS="${REPOS} $(basename "${d%/}")"
        fi
    done
    if [ "${SAFE_NEW_BRANCH}" != "${OLD_BRANCH}" ]; then
        for r in ${REPOS}; do
            if git -C "${OLD_PATH}/repo/${r}" rev-parse --verify --quiet "refs/heads/${SAFE_NEW_BRANCH}" >/dev/null 2>&1; then
                echo "Error: 仓库 ${r} 已存在分支 ${SAFE_NEW_BRANCH}" >&2
                exit 4
            fi
        done
    fi

    echo "RENAME PLAN"
    if [ "${NEW_DIR}" = "${OLD_DIR}" ]; then
        echo "  dir:     space/${OLD_DIR} (unchanged)"
    else
        echo "  dir:     space/${OLD_DIR} -> space/${NEW_DIR}"
    fi
    echo "  work_id: ${OLD_ID} -> ${NEW_ID}"
    echo "  branch:  ${OLD_BRANCH} -> ${SAFE_NEW_BRANCH}"
    for r in ${REPOS}; do
        echo "  repo/${r}: branch ${OLD_BRANCH} -> ${SAFE_NEW_BRANCH}"
    done
    echo "  status.yaml: work_id / branch / work_dir"
    echo "  AGENTS.md:   work entry work_id / branch / work_path"
    echo "  branches[]:  ${OLD_BRANCH} -> ${SAFE_NEW_BRANCH}"

    if [ "${MODE}" = "--dry-run" ]; then
        echo "RENAME_RESULT=dry-run"
        exit 0
    fi

    # ---------- apply：逐步执行，失败即回滚 ----------
    TXN="${ROOT}/.tack/tmp/rename.$$"
    mkdir -p "${TXN}" || { echo "Error: 无法创建事务目录: ${TXN}" >&2; exit 1; }
    cp "${STATUS}" "${TXN}/status.yaml" || exit 1
    cp "${ROOT}/AGENTS.md" "${TXN}/AGENTS.md" || exit 1
    : > "${TXN}/br.log"
    : > "${TXN}/wt.log"
    ROLLBACK_OK=1

    rollback() {
        reason="$1"
        echo "Error: ${reason}" >&2
        cp "${TXN}/status.yaml" "${STATUS}" 2>/dev/null || ROLLBACK_OK=0
        cp "${TXN}/AGENTS.md" "${ROOT}/AGENTS.md" 2>/dev/null || ROLLBACK_OK=0
        if [ "${NEW_DIR}" != "${OLD_DIR}" ] && [ -d "${NEW_PATH}" ] && [ -d "${OLD_PATH}" ]; then
            for entry in "${NEW_PATH}"/*; do
                [ -e "${entry}" ] || continue
                b="$(basename "${entry}")"
                [ "${b}" = "repo" ] && continue
                mv "${entry}" "${OLD_PATH}/" 2>/dev/null || ROLLBACK_OK=0
            done
        fi
        for r in $(cat "${TXN}/wt.log" 2>/dev/null); do
            if [ -d "${NEW_PATH}/repo/${r}" ] && [ ! -d "${OLD_PATH}/repo/${r}" ]; then
                git -C "${ROOT}/repo/${r}" worktree move "${NEW_PATH}/repo/${r}" "${OLD_PATH}/repo/${r}" 2>/dev/null || ROLLBACK_OK=0
            fi
        done
        for r in $(cat "${TXN}/br.log" 2>/dev/null); do
            wt="${OLD_PATH}/repo/${r}"
            if [ -d "${wt}" ]; then
                cur="$(git -C "${wt}" symbolic-ref --short HEAD 2>/dev/null || true)"
                if [ "${cur}" = "${SAFE_NEW_BRANCH}" ]; then
                    git -C "${wt}" branch -m "${OLD_BRANCH}" 2>/dev/null || ROLLBACK_OK=0
                elif git -C "${wt}" rev-parse --verify --quiet "refs/heads/${SAFE_NEW_BRANCH}" >/dev/null 2>&1; then
                    git -C "${wt}" branch -m "${SAFE_NEW_BRANCH}" "${OLD_BRANCH}" 2>/dev/null || ROLLBACK_OK=0
                fi
            fi
        done
        if [ "${NEW_DIR}" != "${OLD_DIR}" ]; then
            rmdir "${NEW_PATH}/repo" 2>/dev/null || true
            rmdir "${NEW_PATH}" 2>/dev/null || true
        fi
        if [ "${ROLLBACK_OK}" -eq 1 ]; then
            echo "ROLLBACK=complete"
        else
            echo "ROLLBACK=incomplete"
        fi
        rm -rf "${TXN}"
        exit 1
    }

    if [ "${SAFE_NEW_BRANCH}" != "${OLD_BRANCH}" ]; then
        for r in ${REPOS}; do
            wt="${OLD_PATH}/repo/${r}"
            cur="$(git -C "${wt}" symbolic-ref --short HEAD 2>/dev/null || true)"
            if [ "${cur}" = "${OLD_BRANCH}" ]; then
                git -C "${wt}" branch -m "${SAFE_NEW_BRANCH}" || rollback "重命名仓库 ${r} 的当前分支失败"
                echo "${r}" >> "${TXN}/br.log"
            elif git -C "${wt}" rev-parse --verify --quiet "refs/heads/${OLD_BRANCH}" >/dev/null 2>&1; then
                git -C "${wt}" branch -m "${OLD_BRANCH}" "${SAFE_NEW_BRANCH}" || rollback "重命名仓库 ${r} 的分支失败"
                echo "${r}" >> "${TXN}/br.log"
            fi
        done
    fi

    if [ "${NEW_DIR}" != "${OLD_DIR}" ]; then
        mkdir -p "${NEW_PATH}/repo" || rollback "创建目标工作区目录失败"
        for r in ${REPOS}; do
            if git -C "${ROOT}/repo/${r}" rev-parse --git-dir >/dev/null 2>&1; then
                git -C "${ROOT}/repo/${r}" worktree move "${OLD_PATH}/repo/${r}" "${NEW_PATH}/repo/${r}" \
                    || rollback "迁移 worktree ${r} 失败"
            else
                mv "${OLD_PATH}/repo/${r}" "${NEW_PATH}/repo/${r}" || rollback "迁移仓库目录 ${r} 失败"
            fi
            echo "${r}" >> "${TXN}/wt.log"
        done
        for entry in "${OLD_PATH}"/*; do
            [ -e "${entry}" ] || continue
            b="$(basename "${entry}")"
            [ "${b}" = "repo" ] && continue
            mv "${entry}" "${NEW_PATH}/" || rollback "迁移工作区文件 ${b} 失败"
        done
    fi

    sh "${SCRIPT_DIR}/work-status.sh" "${NEW_PATH}/status.yaml" set \
        work_id "${NEW_ID}" branch "${SAFE_NEW_BRANCH}" work_dir "${NEW_DIR}" \
        || rollback "更新 status.yaml 失败"

    if grep -q "work_id: \"${OLD_ID}\"" "${ROOT}/AGENTS.md" 2>/dev/null; then
        sh "${SCRIPT_DIR}/project.sh" work-rename "${ROOT}" "${OLD_ID}" "${NEW_ID}" "${SAFE_NEW_BRANCH}" "${NEW_PATH}" --no-commit \
            || rollback "更新 AGENTS.md 工作条目失败"
    else
        echo "WARN: AGENTS.md 未登记 work_id '${OLD_ID}'，跳过工作条目更新" >&2
    fi

    sh "${SCRIPT_DIR}/work-status.sh" "${NEW_PATH}/status.yaml" branch rename "${OLD_BRANCH}" "${SAFE_NEW_BRANCH}" \
        >/dev/null || rollback "更新 branches[] 失败"

    if [ "${NEW_DIR}" != "${OLD_DIR}" ]; then
        rmdir "${OLD_PATH}/repo" 2>/dev/null || true
        rmdir "${OLD_PATH}" 2>/dev/null || rollback "移除旧工作区目录失败"
    fi

    rm -rf "${TXN}"

    RECON="$(sh "${SCRIPT_DIR}/project.sh" work-reconcile "${ROOT}" 2>/dev/null || true)"
    printf '%s\n' "${RECON}"
    ISSUES="$(printf '%s\n' "${RECON}" | awk -F"$(printf '\t')" '/^SUMMARY/ { for (i=1;i<=NF;i++) if ($i ~ /^issues=/) { sub(/^issues=/,"",$i); print $i } }')"
    echo "RENAME_RESULT=applied"
    if [ "${ISSUES:-}" = "0" ]; then
        echo "RECONCILE=ok"
    else
        echo "RECONCILE=issues=${ISSUES:-unknown}"
    fi

    sh "${SCRIPT_DIR}/space.sh" commit "${ROOT}" "chore(tack): rename workspace ${OLD_ID} -> ${NEW_ID}" \
        || echo "WARN: 空间仓库自动提交失败，请检查工作区后重试" >&2
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
# 工作区模板位于 harness/template/（文件复制 + 占位替换，不做字符串拼接）
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

# 5. status.yaml + input.md（模板复制 + 占位替换）
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
if [ -f "${TEMPLATE_DIR}/work-status.yaml" ]; then
    cp "${TEMPLATE_DIR}/work-status.yaml" "${BRANCH_DIR}/status.yaml"
    # 占位替换按字面量拼接（awk index/substr），项目名/分支名含 | & 等 sed 元字符也不会破坏表达式；
    # 临时文件放 .tack/tmp（gitignore 已排除），失败或中断不会在空间仓库留下半成品
    mkdir -p ".tack/tmp"
    STATUS_TMP="$(mktemp ".tack/tmp/work-status.XXXXXX")"
    trap 'rm -f "${STATUS_TMP}"' EXIT HUP INT TERM
    awk -v work_dir="${WORK_BASENAME}" -v project="${PROJECT}" -v branch="${SAFE_BRANCH}" -v created_at="${CREATED_AT}" '
        function rep(s, from, to,    out, i) {
            out = ""
            while ((i = index(s, from)) > 0) {
                out = out substr(s, 1, i - 1) to
                s = substr(s, i + length(from))
            }
            return out s
        }
        {
            line = $0
            line = rep(line, "{{WORK_DIR}}", work_dir)
            line = rep(line, "{{PROJECT}}", project)
            line = rep(line, "{{BRANCH}}", branch)
            line = rep(line, "{{CREATED_AT}}", created_at)
            print line
        }
    ' "${BRANCH_DIR}/status.yaml" > "${STATUS_TMP}"
    if grep -q '{{[A-Z_]*}}' "${STATUS_TMP}"; then
        echo "Error: status.yaml 仍含未替换的模板占位符，请检查模板与入参" >&2
        exit 1
    fi
    mv "${STATUS_TMP}" "${BRANCH_DIR}/status.yaml"
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
