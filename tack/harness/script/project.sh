#!/bin/sh
# project.sh — 维护 tack 空间登记（$ROOT/tack.yaml），兼容旧版 AGENTS.md 项目信息区块
#
# 存储解析（每次读取前判定）：
#   1. $ROOT/tack.yaml 存在且含顶层 projects/work 字段 -> 使用 tack.yaml（新存储）
#   2. tack.yaml 不存在且 AGENTS.md 含 <!-- tack:info:start --> 区块 -> 使用旧区块（兼容）
#   3. tack.yaml 存在但结构无效 -> 报错退出；两者都无 -> 提示先执行 ensure
#
# tack.yaml 字段（第一版沿用旧区块字段与取值）：
#   skill_version: "" / skill_update_url: "..." / skill_trigger: "tack"
#   projects: [{name, keywords, description, root_path, repo_scan_path, service_repo_mapping}]
#   work:     [{work_id, project, description, trigger_words, work_path, branch, services, status, created_at}]
#
# Usage:
#   sh project.sh ensure            <root>                                              # 新空间创建 tack.yaml；旧区块存在时保持旧存储（幂等）
#   sh project.sh migrate           <root> [--no-commit]                                # 备份旧区块 -> 写 tack.yaml -> 核对 -> 删除 AGENTS.md 登记正文
#   sh project.sh store-path        <root>                                              # 输出 STORE=<path> 与 STORE_KIND=<tackyaml|legacy>
#   sh project.sh space-info        <root>                                              # 空间元信息：版本、项目数、工作区数、活跃工作区数
#   sh project.sh project-add       <root> <name> [description] [--no-commit]           # 追加项目条目并创建 wiki/<name>/
#   sh project.sh project-set       <root> <name> <description|root_path> <value>       # 更新项目下简单标量
#   sh project.sh project-keywords  <root> <name> <kw1,kw2,...> [--no-commit]           # 覆盖写某项目 keywords
#   sh project.sh project-service-repo <root> <name> <service_name> <repo_name> <repo_git> <repo_path> [--no-commit]
#                                                                                       # 追加某项目的 service_repo_mapping（repo_git 可传空串）
#   sh project.sh project-list      <root>                                              # 输出 name<TAB>description，每行一个项目
#   sh project.sh project-get       <root> <name>                                       # 输出单项目详情（标量 + 服务映射行）
#   sh project.sh repo-list         <root> <project>                                    # 只输出该项目服务映射（必须带项目名）
#   sh project.sh skill-version     <root> <version> [--if-empty] [--no-commit]         # 写入 skill_version；--if-empty 仅空值时填充（已有值跳过）
#   sh project.sh work-add      <root> <project> <id> <description> <work_path> <branch> <svc1,svc2> [triggers]
#   sh project.sh work-set      <root> <id> <status>                                # 更新某工作条目状态
#   sh project.sh work-remove   <root> <id>                                         # 移除某工作条目（close 时工作区目录删除后同步清理登记）
#   sh project.sh work-path     <root> <id> <work_path>                             # 修正某工作条目的 work_path（reconcile 发现重命名残留时校准）
#   sh project.sh work-rename   <root> <old-id> <new-id> <new-branch> <new-work_path> # 重命名工作条目的 work_id/branch/work_path
#   sh project.sh work-reconcile <root>                                             # 对账 work 条目与 space/ 实际目录，只报告差异不改写
#   sh project.sh work-list     <root> [project]                                     # 输出工作区登记行（可只取某项目）
#   sh project.sh work-get      <root> <id>                                          # 输出单个工作区条目详情
#   sh project.sh work-services <root> <id> <svc1,svc2,...> [status.yaml] [--no-commit]
#                                                                                   # 覆盖写某工作条目 services；给 status.yaml 时同步其顶层 services
#   sh project.sh work-trigger  <root> <id> <kw1,kw2,...> [--no-commit]            # 追加触发词到 work 条目（去重、跳过等于 work_id/branch 的词）
#
# --no-commit: 跳过尾部空间仓库自动提交，供 init-tack / update 等复合流程统一收尾提交
#
# 退出码: 0 成功 / 非 0 失败（AGENTS.md 不存在、项目或 work_id 找不到/重复等）

set -e

ACTION="$1"
ROOT="$2"
AGENTS="${ROOT}/AGENTS.md"
STORE_FILE="${ROOT}/tack.yaml"

START_MARK='<!-- tack:info:start -->'
END_MARK='<!-- tack:info:end -->'

# 当前生效的数据文件与存储类型（resolve_store 设定）
STORE=""
STORE_KIND=""
# 本次动作在空间登记之外额外写入的文件（如 work-services 同步的 status.yaml），纳入提交清单
EXTRA_COMMIT=""

# 共享 YAML 标量/行内列表函数（唯一事实源 script/yamlib.awk）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YAML_LIB="$(cat "${SCRIPT_DIR}/yamlib.awk")"

# 空间级互斥锁：登记写入与空间仓库提交全程串行，锁内重新读取最新登记
if [ ! -f "${SCRIPT_DIR}/space-lock.sh" ]; then
    echo "Error: 缺少空间锁实现: ${SCRIPT_DIR}/space-lock.sh" >&2
    exit 1
fi
. "${SCRIPT_DIR}/space-lock.sh"

if [ -z "${ACTION}" ] || [ -z "${ROOT}" ]; then
    echo "Usage: sh project.sh <ensure|migrate|store-path|space-info|project-add|project-set|project-keywords|project-service-repo|project-list|project-get|repo-list|skill-version|work-add|work-set|work-remove|work-path|work-rename|work-reconcile|work-list|work-get|work-services|work-trigger> <root> [args...]" >&2
    exit 1
fi
if [ ! -f "${AGENTS}" ] && [ ! -f "${STORE_FILE}" ]; then
    echo "Error: 不是 tack 空间（缺 AGENTS.md 与 tack.yaml）: ${ROOT}" >&2
    exit 1
fi

# 临时文件统一落空间运行时目录 .tack/tmp（.gitignore 已排除）：脚本内任意步骤
# 失败或中断都不会把半成品留在 AGENTS.md 同目录，被空间仓库自动提交带走
mkdir -p "${ROOT}/.tack/tmp"
TMP_DIR="$(mktemp -d "${ROOT}/.tack/tmp/project.XXXXXX")"
cleanup_tmp() { tack_space_lock_release; rm -rf "${TMP_DIR}"; }
trap cleanup_tmp EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
new_tmp() { mktemp "${TMP_DIR}/f.XXXXXX"; }

# --no-commit 可出现在任意动作的参数尾部：复合流程（init-tack、update）
# 自行统一收尾提交时，抑制本脚本尾部的单次自动提交
NO_COMMIT=0
for _arg in "$@"; do
    [ "${_arg}" = "--no-commit" ] && NO_COMMIT=1
done

# 双引号转义
esc() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# 逗号分隔列表 -> YAML 行内序列：a,b → ["a", "b"]（去空白、去空项）
csv_to_yaml() {
    printf '%s' "$1" | awk "${YAML_LIB}"'{ print yaml_inline_list($0) }'
}

# 提取数据体到指定临时文件（tack.yaml 取全文；旧存储取两个标记之间的内容）
extract_body() {
    out="$1"
    if [ "${STORE_KIND}" = "tackyaml" ]; then
        cp "${STORE}" "${out}"
        return
    fi
    awk -v s="${START_MARK}" -v e="${END_MARK}" '
        index($0, s) == 1 { inblock=1; next }
        index($0, e) == 1 { inblock=0; next }
        inblock == 1 { print }
    ' "${AGENTS}" > "${out}"
}

