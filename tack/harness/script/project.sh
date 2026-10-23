#!/bin/sh
# project.sh — 维护 AGENTS.md 中的「项目信息」YAML 区块（projects 数组 + work 列表）
#
# 区块边界（区块体内为纯 YAML，不含 markdown 围栏，便于脚本可靠读写）：
#   <!-- tack:info:start -->
#   skill_version: ""
#   skill_update_url: "https://github.com/frcoder-lh/tack-harness"
#   ...
#   projects:
#     - name: "project-a"
#       keywords: [...]
#       description: ""
#       root_path: ""
#       repo_scan_path: []
#       service_repo_mapping: [...]
#   work:
#     - work_id: "..."
#       project: "project-a"
#       ...
#   <!-- tack:info:end -->
#
# Usage:
#   sh project.sh ensure            <root>                                              # 区块缺失时在 AGENTS.md 尾部追加空模板（幂等）
#   sh project.sh project-add       <root> <name> [description] [--no-commit]           # 追加项目条目并创建 wiki/<name>/
#   sh project.sh project-set       <root> <name> <description|root_path> <value>       # 更新项目下简单标量
#   sh project.sh project-keywords  <root> <name> <kw1,kw2,...> [--no-commit]           # 覆盖写某项目 keywords
#   sh project.sh project-service-repo <root> <name> <service_name> <repo_name> <repo_git> <repo_path> [--no-commit]
#                                                                                       # 追加某项目的 service_repo_mapping（repo_git 可传空串）
#   sh project.sh project-list      <root>                                              # 输出 name<TAB>description，每行一个项目
#   sh project.sh skill-version     <root> <version> [--if-empty] [--no-commit]         # 写入 skill_version；--if-empty 仅空值时填充（已有值跳过）
#   sh project.sh work-add      <root> <project> <id> <description> <work_path> <branch> <svc1,svc2> [triggers]
#   sh project.sh work-set      <root> <id> <status>                                # 更新某工作条目状态
#   sh project.sh work-remove   <root> <id>                                         # 移除某工作条目（close 时工作区目录删除后同步清理登记）
#   sh project.sh work-path     <root> <id> <work_path>                             # 修正某工作条目的 work_path（reconcile 发现重命名残留时校准）
#   sh project.sh work-rename   <root> <old-id> <new-id> <new-branch> <new-work_path> # 重命名工作条目的 work_id/branch/work_path
#   sh project.sh work-reconcile <root>                                             # 对账 work 条目与 space/ 实际目录，只报告差异不改写
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

START_MARK='<!-- tack:info:start -->'
END_MARK='<!-- tack:info:end -->'

# 共享 YAML 标量/行内列表函数（唯一事实源 script/yamlib.awk）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YAML_LIB="$(cat "${SCRIPT_DIR}/yamlib.awk")"

if [ -z "${ACTION}" ] || [ -z "${ROOT}" ]; then
    echo "Usage: sh project.sh <ensure|project-add|project-set|project-keywords|project-service-repo|project-list|skill-version|work-add|work-set|work-remove|work-path|work-rename|work-reconcile|work-services|work-trigger> <root> [args...]" >&2
    exit 1
fi
if [ ! -f "${AGENTS}" ]; then
    echo "Error: ${AGENTS} 不存在，请先执行 init-tack.sh 初始化 tack 空间" >&2
    exit 1
fi

# 临时文件统一落空间运行时目录 .tack/tmp（.gitignore 已排除）：脚本内任意步骤
# 失败或中断都不会把半成品留在 AGENTS.md 同目录，被空间仓库自动提交带走
mkdir -p "${ROOT}/.tack/tmp"
TMP_DIR="$(mktemp -d "${ROOT}/.tack/tmp/project.XXXXXX")"
cleanup_tmp() { rm -rf "${TMP_DIR}"; }
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

# 提取区块体（两个标记之间的内容）到指定临时文件
extract_body() {
    out="$1"
    awk -v s="${START_MARK}" -v e="${END_MARK}" '
        index($0, s) == 1 { inblock=1; next }
        index($0, e) == 1 { inblock=0; next }
        inblock == 1 { print }
    ' "${AGENTS}" > "${out}"
}

# 用临时文件中的新 body 重写区块（区块外内容、标记行本身保持不变）
rewrite_block() {
    body="$1"
    tmp="$(new_tmp)"
    awk -v bodyfile="${body}" -v s="${START_MARK}" -v e="${END_MARK}" '
        index($0, s) == 1 { print; while ((getline line < bodyfile) > 0) print line; inblock=1; next }
        index($0, e) == 1 { inblock=0; print; next }
        inblock != 1 { print }
    ' "${AGENTS}" > "${tmp}" && mv "${tmp}" "${AGENTS}"
}

has_block() {
    grep -qF "${START_MARK}" "${AGENTS}" && grep -qF "${END_MARK}" "${AGENTS}"
}

