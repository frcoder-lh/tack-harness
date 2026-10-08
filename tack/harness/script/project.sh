#!/bin/sh
# project.sh — 维护 AGENTS.md 中的「项目信息」YAML 区块（取代根 status.yaml）
#
# 区块边界（区块体内为纯 YAML，不含 markdown 围栏，便于脚本可靠读写）：
#   <!-- tack:info:start -->
#   skill_version: ""
#   skill_update_url: "https://github.com/frcoder-lh/tack-harness"
#   ...
#   work: []
#   <!-- tack:info:end -->
#
# Usage:
#   sh project.sh ensure        <root>                                              # 区块缺失时在 AGENTS.md 尾部追加空模板（幂等）
#   sh project.sh set           <root> <name|description|root_path> <value>         # 更新 project 下简单标量
#   sh project.sh skill-version <root> <version> [--if-empty] [--no-commit]         # 写入 skill_version；--if-empty 仅空值时填充（已有值跳过）
#   sh project.sh keywords      <root> <kw1,kw2,...> [--no-commit]                  # 覆盖写 project.keywords 列表
#   sh project.sh service-repo  <root> <service_name> <repo_name> <repo_git> <repo_path> [--no-commit]
#                                                                                   # 追加一条 project.service_repo_mapping（repo_git 可传空串）
#   sh project.sh work-add      <root> <id> <description> <work_path> <branch> <svc1,svc2> [triggers]
#   sh project.sh work-set      <root> <id> <status>                                # 更新某工作条目状态
#   sh project.sh work-services <root> <id> <svc1,svc2,...> [status.yaml] [--no-commit]
#                                                                                   # 覆盖写某工作条目 services；给 status.yaml 时同步其顶层 services
#   sh project.sh work-trigger  <root> <id> <kw1,kw2,...> [--no-commit]            # 追加触发词到 work 条目（去重、跳过等于 work_id/branch 的词）
#
# --no-commit: 跳过尾部空间仓库自动提交，供 init-tack / update 等复合流程统一收尾提交
#
# 退出码: 0 成功 / 非 0 失败（AGENTS.md 不存在、work_id 重复或找不到等）

set -e

ACTION="$1"
ROOT="$2"
AGENTS="${ROOT}/AGENTS.md"

START_MARK='<!-- tack:info:start -->'
END_MARK='<!-- tack:info:end -->'

if [ -z "${ACTION}" ] || [ -z "${ROOT}" ]; then
    echo "Usage: sh project.sh <ensure|set|skill-version|keywords|service-repo|work-add|work-set|work-services|work-trigger> <root> [args...]" >&2
    exit 1
fi
if [ ! -f "${AGENTS}" ]; then
    echo "Error: ${AGENTS} 不存在，请先执行 init-tack.sh 初始化 tack 空间" >&2
    exit 1
fi

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

# 逗号分隔列表 -> YAML 行内序列内容：a,b → "a", "b"（去空白、去空项）
csv_to_yaml() {
    printf '%s' "$1" | awk -F',' '
        { for (i=1;i<=NF;i++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/,"",$i)
            if ($i!="") printf "%s\"%s\"", (n++?", ":""), $i
        } }'
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
    tmp="${AGENTS}.tmp"
    awk -v bodyfile="${body}" -v s="${START_MARK}" -v e="${END_MARK}" '
        index($0, s) == 1 { print; while ((getline line < bodyfile) > 0) print line; inblock=1; next }
        index($0, e) == 1 { inblock=0; print; next }
        inblock != 1 { print }
    ' "${AGENTS}" > "${tmp}" && mv "${tmp}" "${AGENTS}"
}

has_block() {
    grep -qF "${START_MARK}" "${AGENTS}" && grep -qF "${END_MARK}" "${AGENTS}"
}