# 用临时文件中的新 body 重写数据（tack.yaml 整文件替换；旧区块只替换标记之间）
rewrite_block() {
    body="$1"
    tmp="$(new_tmp)"
    if [ "${STORE_KIND}" = "tackyaml" ]; then
        cp "${body}" "${tmp}" && mv "${tmp}" "${STORE}"
        return
    fi
    awk -v bodyfile="${body}" -v s="${START_MARK}" -v e="${END_MARK}" '
        index($0, s) == 1 { print; while ((getline line < bodyfile) > 0) print line; inblock=1; next }
        index($0, e) == 1 { inblock=0; print; next }
        inblock != 1 { print }
    ' "${AGENTS}" > "${tmp}" && mv "${tmp}" "${AGENTS}"
}

has_block() {
    [ -f "${AGENTS}" ] && grep -qF "${START_MARK}" "${AGENTS}" && grep -qF "${END_MARK}" "${AGENTS}"
}

# tackyaml_valid — 顶层 projects/work 字段齐备即视为有效；含制表符视为格式损坏
tackyaml_valid() {
    [ -f "${STORE_FILE}" ] || return 1
    grep -qE '^projects:' "${STORE_FILE}" && grep -qE '^work:' "${STORE_FILE}" \
        && ! grep -q "$(printf '\t')" "${STORE_FILE}"
}

# resolve_store — 设定 STORE/STORE_KIND：tack.yaml 优先；不存在时兼容 AGENTS.md 旧区块；
# tack.yaml 存在但无效时明确报错，不静默回退
resolve_store() {
    if [ -f "${STORE_FILE}" ]; then
        if ! tackyaml_valid; then
            echo "Error: tack.yaml 无效（须含顶层 projects/work 字段且不含制表符）: ${STORE_FILE}" >&2
            exit 1
        fi
        STORE="${STORE_FILE}"; STORE_KIND="tackyaml"
        return 0
    fi
    if has_block; then
        STORE="${AGENTS}"; STORE_KIND="legacy"
        return 0
    fi
    echo "Error: 未找到 tack.yaml，AGENTS.md 也无可用的项目信息区块；先执行 project.sh ensure" >&2
    exit 1
}

# require_projects — 校验多项目结构（projects 数组）存在；旧版单项目区块给出迁移提示
require_projects() {
    grep -qE '^projects:' "${STORE}" && return 0
    if grep -qE '^project:' "${STORE}"; then
        echo "Error: 检测到旧版单项目区块 project:。多项目结构须为 projects 数组，且每个 work 条目带 project 字段；请先执行 project.sh migrate" >&2
    else
        echo "Error: 空间登记缺少 projects 字段，先执行 project.sh ensure" >&2
    fi
    exit 1
}

# project_exists <name> — projects 数组中是否存在该 name
project_exists() {
    awk -v want="$1" "${YAML_LIB}"'
        BEGIN { inproj=0 }
        /^projects:/ { inproj=1; next }
        inproj==1 && /^[^[:space:]]/ { inproj=0 }
        inproj==1 && /^  - name:/ {
            if (val($0) == want) { found=1 }
        }
        END { exit (found ? 0 : 1) }
    ' "${STORE}"
}

# ensure: 新空间创建 tack.yaml；旧区块存在时保持旧存储（迁移由 migrate 负责）
cmd_ensure() {
    if [ -f "${STORE_FILE}" ]; then
        if tackyaml_valid; then
            echo "tack.yaml 已存在，跳过"
        else
            echo "Error: tack.yaml 无效（须含顶层 projects/work 字段且不含制表符）: ${STORE_FILE}" >&2
            exit 1
        fi
        return 0
    fi
    if has_block; then
        if grep -qE '^projects:' "${AGENTS}"; then
            echo "检测到 AGENTS.md 旧版项目信息区块，继续使用旧存储（执行 migrate 可迁移到 tack.yaml）"
            return 0
        fi
        echo "Error: AGENTS.md 旧区块缺少 projects 字段，请先执行 project.sh migrate 或手工核对" >&2
        exit 1
    fi
    tmp_body="$(new_tmp)"
    cat > "${tmp_body}" <<'EOF'
# ============================================================
# tack 空间登记（$root/tack.yaml）
#
# 定位：空间级结构化登记的唯一事实源——空间版本、项目、服务仓库映射与工作区登记。
# 维护：由 harness/script/project.sh 读写（init / work / close / update 时自动更新）；
#       可手工查阅，结构化修改一律经 project.sh，避免格式偏差。
# 分工：工作区实时状态与进展在 space/<workspace>/status.yaml；目录事实取自文件系统，
#       分支与仓库状态取自 Git。
# ============================================================
skill_version: ""
skill_update_url: "https://github.com/frcoder-lh/tack-harness"
skill_trigger: "tack"
projects: []
work: []
EOF
    cp "${tmp_body}" "${STORE_FILE}"
    rm -f "${tmp_body}"
    echo "已创建 tack.yaml（空间登记）"
}

# 旧存储区块体（不依赖当前 STORE_KIND，供 migrate 读取 AGENTS.md）
extract_legacy_body() {
    out="$1"
    awk -v s="${START_MARK}" -v e="${END_MARK}" '
        index($0, s) == 1 { inblock=1; next }
        index($0, e) == 1 { inblock=0; next }
        inblock == 1 { print }
    ' "${AGENTS}" > "${out}"
}

# 迁移核对快照：只比较关键标识（正文原样复制，快照用于防提取/写入错位）
data_snapshot() {
    awk "${YAML_LIB}"'
        function flushw() {
            if (curw != "") print "W|" curw "|" wprj
            curw=""; wprj=""
        }
        BEGIN { inproj=0; inwork=0; curw="" }
        /^skill_version:/ { if (sv == "") sv=val($0) }
        /^skill_update_url:/ { if (su == "") su=val($0) }
        /^skill_trigger:/ { if (stg == "") stg=val($0) }
        /^projects:/ { inproj=1; inwork=0; next }
        /^work:/ { flushw(); inproj=0; inwork=1; next }
        inproj==1 && /^[^[:space:]]/ { inproj=0 }
        inproj==1 && /^  - name:/ { print "P|" val($0) }
        inwork==1 && /^[^[:space:]]/ { flushw(); inwork=0 }
        inwork==1 && /^[[:space:]]*-[[:space:]]*work_id:/ { flushw(); curw=val($0); next }
        inwork==1 && curw != "" && /^[[:space:]]+project:/ { wprj=val($0) }
        END { flushw(); print "S|" sv "|" su "|" stg }
    ' "$1" | sort
}

# 删除 AGENTS.md 中的「## 项目信息」整节（标题至结束标记）
remove_agents_block() {
    tmp="$(new_tmp)"
    awk -v e="${END_MARK}" '
        /^##[[:space:]]+项目信息[[:space:]]*$/ { skip=1; next }
        skip==1 && index($0, e) == 1 { skip=0; next }
        skip==1 { next }
        { print }
    ' "${AGENTS}" > "${tmp}" && mv "${tmp}" "${AGENTS}"
}