# require_projects — 校验多项目结构（projects 数组）存在；旧版单项目区块给出迁移提示
require_projects() {
    grep -qE '^projects:' "${AGENTS}" && return 0
    if grep -qE '^project:' "${AGENTS}"; then
        echo "Error: 检测到旧版单项目区块 project:。多项目结构须为 projects 数组，且每个 work 条目带 project 字段；请按 AGENTS.md 模板手工迁移该区块后再执行" >&2
    else
        echo "Error: 项目信息区块缺少 projects 字段，先执行 project.sh ensure" >&2
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
    ' "${AGENTS}"
}

# ensure: 幂等追加空区块
cmd_ensure() {
    if has_block; then
        if grep -qE '^projects:' "${AGENTS}"; then
            echo "项目信息区块已存在，跳过"
            return 0
        fi
        require_projects
    fi
    tmp_body="$(new_tmp)"
    cat > "${tmp_body}" <<'EOF'
skill_version: ""
skill_update_url: "https://github.com/frcoder-lh/tack-harness"
skill_trigger: "tack"
projects: []
work: []
EOF
    # 确保文件尾有空行，再追加区块
    [ -z "$(tail -c1 "${AGENTS}" 2>/dev/null)" ] || echo "" >> "${AGENTS}"
    {
        echo "## 项目信息"
        echo ""
        echo "> 以下 YAML 区块由 harness/script/project.sh 维护（init、work、close 时自动更新）；可手工查阅，结构化内容（projects、service_repo_mapping、work.services）由 init 等命令经脚本写入（内容经人工确认）。项目名与 work.project 对应，项目级知识落 wiki/<project>/。"
        echo ""
        echo "${START_MARK}"
        cat "${tmp_body}"
        echo "${END_MARK}"
    } >> "${AGENTS}"
    rm -f "${tmp_body}"
    echo "已在 AGENTS.md 追加项目信息区块"
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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }
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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }
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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }
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
    ' "${AGENTS}"
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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

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
        echo "Error: 项目信息区块中缺少 skill_version 字段" >&2
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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }
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
        echo "Error: work_id '${ID}' 已存在于项目信息区块" >&2
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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

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

# work-remove: 移除某工作条目（close 删除工作区目录后同步清理 AGENTS.md 登记）
cmd_work_remove() {
    ID="$3"
    [ -n "${ID}" ] || { echo "Usage: project.sh work-remove <root> <id>" >&2; exit 1; }
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

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

# work-reconcile: 对账 AGENTS.md work 条目与 space/ 实际目录，只报告差异不改写
# 输出（TAB 分隔；无差异时仅 SUMMARY 行；退出码恒 0）：
#   MISSING_DIR    <id> <登记目录名>        <status>                 条目在、目录缺失
#   STALE_COMPLETED <id> <目录名>            <status>                 条目已 completed 但目录仍在（旧归档残留）
#   PATH_MISMATCH  <id> <登记目录名>         <实际目录名>              work_path 与 status.yaml work_id 指向不符（重命名中断）
#   UNREGISTERED   <目录名> <work_id|-> <project|-> <branch|-> <status|-> <svc,svc|->   目录在、无条目
cmd_work_reconcile() {
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }
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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }
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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

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
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

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

case "${ACTION}" in
    ensure)                cmd_ensure ;;
    project-add)           cmd_project_add "$@" ;;
    project-set)           cmd_project_set "$@" ;;
    project-keywords)      cmd_project_keywords "$@" ;;
    project-service-repo)  cmd_project_service_repo "$@" ;;
    project-list)          NO_COMMIT=1; cmd_project_list "$@" ;;
    skill-version)         cmd_skill_version "$@" ;;
    work-add)              cmd_work_add "$@" ;;
    work-set)              cmd_work_set "$@" ;;
    work-remove)           cmd_work_remove "$@" ;;
    work-path)             cmd_work_path "$@" ;;
    work-rename)           cmd_work_rename "$@" ;;
    work-reconcile)        NO_COMMIT=1; cmd_work_reconcile "$@" ;;
    work-services)         cmd_work_services "$@" ;;
    work-trigger)          cmd_work_trigger "$@" ;;
    *) echo "Error: 未知动作 '${ACTION}'（支持 ensure / project-add / project-set / project-keywords / project-service-repo / project-list / skill-version / work-add / work-set / work-remove / work-path / work-rename / work-reconcile / work-services / work-trigger）" >&2; exit 1 ;;
esac

# AGENTS.md 项目信息区块变更后，框架自动提交空间仓库（无变更时 space.sh 内部跳过）；
# --no-commit 时交由复合流程（init-tack、update）统一收尾提交
if [ "${NO_COMMIT}" -ne 1 ]; then
    sh "${SCRIPT_DIR}/space.sh" commit "${ROOT}" "chore(tack): project ${ACTION}"
fi