# ensure: 幂等追加空区块
cmd_ensure() {
    if has_block; then
        echo "项目信息区块已存在，跳过"
        return 0
    fi
    tmp_body="${AGENTS}.body.$$"
    cat > "${tmp_body}" <<'EOF'
skill_version: ""
skill_update_url: "https://github.com/frcoder-lh/tack-harness"
skill_trigger: "tack"
project:
  name: ""
  keywords:
    - ""
  description: ""
  root_path: ""
  repo_scan_path: []
  service_repo_mapping: []
work: []
EOF
    # 确保文件尾有空行，再追加区块
    [ -z "$(tail -c1 "${AGENTS}" 2>/dev/null)" ] || echo "" >> "${AGENTS}"
    {
        echo "## 项目信息"
        echo ""
        echo "> 以下 YAML 区块由 harness/script/project.sh 维护（init、work、close 时自动更新）；可手工查阅，结构化内容（keywords、service_repo_mapping、work.services）由 init 等命令经脚本写入（内容经人工确认）。"
        echo ""
        echo "${START_MARK}"
        cat "${tmp_body}"
        echo "${END_MARK}"
    } >> "${AGENTS}"
    rm -f "${tmp_body}"
    echo "已在 AGENTS.md 追加项目信息区块"
}

# set: 更新 project 下的简单标量
cmd_set() {
    FIELD="$3"
    VALUE="$4"
    case "${FIELD}" in
        name|description|root_path) ;;
        *) echo "Error: set 仅支持 name/description/root_path（列表字段用 keywords / service-repo / work-services 子命令）" >&2; exit 1 ;;
    esac
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

    tmp_body="${AGENTS}.body.$$"
    extract_body "${tmp_body}"
    tmp_new="${AGENTS}.new.$$"
    awk -v field="${FIELD}" -v value="$(esc "${VALUE}")" '
        BEGIN { inproj=0; done=0 }
        /^project:/ { inproj=1; print; next }
        inproj==1 && /^[^[:space:]]/ { inproj=0 }
        inproj==1 && done==0 && $0 ~ "^  " field ":[[:space:]]*" {
            print "  " field ": \"" value "\""
            done=1
            next
        }
        { print }
        END { if (done==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未在 project 段找到字段 '${FIELD}'" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已更新 project.${FIELD}"
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

    tmp_body="${AGENTS}.body.$$"
    extract_body "${tmp_body}"

    if [ "${IF_EMPTY}" -eq 1 ]; then
        CUR=$(awk '
            /^skill_version:[[:space:]]*/ {
                line=$0
                sub(/^skill_version:[[:space:]]*/, "", line)
                gsub(/"/, "", line)
                sub(/^[[:space:]]+/, "", line)
                sub(/[[:space:]]+$/, "", line)
                print line
                exit
            }
        ' "${tmp_body}")
        if [ -n "${CUR}" ]; then
            echo "skill_version 已有值 \"${CUR}\"，跳过填充"
            rm -f "${tmp_body}"
            return 0
        fi
    fi

    tmp_new="${AGENTS}.new.$$"
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

# work-add: 追加工作条目
cmd_work_add() {
    ID="$3"; DESC="$4"; WPATH="$5"; BRANCH="$6"; SERVICES="${7:-}"; TRIGGERS="${8:-}"
    # --no-commit 可落在第 8 位（未传 triggers 时），此时清空 triggers
    [ "${TRIGGERS}" = "--no-commit" ] && TRIGGERS=""
    [ -n "${ID}" ] || { echo "Usage: project.sh work-add <root> <id> <description> <work_path> <branch> [services] [triggers]" >&2; exit 1; }
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

    tmp_body="${AGENTS}.body.$$"
    extract_body "${tmp_body}"

    # 同 work_id 已存在则拒绝（幂等保护）
    if awk -v id="$(esc "${ID}")" '
        /^[[:space:]]*-[[:space:]]*work_id:/ {
            line=$0; sub(/.*work_id:[[:space:]]*/,"",line)
            gsub(/"/,"",line); gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
            if (line==id) found=1
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

    tmp_entry="${AGENTS}.entry.$$"
    cat > "${tmp_entry}" <<EOF
  - work_id: "$(esc "${ID}")"
    description: "$(esc "${DESC}")"
    trigger_words: [$TRIG_LIST]
    work_path: "$(esc "${WPATH}")"
    branch: "$(esc "${BRANCH}")"
    services: [$SVC_LIST]
    status: "initialized"
    created_at: "${CREATED_AT}"
EOF

    tmp_new="${AGENTS}.new.$$"
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
    echo "已登记工作: ${ID}"
}

# work-set: 更新某工作条目状态
cmd_work_set() {
    ID="$3"; STATUS="$4"
    [ -n "${ID}" ] && [ -n "${STATUS}" ] || { echo "Usage: project.sh work-set <root> <id> <status>" >&2; exit 1; }
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

    tmp_body="${AGENTS}.body.$$"
    extract_body "${tmp_body}"
    tmp_new="${AGENTS}.new.$$"
    awk -v want="$(esc "${ID}")" -v st="$(esc "${STATUS}")" '
        BEGIN { inwork=0; cur=""; updated=0 }
        /^work:/ { inwork=1; print; next }
        inwork==1 && /^[^[:space:]]/ { inwork=0 }
        inwork==1 && $0 ~ /^[[:space:]]*-[[:space:]]*work_id:/ {
            line=$0; sub(/.*work_id:[[:space:]]*/,"",line)
            gsub(/"/,"",line); gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
            cur=line
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

# keywords: 覆盖写 project.keywords（逗号分隔；空值写空序列）
cmd_keywords() {
    KW="$3"
    [ -n "${KW}" ] || { echo "Usage: project.sh keywords <root> <kw1,kw2,...>" >&2; exit 1; }
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

    tmp_body="${AGENTS}.body.$$"
    extract_body "${tmp_body}"
    tmp_new="${AGENTS}.new.$$"
    awk -v kws="$(esc "${KW}")" '
        BEGIN { inproj=0; inkw=0; done=0 }
        /^project:/ { inproj=1; print; next }
        inproj==1 && /^[^[:space:]]/ { inproj=0; inkw=0 }
        inproj==1 && $0 ~ /^  keywords:[[:space:]]*($|#)/ {
            n = split(kws, arr, ",")
            c = 0
            for (i=1;i<=n;i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", arr[i])
                if (arr[i] != "") { c++; clean[c] = arr[i] }
            }
            if (c == 0) { print "  keywords: []" }
            else {
                print "  keywords:"
                for (i=1;i<=c;i++) print "    - \"" clean[i] "\""
            }
            inkw=1; done=1; next
        }
        inproj==1 && inkw==1 && $0 ~ /^[[:space:]]*-[[:space:]]/ { next }
        inproj==1 && inkw==1 && $0 ~ /^  [A-Za-z_]/ { inkw=0 }
        { print }
        END { if (done==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未在 project 段找到 keywords 字段" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已更新 project.keywords"
}

# service-repo: 追加一条 project.service_repo_mapping（空 [] 替换为块，非空在块尾追加）
cmd_service_repo() {
    SVC="$3"; RN="$4"; RG="$5"; RP="$6"
    if [ -z "${SVC}" ] || [ -z "${RN}" ] || [ -z "${RP}" ]; then
        echo "Usage: project.sh service-repo <root> <service_name> <repo_name> <repo_git> <repo_path>" >&2
        exit 1
    fi
    has_block || { echo "Error: 项目信息区块不存在，先执行 project.sh ensure" >&2; exit 1; }

    tmp_body="${AGENTS}.body.$$"
    extract_body "${tmp_body}"
    tmp_new="${AGENTS}.new.$$"
    awk -v svc="$(esc "${SVC}")" -v rn="$(esc "${RN}")" -v rg="$(esc "${RG}")" -v rp="$(esc "${RP}")" '
        function emit() {
            print "    - service_name: \"" svc "\""
            print "      repo_name: \"" rn "\""
            print "      repo_git: \"" rg "\""
            print "      repo_path: \"" rp "\""
        }
        BEGIN { inproj=0; inmap=0; done=0 }
        /^project:/ { inproj=1; print; next }
        inproj==1 && /^[^[:space:]]/ {
            if (inmap==1) { emit(); done=1; inmap=0 }
            inproj=0
            print; next
        }
        inproj==1 && $0 ~ /^  service_repo_mapping:[[:space:]]*\[\][[:space:]]*(#.*)?$/ {
            print "  service_repo_mapping:"
            emit(); done=1
            next
        }
        inproj==1 && $0 ~ /^  service_repo_mapping:[[:space:]]*($|#)/ { inmap=1; print; next }
        inproj==1 && inmap==1 && $0 ~ /^  [A-Za-z_]/ {
            emit(); done=1; inmap=0
            print; next
        }
        { print }
        END { if (inmap==1 && done==0) { emit(); done=1 }; if (done==0) exit 3 }
    ' "${tmp_body}" > "${tmp_new}" || {
        echo "Error: 未在 project 段找到 service_repo_mapping 字段" >&2
        rm -f "${tmp_body}" "${tmp_new}"; exit 1
    }
    rewrite_block "${tmp_new}"
    rm -f "${tmp_body}" "${tmp_new}"
    echo "已登记服务映射: ${SVC} -> ${RN}"
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
    tmp_body="${AGENTS}.body.$$"
    extract_body "${tmp_body}"
    tmp_new="${AGENTS}.new.$$"
    awk -v want="$(esc "${ID}")" -v list="${SVC_LIST}" '
        BEGIN { inwork=0; cur=""; updated=0 }
        /^work:/ { inwork=1; print; next }
        inwork==1 && /^[^[:space:]]/ { inwork=0 }
        inwork==1 && $0 ~ /^[[:space:]]*-[[:space:]]*work_id:/ {
            line=$0; sub(/.*work_id:[[:space:]]*/,"",line)
            gsub(/"/,"",line); gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
            cur=line
            print; next
        }
        inwork==1 && cur==want && $0 ~ /^[[:space:]]+services:/ {
            print "    services: [" list "]"
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
        awk -v list="${SVC_LIST}" '
            /^services:[[:space:]]*/ { print "services: [" list "]"; done=1; next }
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

    tmp_body="${AGENTS}.body.$$"
    extract_body "${tmp_body}"

    # 提取目标条目的现有 trigger_words 与 branch（用 sed 范围匹配，兼容有无 trigger_words 字段的条目）
    WANT_ID="$(esc "${ID}")"
    EXISTING=$(sed -n '/work_id: "'"${WANT_ID}"'"/,/work_id: *"/{ /trigger_words:/!d; s/.*trigger_words: *\[//; s/\].*//; s/"//g; p }' "${tmp_body}")
    BR=$(sed -n '/work_id: "'"${WANT_ID}"'"/,/work_id: *"/{ /branch:/!d; s/.*branch: *"//; s/".*//; p }' "${tmp_body}")

    # 验证 work_id 存在（EXISTING 和 BR 同时为空且无匹配 → 报错）
    if [ -z "${BR}" ]; then
        # 再确认一次条目是否存在（可能条目无 branch 字段，极少情况）
        if ! awk -v id="$(esc "${ID}")" '
            /^[[:space:]]*-[[:space:]]*work_id:/ {
                line=$0; sub(/.*work_id:[[:space:]]*/,"",line)
                gsub(/"/,"",line); gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
                if (line==id) found=1
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
    tmp_new="${AGENTS}.new.$$"
    awk -v want="$(esc "${ID}")" -v list="${MERGED_LIST}" '
        BEGIN { inwork=0; cur=""; inserted=0 }
        /^work:/ { inwork=1; print; next }
        inwork==1 && /^[^[:space:]]/ { inwork=0 }
        inwork==1 && $0 ~ /^[[:space:]]*-[[:space:]]*work_id:/ {
            line=$0; sub(/.*work_id:[[:space:]]*/,"",line)
            gsub(/"/,"",line); gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
            cur=line
            print; next
        }
        inwork==1 && cur==want && $0 ~ /^[[:space:]]+description:/ {
            print
            if (inserted==0) { print "    trigger_words: [" list "]"; inserted=1 }
            next
        }
        inwork==1 && cur==want && $0 ~ /^[[:space:]]+trigger_words:/ {
            if (inserted==0) { print "    trigger_words: [" list "]"; inserted=1 }
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
    ensure)        cmd_ensure ;;
    set)           cmd_set "$@" ;;
    skill-version) cmd_skill_version "$@" ;;
    keywords)      cmd_keywords "$@" ;;
    service-repo)  cmd_service_repo "$@" ;;
    work-add)      cmd_work_add "$@" ;;
    work-set)      cmd_work_set "$@" ;;
    work-services) cmd_work_services "$@" ;;
    work-trigger)  cmd_work_trigger "$@" ;;
    *) echo "Error: 未知动作 '${ACTION}'（支持 ensure / set / skill-version / keywords / service-repo / work-add / work-set / work-services / work-trigger）" >&2; exit 1 ;;
esac

# AGENTS.md 项目信息区块变更后，框架自动提交空间仓库（无变更时 space.sh 内部跳过）；
# --no-commit 时交由复合流程（init-tack、update）统一收尾提交
if [ "${NO_COMMIT}" -ne 1 ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    sh "${SCRIPT_DIR}/space.sh" commit "${ROOT}" "chore(tack): project ${ACTION}"
fi