# migrate: 备份 -> 提取旧区块 -> 写 tack.yaml -> 核对 -> 删除 AGENTS.md 登记正文
cmd_migrate() {
    if [ ! -f "${STORE_FILE}" ] && ! has_block; then
        echo "Error: 无可迁移的登记（既无 tack.yaml 也无 AGENTS.md 项目信息区块）" >&2
        exit 1
    fi
    mkdir -p "${ROOT}/.tack/backup"
    BDIR="${ROOT}/.tack/backup/migrate-$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "${BDIR}"
    [ -f "${AGENTS}" ] && cp "${AGENTS}" "${BDIR}/AGENTS.md"
    [ -f "${STORE_FILE}" ] && cp "${STORE_FILE}" "${BDIR}/tack.yaml"
    echo "BACKUP_DIR=${BDIR}"

    if [ -f "${STORE_FILE}" ]; then
        tackyaml_valid || { echo "Error: tack.yaml 无效: ${STORE_FILE}" >&2; exit 1; }
        if ! has_block; then
            echo "tack.yaml 已是唯一登记，无需迁移"
            echo "MIGRATE_RESULT=ok"
            return 0
        fi
        BLOCK_BODY="$(new_tmp)"
        extract_legacy_body "${BLOCK_BODY}"
        SNAP_Y="$(new_tmp)"; SNAP_B="$(new_tmp)"
        data_snapshot "${STORE_FILE}" > "${SNAP_Y}"
        data_snapshot "${BLOCK_BODY}" > "${SNAP_B}"
        if ! cmp -s "${SNAP_Y}" "${SNAP_B}"; then
            echo "Error: tack.yaml 与 AGENTS.md 旧区块数据不一致，停止迁移（备份见 ${BDIR}）" >&2
            exit 1
        fi
        remove_agents_block
        echo "已保留 tack.yaml，删除 AGENTS.md 登记正文"
    else
        BLOCK_BODY="$(new_tmp)"
        extract_legacy_body "${BLOCK_BODY}"
        if ! grep -qE '^projects:' "${BLOCK_BODY}" || ! grep -qE '^work:' "${BLOCK_BODY}"; then
            echo "Error: AGENTS.md 旧区块缺少顶层 projects/work 字段，无法迁移" >&2
            exit 1
        fi
        NEW_FILE="$(new_tmp)"
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
            cat "${BLOCK_BODY}"
        } > "${NEW_FILE}"
        cp "${NEW_FILE}" "${STORE_FILE}"
        SNAP_Y="$(new_tmp)"; SNAP_B="$(new_tmp)"
        data_snapshot "${STORE_FILE}" > "${SNAP_Y}"
        data_snapshot "${BLOCK_BODY}" > "${SNAP_B}"
        if ! cmp -s "${SNAP_Y}" "${SNAP_B}"; then
            rm -f "${STORE_FILE}"
            echo "Error: 写入 tack.yaml 后核对不一致，已回滚（备份见 ${BDIR}）" >&2
            exit 1
        fi
        remove_agents_block
        echo "已将 AGENTS.md 旧区块迁移到 tack.yaml，并删除登记正文"
    fi
    echo "MIGRATE_RESULT=ok"
    echo "STORE=${STORE_FILE}"
}

