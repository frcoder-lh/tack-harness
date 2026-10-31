#!/bin/sh
# harness-resync.sh — 旧流程空间一次性重建 harness 与 AGENTS.md
#
# 仅用于 update 流程早于「cmd/ 与 AGENTS.md 逐文件裁决」的空间（≤V0.0.22）：用本机
# 最新 skill 的 harness 骨架与 AGENTS.md 覆盖空间，备份并迁移旧登记后切换新版 update
# 流程，之后按常规 update 升级即可，无需再次运行本脚本。
# 必须用本机 skill 目录下的脚本执行；空间内的旧副本会被本次覆盖，不能作为运行源。
#
# Usage:
#   sh <skill>/tack/harness/script/harness-resync.sh <root> [-n|--dry-run] [--skill-root <path>]
#
# 参数:
#   root           tack 空间根目录
#   -n|--dry-run   只输出差异预览，不改动空间文件
#   --skill-root   指定本机 skill 安装目录（默认取本脚本所在 skill）
#
# 行为（顺序固定，避免旧登记丢失）:
#   1. 备份空间 harness/AGENTS.md/tack.yaml/.gitignore 到 .tack/backup/resync-<时间戳>/
#   2. AGENTS.md 仍含旧项目信息区块时先迁移到 tack.yaml
#   3. 用 skill 的 tack/harness 覆盖空间 harness（同名框架文件取新版，用户自建文件保留）
#   4. 用 skill 的 tack/AGENTS.md 覆盖空间 AGENTS.md
#   5. 校验路由、写入 skill_version，并自动提交空间仓库
#
# 退出码: 0 成功；1 失败（备份已生成，可按输出路径回滚）；2 用法错误

set -eu

DRY_RUN=0
ROOT=""
SKILL_ROOT_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1; shift ;;
        --skill-root)
            [ $# -ge 2 ] || { echo "错误：--skill-root 需要参数" >&2; exit 2; }
            SKILL_ROOT_ARG="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --)
            shift; break ;;
        -*)
            echo "错误：未知选项 $1" >&2; exit 2 ;;
        *)
            if [ -z "${ROOT}" ]; then
                ROOT="$1"
            else
                echo "错误：多余参数 $1" >&2; exit 2
            fi
            shift ;;
    esac
done