# project-add: 追加项目条目（projects 数组），并创建 wiki/<name>/ 目录
cmd_project_add() {
    NAME="$3"
    DESC="${4:-}"
    [ "${DESC}" = "--no-commit" ] && DESC=""
    [ -n "${NAME}" ] || { echo "Usage: project.sh project-add <root> <name> [description]" >&2; exit 1; }
    case "${NAME}" in
        */*|*'\'*|*" "*|*'|'*|*'&'*|.|..)
            echo "Error: 非法项目名 '${NAME}'（仅接受单层目录名，不得含分隔符、空白或 sed 元字符 | &）" >&2
            exit 1
            ;;
    esac
    resolve_store
    require_projects
    if project_exists "${NAME}"; then
        echo "Error: 项目 '${NAME}' 已存在于 projects 数组" >&2
        exit 1
    fi

    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"
    tmp_entry="$(new_tmp)"
    cat > "${tmp_entry}" <<EOF
  - name: "$(esc "${NAME}")"
    keywords: []
    description: "$(esc "${DESC}")"
    root_path: ""
    repo_scan_path: []
    service_repo_mapping: []
EOF

    tmp_new="$(new_tmp)"
    if grep -qE '^projects:[[:space:]]*\[\][[:space:]]*(#.*)?$' "${tmp_body}"; then
        awk -v entryfile="${tmp_entry}" '
            /^projects:[[:space:]]*\[\][[:space:]]*(#.*)?$/ {
                print "projects:"
                while ((getline l < entryfile) > 0) print l
                next
            }
            { print }
        ' "${tmp_body}" > "${tmp_new}"
    else
        awk -v entryfile="${tmp_entry}" '
            BEGIN { done=0 }
            done==0 && /^work:/ {
                while ((getline l < entryfile) > 0) print l
                done=1
            }
            { print }
            END {
                if (done==0) { while ((getline l < entryfile) > 0) print l }
            }
        ' "${tmp_body}" > "${tmp_new}"
    fi

    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_entry}" "${tmp_new}"
    mkdir -p "${ROOT}/wiki/${NAME}"
    echo "已登记项目: ${NAME}（知识目录 wiki/${NAME}/）"
}

# project-set: 更新指定项目下的简单标量（项目名不可改，避免 wiki 目录与 work.project 失联）
cmd_project_set() {
    NAME="$3"; FIELD="$4"; VALUE="$5"
    [ -n "${NAME}" ] && [ -n "${FIELD}" ] || { echo "Usage: project.sh project-set <root> <name> <description|root_path> <value>" >&2; exit 1; }
    case "${FIELD}" in
        description|root_path) ;;
        *) echo "Error: project-set 仅支持 description/root_path（项目名不可改，列表字段用 project-keywords / project-service-repo）" >&2; exit 1 ;;
    esac
    resolve_store
    require_projects
    project_exists "${NAME}" || { echo "Error: 项目 '${NAME}' 不存在" >&2; exit 1; }

    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"
    tmp_new="$(new_tmp)"
    awk -v want="$(esc "${NAME}")" -v field="${FIELD}" -v value="$(esc "${VALUE}")" "${YAML_LIB}"'
        BEGIN { inproj=0; cur=""; done=0 }
        /^projects:/ { inproj=1; print; next }
        inproj==1 && /^[^[:space:]]/ { inproj=0 }
        inproj==1 && /^  - name:/ {
            cur=val($0)
            print; next
        }
        inproj==1 && cur==want && done==0 && $0 ~ "^    " field ":[[:space:]]*" {
            print "    " field ": \"" value "\""
            done=1
            next
        }
        { print }
        END { if (done==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未在项目 '${NAME}' 中找到字段 '${FIELD}'" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已更新 projects[${NAME}].${FIELD}"
}

# project-list: 输出全部项目（name<TAB>description）
cmd_project_list() {
    resolve_store
    require_projects
    awk "${YAML_LIB}"'
        BEGIN { inproj=0; have=0; name=""; desc="" }
        /^projects:/ { inproj=1; next }
        inproj==1 && /^[^[:space:]]/ {
            if (have) printf "%s\t%s\n", name, desc
            inproj=0; have=0
        }
        inproj==1 && /^  - name:/ {
            if (have) printf "%s\t%s\n", name, desc
            name=val($0)
            desc=""; have=1; next
        }
        inproj==1 && have && /^    description:/ {
            desc=val($0)
        }
        END { if (have) printf "%s\t%s\n", name, desc }
    ' "${STORE}"
}

# store-path: 输出当前生效的数据文件与存储类型（供 work.sh 等需要原子回滚的调用方）
cmd_store_path() {
    resolve_store
    echo "STORE=${STORE}"
    echo "STORE_KIND=${STORE_KIND}"
}

# space-info: 空间元信息（只返回概要，不读全量登记）
cmd_space_info() {
    resolve_store
    awk -v kind="${STORE_KIND}" "${YAML_LIB}"'
        function flushwork() {
            if (curw != "") { nwork++; if (wst != "completed") nactive++ }
            curw=""; wst=""
        }
        BEGIN { inproj=0; inwork=0; nproj=0; nwork=0; nactive=0; curw=""; wst="" }
        /^skill_version:/ { if (sv == "") sv=val($0) }
        /^skill_update_url:/ { if (su == "") su=val($0) }
        /^skill_trigger:/ { if (stg == "") stg=val($0) }
        /^projects:/ { inproj=1; inwork=0; next }
        /^work:/ { flushwork(); inproj=0; inwork=1; next }
        inproj==1 && /^[^[:space:]]/ { inproj=0 }
        inproj==1 && /^  - name:/ { nproj++ }
        inwork==1 && /^[^[:space:]]/ { flushwork(); inwork=0 }
        inwork==1 && /^[[:space:]]*-[[:space:]]*work_id:/ { flushwork(); curw=val($0); next }
        inwork==1 && curw != "" && /^[[:space:]]+status:/ { wst=val($0) }
        END {
            flushwork()
            print "STORE_KIND=" kind
            print "SKILL_VERSION=" sv
            print "SKILL_UPDATE_URL=" su
            print "SKILL_TRIGGER=" stg
            print "PROJECTS=" nproj
            print "WORK=" nwork
            print "WORK_ACTIVE=" nactive
        }
    ' "${STORE}"
}

# project-get: 输出单项目详情（标量 + 服务映射行），不返回其他项目
cmd_project_get() {
    NAME="$3"
    [ -n "${NAME}" ] || { echo "Usage: project.sh project-get <root> <name>" >&2; exit 1; }
    resolve_store
    require_projects
    project_exists "${NAME}" || { echo "Error: 项目 '${NAME}' 不存在" >&2; exit 1; }

    awk -v want="$(esc "${NAME}")" "${YAML_LIB}"'
        function flushmap() {
            if (m_svc != "") mapbuf = mapbuf sprintf("SERVICE_REPO\t%s\t%s\t%s\t%s\n", m_svc, m_repo, m_git, m_path)
            m_svc=""; m_repo=""; m_git=""; m_path=""
        }
        BEGIN { inproj=0; cur=""; inmap=0 }
        /^projects:/ { inproj=1; next }
        inproj==1 && /^[^[:space:]]/ { if (cur==want) flushmap(); inproj=0; cur="" }
        inproj==1 && /^  - name:/ { if (cur==want) flushmap(); cur=val($0); inmap=0; next }
        inproj==1 && cur==want && /^    description:/ { desc=val($0); next }
        inproj==1 && cur==want && /^    root_path:/ { rootp=val($0); next }
        inproj==1 && cur==want && /^    keywords:/ { kw=yaml_csv(val($0)); next }
        inproj==1 && cur==want && /^    repo_scan_path:/ { scan=yaml_csv(val($0)); next }
        inproj==1 && cur==want && /^    service_repo_mapping:[[:space:]]*\[\][[:space:]]*(#.*)?$/ { next }
        inproj==1 && cur==want && /^      - service_name:/ { flushmap(); m_svc=val($0); next }
        inproj==1 && cur==want && /^        repo_name:/ { m_repo=val($0); next }
        inproj==1 && cur==want && /^        repo_git:/ { m_git=val($0); next }
        inproj==1 && cur==want && /^        repo_path:/ { m_path=val($0); next }
        END {
            if (cur==want) flushmap()
            print "NAME=" want
            print "DESCRIPTION=" desc
            print "ROOT_PATH=" rootp
            print "KEYWORDS=" kw
            print "REPO_SCAN_PATH=" scan
            printf "%s", mapbuf
        }
    ' "${STORE}"
}

# repo-list: 输出指定项目的服务仓库映射（仓库查询必须带项目名）
cmd_repo_list() {
    NAME="$3"
    [ -n "${NAME}" ] || { echo "Error: 仓库查询必须带项目名: project.sh repo-list <root> <project>" >&2; exit 2; }
    resolve_store
    require_projects
    project_exists "${NAME}" || { echo "Error: 项目 '${NAME}' 不存在" >&2; exit 1; }

    awk -v want="$(esc "${NAME}")" "${YAML_LIB}"'
        function flushmap() {
            if (m_svc != "") printf "%s\t%s\t%s\t%s\n", m_svc, m_repo, m_git, m_path
            m_svc=""; m_repo=""; m_git=""; m_path=""
        }
        BEGIN { inproj=0; cur="" }
        /^projects:/ { inproj=1; next }
        inproj==1 && /^[^[:space:]]/ { if (cur==want) flushmap(); inproj=0; cur="" }
        inproj==1 && /^  - name:/ { if (cur==want) flushmap(); cur=val($0); next }
        inproj==1 && cur==want && /^      - service_name:/ { flushmap(); m_svc=val($0); next }
        inproj==1 && cur==want && /^        repo_name:/ { m_repo=val($0); next }
        inproj==1 && cur==want && /^        repo_git:/ { m_git=val($0); next }
        inproj==1 && cur==want && /^        repo_path:/ { m_path=val($0); next }
        END { if (cur==want) flushmap() }
    ' "${STORE}"
}

# work-list: 输出工作区登记行；给项目名时只返回该项目
cmd_work_list() {
    FILTER="${3:-}"
    resolve_store
    awk -v filter="$(esc "${FILTER}")" "${YAML_LIB}"'
        function flushwork() {
            if (curw != "" && (filter == "" || wprj == filter))
                printf "WORK\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", curw, wprj, wst, wbr, wpath, wdesc, wtrig, wsvc
            curw=""; wprj=""; wst=""; wbr=""; wpath=""; wdesc=""; wtrig=""; wsvc=""
        }
        BEGIN { inwork=0; curw="" }
        /^work:/ { inwork=1; next }
        inwork==1 && /^[^[:space:]]/ { flushwork(); inwork=0 }
        inwork==1 && /^[[:space:]]*-[[:space:]]*work_id:/ { flushwork(); curw=val($0); next }
        inwork==1 && curw != "" && /^[[:space:]]+project:/ { wprj=val($0) }
        inwork==1 && curw != "" && /^[[:space:]]+status:/ { wst=val($0) }
        inwork==1 && curw != "" && /^[[:space:]]+branch:/ { wbr=val($0) }
        inwork==1 && curw != "" && /^[[:space:]]+work_path:/ { wpath=val($0) }
        inwork==1 && curw != "" && /^[[:space:]]+description:/ { wdesc=val($0) }
        inwork==1 && curw != "" && /^[[:space:]]+trigger_words:/ { wtrig=yaml_csv(val($0)) }
        inwork==1 && curw != "" && /^[[:space:]]+services:/ { wsvc=yaml_csv(val($0)) }
        END { flushwork() }
    ' "${STORE}"
}

# work-get: 输出单个工作区条目详情（不读其他条目）
cmd_work_get() {
    ID="$3"
    [ -n "${ID}" ] || { echo "Usage: project.sh work-get <root> <id>" >&2; exit 1; }
    resolve_store
    OUT="$(awk -v want="$(esc "${ID}")" "${YAML_LIB}"'
        function flushwork() {
            if (curw == want && found == 0) { found=1; emit() }
            curw=""; wprj=""; wst=""; wbr=""; wpath=""; wdesc=""; wtrig=""; wsvc=""
        }
        function emit() {
            print "WORK_ID=" curw
            print "PROJECT=" wprj
            print "STATUS=" wst
            print "BRANCH=" wbr
            print "WORK_PATH=" wpath
            print "DESCRIPTION=" wdesc
            print "TRIGGER_WORDS=" wtrig
            print "SERVICES=" wsvc
        }
        BEGIN { inwork=0; curw="" }
        /^work:/ { inwork=1; next }
        inwork==1 && /^[^[:space:]]/ { flushwork(); inwork=0 }
        inwork==1 && /^[[:space:]]*-[[:space:]]*work_id:/ { flushwork(); curw=val($0); next }
        inwork==1 && curw != "" && /^[[:space:]]+project:/ { wprj=val($0) }
        inwork==1 && curw != "" && /^[[:space:]]+status:/ { wst=val($0) }
        inwork==1 && curw != "" && /^[[:space:]]+branch:/ { wbr=val($0) }
        inwork==1 && curw != "" && /^[[:space:]]+work_path:/ { wpath=val($0) }
        inwork==1 && curw != "" && /^[[:space:]]+description:/ { wdesc=val($0) }
        inwork==1 && curw != "" && /^[[:space:]]+trigger_words:/ { wtrig=yaml_csv(val($0)) }
        inwork==1 && curw != "" && /^[[:space:]]+services:/ { wsvc=yaml_csv(val($0)) }
        END { flushwork(); if (!found) exit 3 }
    ' "${STORE}")" || { echo "Error: 未找到 work_id '${ID}' 的条目" >&2; exit 1; }
    printf '%s\n' "${OUT}"
}

# skill-version: 写入区块顶级标量 skill_version
#   --if-empty: 仅当前值为空串/缺失时填充，已有非空值则跳过（init 幂等回填，不降级）
cmd_skill_version() {
    NEWVER="$3"
    IF_EMPTY=0
    for _a in "$@"; do
        [ "${_a}" = "--if-empty" ] && IF_EMPTY=1
    done
    if [ -z "${NEWVER}" ] || printf '%s' "${NEWVER}" | grep -q '^--'; then
        echo "Usage: project.sh skill-version <root> <version> [--if-empty] [--no-commit]" >&2
        exit 1
    fi
    resolve_store

    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"

    if [ "${IF_EMPTY}" -eq 1 ]; then
        CUR=$(awk "${YAML_LIB}"'
            /^skill_version:[[:space:]]*/ {
                print val($0)
                exit
            }
        ' "${tmp_body}")
        if [ -n "${CUR}" ]; then
            echo "skill_version 已有值 \"${CUR}\"，跳过填充"
            rm -f "${tmp_body}"
            return 0
        fi
    fi

    tmp_new="$(new_tmp)"
    awk -v ver="$(esc "${NEWVER}")" '
        BEGIN { done=0 }
        /^skill_version:[[:space:]]*/ {
            print "skill_version: \"" ver "\""
            done=1
            next
        }
        { print }
        END { if (done==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 空间登记中缺少 skill_version 字段" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已更新 skill_version: ${NEWVER}"
}

# work-add: 追加工作条目（必须归属一个已有项目）
cmd_work_add() {
    PROJECT="$3"; ID="$4"; DESC="$5"; WPATH="$6"; BRANCH="$7"; SERVICES="${8:-}"; TRIGGERS="${9:-}"
    # --no-commit 可落在第 8/9 位（未传 services/triggers 时），此时清空对应参数
    [ "${SERVICES}" = "--no-commit" ] && SERVICES=""
    [ "${TRIGGERS}" = "--no-commit" ] && TRIGGERS=""
    [ -n "${PROJECT}" ] && [ -n "${ID}" ] || { echo "Usage: project.sh work-add <root> <project> <id> <description> <work_path> <branch> [services] [triggers]" >&2; exit 1; }
    resolve_store
    require_projects
    project_exists "${PROJECT}" || { echo "Error: 项目 '${PROJECT}' 不存在，先执行 project.sh project-add" >&2; exit 1; }

    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"

    # 同 work_id 已存在则拒绝（幂等保护）
    if awk -v id="$(esc "${ID}")" "${YAML_LIB}"'
        /^[[:space:]]*-[[:space:]]*work_id:/ {
            if (val($0) == id) found=1
        }
        END { exit (found?0:1) }
    ' "${tmp_body}"; then
        echo "Error: work_id '${ID}' 已存在于空间登记" >&2
        rm -f "${tmp_body}"; exit 1
    fi

    # services / triggers 逗号分隔 -> ["a", "b"]
    SVC_LIST=$(csv_to_yaml "${SERVICES}")
    TRIG_LIST=$(csv_to_yaml "${TRIGGERS}")
    CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

    tmp_entry="$(new_tmp)"
    cat > "${tmp_entry}" <<EOF
  - work_id: "$(esc "${ID}")"
    project: "$(esc "${PROJECT}")"
    description: "$(esc "${DESC}")"
    trigger_words: ${TRIG_LIST}
    work_path: "$(esc "${WPATH}")"
    branch: "$(esc "${BRANCH}")"
    services: ${SVC_LIST}
    status: "initialized"
    created_at: "${CREATED_AT}"
EOF

    tmp_new="$(new_tmp)"
    # 若 work 还是空列表，替换为 work: + 首条；否则插入到区块末尾
    if grep -qE '^work:[[:space:]]*\[\][[:space:]]*(#.*)?$' "${tmp_body}"; then
        awk -v entryfile="${tmp_entry}" '
            /^work:[[:space:]]*\[\][[:space:]]*(#.*)?$/ {
                print "work:"
                while ((getline l < entryfile) > 0) print l
                next
            }
            { print }
        ' "${tmp_body}" > "${tmp_new}"
    else
        awk -v entryfile="${tmp_entry}" -v e="${END_MARK}" '
            { print }
            END { while ((getline l < entryfile) > 0) print l }
        ' "${tmp_body}" > "${tmp_new}"
    fi

    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_entry}" "${tmp_new}"
    echo "已登记工作: ${ID}（项目: ${PROJECT}）"
}

# work-set: 更新某工作条目状态
cmd_work_set() {
    ID="$3"; STATUS="$4"
    [ -n "${ID}" ] && [ -n "${STATUS}" ] || { echo "Usage: project.sh work-set <root> <id> <status>" >&2; exit 1; }
    resolve_store

    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"
    tmp_new="$(new_tmp)"
    awk -v want="$(esc "${ID}")" -v st="$(esc "${STATUS}")" "${YAML_LIB}"'
        BEGIN { inwork=0; cur=""; updated=0 }
        /^work:/ { inwork=1; print; next }
        inwork==1 && /^[^[:space:]]/ { inwork=0 }
        inwork==1 && $0 ~ /^[[:space:]]*-[[:space:]]*work_id:/ {
            cur=val($0)
            print; next
        }
        inwork==1 && cur==want && $0 ~ /^[[:space:]]+status:/ {
            print "    status: \"" st "\""
            updated=1
            next
        }
        { print }
        END { if (updated==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未找到 work_id '${ID}' 的条目" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已更新工作状态: ${ID} -> ${STATUS}"
}

# work-remove: 移除某工作条目（close 删除工作区目录后同步清理空间登记）
cmd_work_remove() {
    ID="$3"
    [ -n "${ID}" ] || { echo "Usage: project.sh work-remove <root> <id>" >&2; exit 1; }
    resolve_store

    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"
    tmp_new="$(new_tmp)"
    awk -v want="$(esc "${ID}")" "${YAML_LIB}"'
        BEGIN { inwork=0; cur=""; skip=0; removed=0 }
        /^work:/ { inwork=1; print; next }
        inwork==1 && /^[^[:space:]]/ { inwork=0; skip=0 }
        inwork==1 && $0 ~ /^[[:space:]]*-[[:space:]]*work_id:/ {
            cur=val($0)
            if (cur==want) { skip=1; removed=1; next }
            skip=0
        }
        inwork==1 && skip==1 { next }
        { print }
        END { if (removed==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未找到 work_id '${ID}' 的条目" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    # work 区块删空后回写为 work: []，避免无效 YAML
    if ! grep -qE '^[[:space:]]*-[[:space:]]*work_id:' "${tmp_new}"; then
        awk '/^work:/ { print "work: []"; next } { print }' "${tmp_new}" > "${tmp_new}.2" && mv "${tmp_new}.2" "${tmp_new}"
    fi
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已移除工作条目: ${ID}"
}

# work-path: 修正某工作条目的 work_path（reconcile 发现重命名中断残留时校准）
cmd_work_path() {
    ID="$3"; WPATH="$4"
    [ -n "${ID}" ] && [ -n "${WPATH}" ] || { echo "Usage: project.sh work-path <root> <id> <work_path>" >&2; exit 1; }
    resolve_store

    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"
    tmp_new="$(new_tmp)"
    awk -v want="$(esc "${ID}")" -v wp="$(esc "${WPATH}")" "${YAML_LIB}"'
        BEGIN { inwork=0; cur=""; updated=0 }
        /^work:/ { inwork=1; print; next }
        inwork==1 && /^[^[:space:]]/ { inwork=0 }
        inwork==1 && $0 ~ /^[[:space:]]*-[[:space:]]*work_id:/ {
            cur=val($0)
            print; next
        }
        inwork==1 && cur==want && $0 ~ /^[[:space:]]+work_path:/ {
            print "    work_path: \"" wp "\""
            updated=1
            next
        }
        { print }
        END { if (updated==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未找到 work_id '${ID}' 的条目" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已修正工作路径: ${ID} -> ${WPATH}"
}

# work-rename: 重命名某工作条目的 work_id / branch / work_path（work.sh rename 调用）
cmd_work_rename() {
    ID="$3"; NEWID="$4"; NEWBR="$5"; NEWPATH="$6"
    [ -n "${ID}" ] && [ -n "${NEWID}" ] && [ -n "${NEWBR}" ] && [ -n "${NEWPATH}" ] || {
        echo "Usage: project.sh work-rename <root> <old-id> <new-id> <new-branch> <new-work-path>" >&2
        exit 1
    }
    resolve_store

    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"

    # 新 work_id 已被其他条目占用时拒绝
    if [ "${ID}" != "${NEWID}" ] && awk -v id="$(esc "${NEWID}")" "${YAML_LIB}"'
        /^[[:space:]]*-[[:space:]]*work_id:/ {
            if (val($0) == id) found=1
        }
        END { exit (found?0:1) }
    ' "${tmp_body}"; then
        echo "Error: work_id '${NEWID}' 已存在" >&2
        rm -f "${tmp_body}"; exit 1
    fi

    tmp_new="$(new_tmp)"
    awk -v want="$(esc "${ID}")" -v nid="$(esc "${NEWID}")" \
        -v nbr="$(esc "${NEWBR}")" -v nwp="$(esc "${NEWPATH}")" "${YAML_LIB}"'
        BEGIN { inwork=0; cur=""; found=0 }
        /^work:/ { inwork=1; print; next }
        inwork==1 && /^[^[:space:]]/ { inwork=0 }
        inwork==1 && $0 ~ /^[[:space:]]*-[[:space:]]*work_id:/ {
            cur=val($0)
            if (cur==want) { print "  - work_id: \"" nid "\""; found=1; cur=want; next }
            print; next
        }
        inwork==1 && cur==want && $0 ~ /^[[:space:]]+branch:/ {
            print "    branch: \"" nbr "\""; next
        }
        inwork==1 && cur==want && $0 ~ /^[[:space:]]+work_path:/ {
            print "    work_path: \"" nwp "\""; next
        }
        { print }
        END { if (!found) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未找到 work_id '${ID}' 的条目" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 3
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已重命名工作条目: ${ID} -> ${NEWID}（branch: ${NEWBR}）"
}

# 从单个 status.yaml 提取概要行：work_id<TAB>project<TAB>branch<TAB>status<TAB>svc1,svc2
# 文件不存在或字段缺失以 - 占位
status_summary() {
    f="$1"
    if [ ! -f "${f}" ]; then
        printf -- '-\t-\t-\t-\t-\n'
        return
    fi
    awk "${YAML_LIB}"'
        BEGIN { id="-"; prj="-"; br="-"; st="-"; svc=""; insvc=0 }
        /^[A-Za-z_]/ { insvc=0 }
        /^work_id:/ { id=val($0) }
        /^project:/ { prj=val($0) }
        /^branch:/  { br=val($0) }
        /^status:/  { st=val($0) }
        /^services:[[:space:]]*$/ { insvc=1; next }
        /^services:/ {
            svc=norm_csv(val($0))
            next
        }
        insvc==1 && /^[[:space:]]+-[[:space:]]/ {
            v=$0; sub(/^[[:space:]]+-[[:space:]]*/,"",v)
            v=clean(v)
            if (v!="") svc=(svc==""?v:svc","v)
        }
        END { printf "%s\t%s\t%s\t%s\t%s\n", id, prj, br, st, svc }
    ' "${f}"
}

# work-reconcile: 对账空间登记的 work 条目与 space/ 实际目录，只报告差异不改写
# 输出（TAB 分隔；无差异时仅 SUMMARY 行；退出码恒 0）：
#   MISSING_DIR    <id> <登记目录名>        <status>                 条目在、目录缺失
#   STALE_COMPLETED <id> <目录名>            <status>                 条目已 completed 但目录仍在（旧归档残留）
#   PATH_MISMATCH  <id> <登记目录名>         <实际目录名>              work_path 与 status.yaml work_id 指向不符（重命名中断）
#   UNREGISTERED   <目录名> <work_id|-> <project|-> <branch|-> <status|-> <svc,svc|->   目录在、无条目
cmd_work_reconcile() {
    resolve_store

    tmp_body="$(new_tmp)"
    tmp_entries="$(new_tmp)"
    tmp_seen="$(new_tmp)"
    extract_body "${tmp_body}"
    : > "${tmp_seen}"

    # 提取条目：id<TAB>work_path 末段<TAB>status
    awk "${YAML_LIB}"'
        function flush() { if (cur!="") print cur "\t" wp "\t" st; cur=""; wp=""; st="" }
        BEGIN { inwork=0; cur=""; wp=""; st="" }
        /^work:/ { inwork=1; next }
        inwork==1 && /^[^[:space:]]/ { flush(); inwork=0 }
        inwork==1 && $0 ~ /^[[:space:]]*-[[:space:]]*work_id:/ {
            flush()
            cur=val($0)
            next
        }
        inwork==1 && cur!="" && $0 ~ /^[[:space:]]+work_path:/ {
            line=val($0)
            gsub(/\\/,"/",line)
            n=split(line, parts, "/"); wp=parts[n]
            next
        }
        inwork==1 && cur!="" && $0 ~ /^[[:space:]]+status:/ {
            st=val($0)
        }
        END { flush() }
    ' "${tmp_body}" > "${tmp_entries}"

    issues=0
    matched=0

    # 逐条核对磁盘
    while IFS="$(printf '\t')" read -r id dirname status; do
        [ -n "${id}" ] || continue
        if [ -d "${ROOT}/space/${dirname}" ]; then
            matched=$((matched+1))
            printf '%s\n' "${dirname}" >> "${tmp_seen}"
            if [ "${status}" = "completed" ]; then
                printf 'STALE_COMPLETED\t%s\t%s\t%s\n' "${id}" "${dirname}" "${status}"
                issues=$((issues+1))
            fi
            continue
        fi
        # 登记目录缺失：在其余工作区的 status.yaml 中按 work_id 找实际目录
        actual=""
        if [ -d "${ROOT}/space" ]; then
            for sf in "${ROOT}/space"/*/status.yaml; do
                [ -f "${sf}" ] || continue
                sid=$(awk "${YAML_LIB}"'/^work_id:/ { print val($0); exit }' "${sf}")
                if [ "${sid}" = "${id}" ]; then
                    actual=$(basename "$(dirname "${sf}")")
                    break
                fi
            done
        fi
        if [ -n "${actual}" ]; then
            printf 'PATH_MISMATCH\t%s\t%s\t%s\n' "${id}" "${dirname}" "${actual}"
            # 实际目录已由本条 PATH_MISMATCH 覆盖，不再计为 UNREGISTERED
            printf '%s\n' "${actual}" >> "${tmp_seen}"
        else
            printf 'MISSING_DIR\t%s\t%s\t%s\n' "${id}" "${dirname}" "${status}"
        fi
        issues=$((issues+1))
    done < "${tmp_entries}"

    # 逐目录核对登记（UNREGISTERED）
    if [ -d "${ROOT}/space" ]; then
        for d in "${ROOT}/space"/*/; do
            [ -d "${d}" ] || continue
            dn=$(basename "${d}")
            if grep -qxF "${dn}" "${tmp_seen}"; then
                continue
            fi
            summary=$(status_summary "${d}status.yaml")
            printf 'UNREGISTERED\t%s\t%s\n' "${dn}" "${summary}"
            issues=$((issues+1))
        done
    fi

    printf 'SUMMARY\tmatched=%s\tissues=%s\n' "${matched}" "${issues}"
    rm -f "${tmp_body}" "${tmp_entries}" "${tmp_seen}"
}

# project-keywords: 覆盖写指定项目的 keywords（逗号分隔；空值写空序列）
cmd_project_keywords() {
    NAME="$3"; KW="$4"
    [ -n "${NAME}" ] && [ -n "${KW}" ] || { echo "Usage: project.sh project-keywords <root> <name> <kw1,kw2,...>" >&2; exit 1; }
    resolve_store
    require_projects
    project_exists "${NAME}" || { echo "Error: 项目 '${NAME}' 不存在" >&2; exit 1; }

    KW_LIST=$(csv_to_yaml "${KW}")
    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"
    tmp_new="$(new_tmp)"
    awk -v want="$(esc "${NAME}")" -v list="${KW_LIST}" "${YAML_LIB}"'
        BEGIN { inproj=0; cur=""; inkw=0; done=0 }
        /^projects:/ { inproj=1; print; next }
        inproj==1 && /^[^[:space:]]/ { inproj=0; inkw=0; cur="" }
        inproj==1 && /^  - name:/ {
            cur=val($0); inkw=0
            print; next
        }
        inproj==1 && cur==want && done==0 && /^    keywords:/ {
            print "    keywords: " list
            inkw=1; done=1; next
        }
        inproj==1 && inkw==1 && /^      - / { next }
        inproj==1 && inkw==1 && /^    [A-Za-z_]/ { inkw=0 }
        { print }
        END { if (done==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未在项目 '${NAME}' 中找到 keywords 字段" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已更新 projects[${NAME}].keywords"
}

# project-service-repo: 追加一条指定项目的 service_repo_mapping（空 [] 替换为块，非空在块尾追加）
cmd_project_service_repo() {
    NAME="$3"; SVC="$4"; RN="$5"; RG="$6"; RP="$7"
    if [ -z "${NAME}" ] || [ -z "${SVC}" ] || [ -z "${RN}" ] || [ -z "${RP}" ]; then
        echo "Usage: project.sh project-service-repo <root> <name> <service_name> <repo_name> <repo_git> <repo_path>" >&2
        exit 1
    fi
    resolve_store
    require_projects
    project_exists "${NAME}" || { echo "Error: 项目 '${NAME}' 不存在" >&2; exit 1; }

    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"
    tmp_new="$(new_tmp)"
    awk -v want="$(esc "${NAME}")" -v svc="$(esc "${SVC}")" -v rn="$(esc "${RN}")" -v rg="$(esc "${RG}")" -v rp="$(esc "${RP}")" "${YAML_LIB}"'
        function emit() {
            print "      - service_name: \"" svc "\""
            print "        repo_name: \"" rn "\""
            print "        repo_git: \"" rg "\""
            print "        repo_path: \"" rp "\""
        }
        BEGIN { inproj=0; cur=""; inmap=0; done=0 }
        /^projects:/ { inproj=1; print; next }
        inproj==1 && /^[^[:space:]]/ {
            if (inmap==1 && cur==want && done==0) { emit(); done=1 }
            inproj=0; inmap=0; cur=""
            print; next
        }
        inproj==1 && /^  - name:/ {
            if (inmap==1 && cur==want && done==0) { emit(); done=1 }
            cur=val($0); inmap=0
            print; next
        }
        inproj==1 && cur==want && $0 ~ /^    service_repo_mapping:[[:space:]]*\[\][[:space:]]*(#.*)?$/ {
            print "    service_repo_mapping:"
            emit(); done=1
            next
        }
        inproj==1 && cur==want && $0 ~ /^    service_repo_mapping:[[:space:]]*($|#)/ {
            inmap=1; print; next
        }
        inproj==1 && inmap==1 && $0 ~ /^    [A-Za-z_]/ {
            emit(); done=1; inmap=0
            print; next
        }
        { print }
        END {
            if (inmap==1 && cur==want && done==0) { emit(); done=1 }
            if (done==0) exit 3
        }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未在项目 '${NAME}' 中找到 service_repo_mapping 字段" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已登记项目服务映射: ${NAME} ${SVC} -> ${RN}"
}

# work-services: 覆盖写某 work 条目的 services；给 status.yaml 时同步其顶层 services
cmd_work_services() {
    ID="$3"; SVC="$4"; SYNC="$5"
    [ -n "${ID}" ] && [ -n "${SVC}" ] || { echo "Usage: project.sh work-services <root> <id> <svc1,svc2,...> [status.yaml]" >&2; exit 1; }
    if [ -n "${SYNC}" ] && [ "${SYNC}" != "--no-commit" ] && [ ! -f "${SYNC}" ]; then
        echo "Error: status.yaml 不存在: ${SYNC}" >&2; exit 1
    fi
    resolve_store

    SVC_LIST=$(csv_to_yaml "${SVC}")
    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"
    tmp_new="$(new_tmp)"
    awk -v want="$(esc "${ID}")" -v list="${SVC_LIST}" "${YAML_LIB}"'
        BEGIN { inwork=0; cur=""; updated=0 }
        /^work:/ { inwork=1; print; next }
        inwork==1 && /^[^[:space:]]/ { inwork=0 }
        inwork==1 && $0 ~ /^[[:space:]]*-[[:space:]]*work_id:/ {
            cur=val($0)
            print; next
        }
        inwork==1 && cur==want && $0 ~ /^[[:space:]]+services:/ {
            print "    services: " list
            updated=1
            next
        }
        { print }
        END { if (updated==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未找到 work_id '${ID}' 的条目" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"

    if [ -n "${SYNC}" ] && [ "${SYNC}" != "--no-commit" ]; then
        tmp_s="${SYNC}.$$"
        awk -v list="${SVC_LIST}" "${YAML_LIB}"'
            /^services:[[:space:]]*/ { print "services: " list; done=1; next }
            { print }
            END { if (done==0) exit 3 }
        ' "${SYNC}" > "${tmp_s}" || {
            echo "Error: ${SYNC} 缺少顶层 services 字段" >&2
            rm -f "${tmp_s}"; exit 1
        }
        mv "${tmp_s}" "${SYNC}"
        # 同步写入的 status.yaml 一并纳入本次提交清单
        EXTRA_COMMIT="${SYNC}"
        echo "已同步 ${SYNC} 的 services"
    fi
    echo "已更新工作服务列表: ${ID}"
}

# work-trigger: 追加触发词到指定 work 条目（去重，跳过等于 work_id/branch 的词）
cmd_work_trigger() {
    ID="$3"; KWS="$4"
    # --no-commit 落在第 4 位（未传 kws 时），视为缺少 kws 参数
    [ "${KWS}" = "--no-commit" ] && KWS=""
    [ -n "${ID}" ] && [ -n "${KWS}" ] || { echo "Usage: project.sh work-trigger <root> <id> <kw1,kw2,...>" >&2; exit 1; }
    resolve_store

    tmp_body="$(new_tmp)"
    extract_body "${tmp_body}"

    # 提取目标条目的现有 trigger_words 与 branch（awk 逐行跟踪当前 work_id；
    # 不用 sed 地址——work_id 含 / 时会截断正则表达式并让脚本中止）
    EXISTING=$(awk -v id="$(esc "${ID}")" "${YAML_LIB}"'
        /^[[:space:]]*-[[:space:]]*work_id:/ { cur = val($0); next }
        cur == id && /^[[:space:]]*trigger_words[[:space:]]*:/ { print yaml_csv(val($0)); exit }
    ' "${tmp_body}")
    BR=$(awk -v id="$(esc "${ID}")" "${YAML_LIB}"'
        /^[[:space:]]*-[[:space:]]*work_id:/ { cur = val($0); next }
        cur == id && /^[[:space:]]*branch[[:space:]]*:/ { print val($0); exit }
    ' "${tmp_body}")

    # 验证 work_id 存在（EXISTING 和 BR 同时为空且无匹配 → 报错）
    if [ -z "${BR}" ]; then
        # 再确认一次条目是否存在（可能条目无 branch 字段，极少情况）
        if ! awk -v id="$(esc "${ID}")" "${YAML_LIB}"'
            /^[[:space:]]*-[[:space:]]*work_id:/ {
                if (val($0) == id) found=1
            }
            END { exit (found?0:1) }
        ' "${tmp_body}"; then
            echo "Error: 未找到 work_id '${ID}' 的条目" >&2
            rm -f "${tmp_body}"; exit 1
        fi
    fi

    # 合并现有词与新词，去重，跳过 work_id 与 branch
    ALL="${EXISTING},${KWS}"
    MERGED=$(printf '%s' "${ALL}" | awk -F',' -v id="$(esc "${ID}")" -v br="${BR}" '
    {
        for (i=1;i<=NF;i++) {
            w=$i; gsub(/^[[:space:]]+|[[:space:]]+$/,"",w)
            if (w=="" || w==id || w==br) continue
            if (!(w in seen)) { seen[w]=1; if (first) printf ","; printf "%s", w; first=1 }
        }
    }')

    MERGED_LIST=$(csv_to_yaml "${MERGED}")
    tmp_new="$(new_tmp)"
    awk -v want="$(esc "${ID}")" -v list="${MERGED_LIST}" "${YAML_LIB}"'
        BEGIN { inwork=0; cur=""; inserted=0 }
        /^work:/ { inwork=1; print; next }
        inwork==1 && /^[^[:space:]]/ { inwork=0 }
        inwork==1 && $0 ~ /^[[:space:]]*-[[:space:]]*work_id:/ {
            cur=val($0)
            print; next
        }
        inwork==1 && cur==want && $0 ~ /^[[:space:]]+description:/ {
            print
            if (inserted==0) { print "    trigger_words: " list; inserted=1 }
            next
        }
        inwork==1 && cur==want && $0 ~ /^[[:space:]]+trigger_words:/ {
            if (inserted==0) { print "    trigger_words: " list; inserted=1 }
            next
        }
        { print }
        END { if (inserted==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未找到 work_id '${ID}' 的条目" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已更新工作触发词: ${ID}"
}

# 写登记的动作先加空间级锁，后续 resolve_store/extract_body 均在锁内重新读取最新内容；
# 覆盖新增（ensure/project-add/work-add）、更新、删除（work-remove）、迁移与回滚（migrate）
case "${ACTION}" in
    ensure|migrate|project-add|project-set|project-keywords|project-service-repo|skill-version|work-add|work-set|work-remove|work-path|work-rename|work-services|work-trigger)
        tack_space_lock_acquire "${ROOT}"
        ;;
esac

case "${ACTION}" in
    ensure)                cmd_ensure ;;
    migrate)               cmd_migrate ;;
    store-path)            NO_COMMIT=1; cmd_store_path ;;
    space-info)            NO_COMMIT=1; cmd_space_info ;;
    project-add)           cmd_project_add "$@" ;;
    project-set)           cmd_project_set "$@" ;;
    project-keywords)      cmd_project_keywords "$@" ;;
    project-service-repo)  cmd_project_service_repo "$@" ;;
    project-list)          NO_COMMIT=1; cmd_project_list "$@" ;;
    project-get)           NO_COMMIT=1; cmd_project_get "$@" ;;
    repo-list)             NO_COMMIT=1; cmd_repo_list "$@" ;;
    skill-version)         cmd_skill_version "$@" ;;
    work-add)              cmd_work_add "$@" ;;
    work-set)              cmd_work_set "$@" ;;
    work-remove)           cmd_work_remove "$@" ;;
    work-path)             cmd_work_path "$@" ;;
    work-rename)           cmd_work_rename "$@" ;;
    work-reconcile)        NO_COMMIT=1; cmd_work_reconcile "$@" ;;
    work-list)             NO_COMMIT=1; cmd_work_list "$@" ;;
    work-get)              NO_COMMIT=1; cmd_work_get "$@" ;;
    work-services)         cmd_work_services "$@" ;;
    work-trigger)          cmd_work_trigger "$@" ;;
    *) echo "Error: 未知动作 '${ACTION}'（支持 ensure / migrate / store-path / space-info / project-add / project-set / project-keywords / project-service-repo / project-list / project-get / repo-list / skill-version / work-add / work-set / work-remove / work-path / work-rename / work-reconcile / work-list / work-get / work-services / work-trigger）" >&2; exit 1 ;;
esac

# 空间登记（tack.yaml 或旧区块）变更后，在同一空间锁内精确提交本次写过的登记文件
# （space.sh 内部跳过无变更；--no-commit 时交由复合流程（init-tack、update）统一收尾提交）
if [ "${NO_COMMIT}" -ne 1 ]; then
    case "${ACTION}" in
        ensure)
            sh "${SCRIPT_DIR}/space.sh" commit "${ROOT}" "chore(tack): project ${ACTION}" "${STORE_FILE}" ;;
        migrate)
            sh "${SCRIPT_DIR}/space.sh" commit "${ROOT}" "chore(tack): project ${ACTION}" "${STORE_FILE}" "${AGENTS}" ;;
        *)
            if [ -n "${EXTRA_COMMIT}" ]; then
                sh "${SCRIPT_DIR}/space.sh" commit "${ROOT}" "chore(tack): project ${ACTION}" "${STORE}" "${EXTRA_COMMIT}"
            else
                sh "${SCRIPT_DIR}/space.sh" commit "${ROOT}" "chore(tack): project ${ACTION}" "${STORE}"
            fi ;;
    esac
fi