[ -n "${ROOT}" ] || { echo "Usage: sh harness-resync.sh <root> [-n|--dry-run] [--skill-root <path>]" >&2; exit 2; }
[ -d "${ROOT}" ] || { echo "错误：空间目录不存在: ${ROOT}" >&2; exit 2; }
ROOT="$(cd "${ROOT}" && pwd)"
[ -f "${ROOT}/AGENTS.md" ] && [ -d "${ROOT}/harness" ] || {
    echo "错误：不是 tack 空间（缺 AGENTS.md 或 harness/）: ${ROOT}" >&2
    exit 1
}
[ -d "${ROOT}/.git" ] || { echo "错误：空间根不是 Git 仓库，先执行 init 初始化: ${ROOT}" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${SKILL_ROOT_ARG}" ]; then
    SKILL_ROOT="$(cd "${SKILL_ROOT_ARG}" && pwd)"
else
    SKILL_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi
[ -f "${SKILL_ROOT}/SKILL.md" ] || {
    echo "错误：${SKILL_ROOT} 不是本机 skill 目录（缺 SKILL.md）。请用本机 skill 目录下的 harness-resync.sh 执行，或用 --skill-root 指定" >&2
    exit 1
}
[ -d "${SKILL_ROOT}/tack/harness" ] && [ -f "${SKILL_ROOT}/tack/AGENTS.md" ] || {
    echo "错误：skill 骨架不完整（缺 tack/harness 或 tack/AGENTS.md）: ${SKILL_ROOT}" >&2
    exit 1
}

# 禁止从空间内的旧副本运行：本次覆盖会改写正在执行的脚本
[ -d "${ROOT}/harness/script" ] || { echo "错误：空间缺少 harness/script，无法重建: ${ROOT}" >&2; exit 1; }
SELF_DIR="$(cd "${SCRIPT_DIR}" && pwd -P)"
ROOT_SCRIPT_DIR="$(cd "${ROOT}/harness/script" && pwd -P)"
if [ "${SELF_DIR}" = "${ROOT_SCRIPT_DIR}" ]; then
    echo "错误：请用本机 skill 目录下的脚本执行（空间内旧副本会被本次覆盖）: ${SKILL_ROOT}/tack/harness/script/harness-resync.sh" >&2
    exit 1
fi

. "${SKILL_ROOT}/tack/harness/script/common.sh"
NEW_VER="$(tack_skill_version "${SKILL_ROOT}")" || NEW_VER=""
[ -n "${NEW_VER}" ] || { echo "错误：skill 的 SKILL.md 缺少 version 字段: ${SKILL_ROOT}" >&2; exit 1; }

# legacy_single_to_store <block-file> — 把 V0.0.18 及更早的单项目区块（project: 单对象）
# 转换为 tack.yaml（projects 数组 + 每条 work 带 project 字段）；项目名为空时生成空登记。
# 文件头与 project.sh 的 tack.yaml 模板保持一致（仅注释，不承载数据）。
legacy_single_to_store() {
    _block="$1"
    _name="$(sed -n 's/^  name:[[:space:]]*//p' "${_block}" | head -n 1 | sed 's/^"//; s/"$//')"
    _new="$(mktemp "${ROOT}/.tack/tmp/resync-store.XXXXXX")"
    awk -v name="${_name}" '
        /^skill_version:|^skill_update_url:|^skill_trigger:/ { print; next }
        /^project:/ {
            if (name != "") { print "projects:"; inproj = 1 } else { print "projects: []" }
            next
        }
        inproj == 1 && /^  name:/ { sub(/^  name:/, "  - name:"); print; next }
        inproj == 1 && /^  / { print "  " $0; next }
        inproj == 1 && /^[^[:space:]]/ { inproj = 0 }
        /^work:/ {
            if (name == "") { print "work: []"; next }
            print; inwork = 1; next
        }
        inwork == 1 && /^[[:space:]]*-[[:space:]]*work_id:/ {
            print
            print "    project: \"" name "\""
            next
        }
        { print }
    ' "${_block}" > "${_new}"

    if [ -n "${_name}" ] && ! grep -qE '^  - name:' "${_new}"; then
        rm -f "${_new}"
        echo "错误：旧单项目登记缺少 name，无法转换（备份: ${BACKUP_DIR}）" >&2
        exit 1
    fi
    if ! grep -qE '^projects:' "${_new}" || ! grep -qE '^work:' "${_new}" || ! grep -qE '^skill_version:' "${_new}"; then
        rm -f "${_new}"
        echo "错误：旧单项目登记转换失败（备份: ${BACKUP_DIR}）" >&2
        exit 1
    fi

    {
        echo "# ============================================================"
        echo "# tack 空间登记（\$root/tack.yaml）"
        echo "#"
        echo "# 定位：空间级结构化登记的唯一事实源——空间版本、项目、服务仓库映射与工作区登记。"
        echo "# 维护：由 harness/script/project.sh 读写（init / work / close / update 时自动更新）；"
        echo "#       可手工查阅，结构化修改一律经 project.sh，避免格式偏差。"
        echo "# 分工：工作区实时状态与进展在 space/<workspace>/status.yaml；目录事实取自文件系统，"
        echo "#       分支与仓库状态取自 Git。"
        echo "# ============================================================"
        cat "${_new}"
    } > "${ROOT}/tack.yaml"
    rm -f "${_new}"

    if ! sh "${SKILL_ROOT}/tack/harness/script/project.sh" space-info "${ROOT}" >/dev/null 2>&1; then
        rm -f "${ROOT}/tack.yaml"
        echo "错误：转换后的 tack.yaml 校验失败，已删除该文件（备份: ${BACKUP_DIR}）" >&2
        exit 1
    fi
    if [ -z "${_name}" ]; then
        echo ">> 旧单项目登记缺少项目名，已生成空 tack.yaml；请执行 init 重新登记项目"
    else
        echo ">> 旧单项目登记已转换为 tack.yaml（项目: ${_name}）"
    fi
}

if [ "${DRY_RUN}" -eq 1 ]; then
    echo ">> DRY RUN（不改动空间文件）"
    echo ">> 目标空间: ${ROOT}"
    echo ">> skill: ${SKILL_ROOT}（${NEW_VER}）"
    sh "${SKILL_ROOT}/tack/harness/script/harness-diff.sh" \
        "${SKILL_ROOT}/tack/harness" "${ROOT}/harness" --profile update
    if cmp -s "${SKILL_ROOT}/tack/AGENTS.md" "${ROOT}/AGENTS.md"; then
        echo "AGENTS.md: SAME"
    else
        echo "AGENTS.md: CHANGED（将被新版覆盖，本地增补请先记录或从备份找回）"
    fi
    echo "DRY_RUN=ok"
    exit 0
fi

# —— 1. 备份（覆盖前完成，失败即中止） ——
if [ ! -f "${ROOT}/tack.yaml" ] && ! grep -qF '<!-- tack:info:start -->' "${ROOT}/AGENTS.md"; then
    echo "错误：空间既无 tack.yaml 也无旧登记区块，先执行 init 初始化: ${ROOT}" >&2
    exit 1
fi
BK_OUT="$(sh "${SKILL_ROOT}/tack/harness/script/harness-backup.sh" backup "${ROOT}" resync)"
BACKUP_DIR="$(printf '%s\n' "${BK_OUT}" | sed -n 's/^BACKUP_DIR=//p' | head -n 1)"
[ -n "${BACKUP_DIR}" ] || { echo "错误：备份失败，未做任何改动: ${ROOT}" >&2; exit 1; }
echo ">> 已备份: ${BACKUP_DIR}"

# —— 2. 旧登记迁移（先把项目数据落到 tack.yaml，后续覆盖 AGENTS.md 才不会丢） ——
mkdir -p "${ROOT}/.tack/tmp"
if [ -f "${ROOT}/tack.yaml" ]; then
    sh "${SKILL_ROOT}/tack/harness/script/project.sh" space-info "${ROOT}" >/dev/null
else
    _block="$(mktemp "${ROOT}/.tack/tmp/resync-block.XXXXXX")"
    awk -v s='<!-- tack:info:start -->' -v e='<!-- tack:info:end -->' '
        index($0, s) == 1 { inb = 1; next }
        index($0, e) == 1 { inb = 0; next }
        inb == 1 { print }
    ' "${ROOT}/AGENTS.md" > "${_block}"
    if grep -qE '^projects:' "${_block}"; then
        sh "${SKILL_ROOT}/tack/harness/script/project.sh" migrate "${ROOT}" --no-commit
        rm -f "${_block}"
    elif grep -qE '^project:' "${_block}"; then
        legacy_single_to_store "${_block}"
        rm -f "${_block}"
    else
        rm -f "${_block}"
        echo "错误：旧登记区块结构无法识别（既无 projects 也无 project），请按 AGENTS.md 模板手工迁移（备份: ${BACKUP_DIR}）" >&2
        exit 1
    fi
fi

# —— 3. 覆盖 harness：同名框架文件取新版，用户自建文件保留 ——
cp -R "${SKILL_ROOT}/tack/harness/." "${ROOT}/harness/"
# —— 4. 覆盖 AGENTS.md（旧登记已迁出） ——
cp "${SKILL_ROOT}/tack/AGENTS.md" "${ROOT}/AGENTS.md"

# —— 5. .gitignore 兜底：缺失时按新版模板创建，存在且无点目录忽略时追加 .*/ ——
GITIGNORE="${ROOT}/.gitignore"
if [ ! -f "${GITIGNORE}" ]; then
    cp "${SKILL_ROOT}/tack/.gitignore" "${GITIGNORE}"
    echo ">> .gitignore 已按新版模板创建"
elif ! grep -qE '^\.\*/' "${GITIGNORE}" && ! grep -q '.tack/' "${GITIGNORE}"; then
    printf '\n.*/\n' >> "${GITIGNORE}"
    echo ">> .gitignore 已追加 .*/"
fi

# 可选加速层：已有声明不覆盖，失败不阻断
sh "${SKILL_ROOT}/tack/harness/script/hook/install-hooks.sh" "${ROOT}" >/dev/null 2>&1 || true

# —— 6. 校验与收尾 ——
sh "${SKILL_ROOT}/tack/harness/script/scan-routes.sh" list "${ROOT}/harness" >/dev/null
echo ">> 路由校验通过"
sh "${SKILL_ROOT}/tack/harness/script/project.sh" skill-version "${ROOT}" "${NEW_VER}" --no-commit
sh "${SKILL_ROOT}/tack/harness/script/space.sh" commit "${ROOT}" "chore(tack): resync harness"

echo "✅ 空间框架已同步到 ${NEW_VER}；备份: ${BACKUP_DIR}"
echo "   回滚: sh ${SKILL_ROOT}/tack/harness/script/harness-backup.sh restore ${ROOT} ${BACKUP_DIR}"
