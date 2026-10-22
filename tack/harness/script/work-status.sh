#!/bin/sh
# work-status.sh — 确定性回写工作区 status.yaml 的常用字段
#
# 用法: sh work-status.sh <status.yaml> set <key> <value> [<key> <value> ...]
#   key 取值:
#     status            顶层 status 字段（工作流状态机取值）
#     stage|task|next   current 区块下的 stage/task/next
#     progress.<名称>   progress 区块下的布尔开关（值 true/false）
#     updated_at        顶层 updated_at（一般不显式传；每次执行自动刷新为当前时间）
#     mr_url|meego|tech_doc_url  顶层工作区链接字段
#     work_id|work_dir|branch    顶层工作区标识（work.sh rename 使用）
#
# 用法: sh work-status.sh <status.yaml> guidance <id> <distilled|dismissed> [落点路径 ..]
#   - distilled: 置该条 status，并写/更新「落点:」行（须给 ≥1 个落点，相对 $root，空格分隔）
#   - dismissed: 仅置该条 status（不接受落点参数）
#   - 条目（guidance 区块内 - id: "<id>"）不存在时退出码 3
# 用法: sh work-status.sh <status.yaml> guidance list [raw|all]
#   - 输出 guidance 条目（默认 raw），每行一条，TAB 分隔：
#     workspace / id / status / stage / candidate / summary
#   - workspace 取 status.yaml 的 work_dir（缺失时取所在目录名）
#
# 用法: sh work-status.sh <status.yaml> tasks list
#   - 输出 tasks 条目，每行一条，TAB 分隔：id / status / title / repo / deps(逗号分隔)
# 用法: sh work-status.sh <status.yaml> tasks validate
#   - 校验悬空依赖、自依赖、循环依赖、重复 ID、非法状态；错误行：ERROR<TAB>code<TAB>id<TAB>detail
#   - 存在错误退出码 4（结构/依赖/状态非法）
# 用法: sh work-status.sh <status.yaml> tasks ready
#   - 输出 deps 已全部 done 的 pending 任务，TAB 分隔：id / title / repo / deps
# 用法: sh work-status.sh <status.yaml> tasks repos
#   - 输出去重后的非空 repo，每行一个（供 git-diff-context.sh batch 使用）
# 用法: sh work-status.sh <status.yaml> tasks set <task-id> <pending|in_progress|done|blocked>
#   - 按允许的迁移图改单条状态；任务不存在退出码 3；非法迁移退出码 4
# 用法: sh work-status.sh <status.yaml> tasks replace <normalized-tsv>
#   - normalized-tsv 为文件路径（- 表示 stdin），列：id title module repo deps-csv status
#   - 首行可为表头；写入前校验依赖图，非法则不落盘并退出码 4
#   - 已存在同一 id 时保留其 acceptance / parallel_with 字段
#
# 用法: sh work-status.sh <status.yaml> deploy list
#   - 输出部署登记，每行一条，TAB 分隔：repo / env / lane / route / build / url / status
# 用法: sh work-status.sh <status.yaml> deploy upsert <repo> <env> <lane> <route> <build> <url> <status>
#   - (repo, env, lane) 为复合键：存在则覆盖字段，不存在则追加
# 用法: sh work-status.sh <status.yaml> deploy mark <repo> <env> <lane> <status>
#   - 只改状态；条目不存在退出码 3
#
# 用法: sh work-status.sh <status.yaml> branch register <repo> <name> <role> <source>
#   - 往 branches 列表追加一条（同 repo+name 已存在则跳过，退出码 0）
#   - role: main（工作区主分支）/ tmp（临时分支）；source: work / worktree / branch-op / rename
# 用法: sh work-status.sh <status.yaml> branch mark <repo> <name> cleaned
#   - 置匹配条目的 cleaned: true（条目不存在时退出码 3）
# 用法: sh work-status.sh <status.yaml> branch list
#   - 输出 branches 列表，每行一条：repo|name|role|source|cleaned（供 close 遍历）
# 用法: sh work-status.sh <status.yaml> branch rename <old-name> <new-name>
#   - 把 branches 中所有 name 为 old-name 的条目改为 new-name；输出 RENAMED=<条数>
#
# 行为:
#   - 字段已存在则就地更新；缺失则插入对应区块头部（顶层缺失则追加到文件末尾）
#   - 每次执行自动刷新 updated_at（显式传入时以传入值为准）
#   - 字符串值一律双引号包裹（与模板风格一致）；true/false 不加引号
# 退出码: 0 成功；1 文件不存在或写入失败；2 用法错误；
#         3 未知 key / guidance 或 tasks / deploy 条目不存在；
#         4 tasks 结构、依赖或状态非法（含非法状态迁移）
#
# 最小用例:
#   sh work-status.sh space/20261001-feat-x/status.yaml set status planning stage spec next "生成并确认 spec.md"
#   sh work-status.sh space/20261001-feat-x/status.yaml set progress.spec true
#   sh work-status.sh space/20261001-feat-x/status.yaml guidance G-01 distilled harness/cmd/dev/code.md
#   sh work-status.sh space/20261001-feat-x/status.yaml guidance G-02 dismissed

set -e

usage() {
  echo "work-status: 用法:" >&2
  echo "  sh work-status.sh <status.yaml> set <key> <value> [<key> <value> ...]" >&2
  echo "  sh work-status.sh <status.yaml> guidance <id> <distilled|dismissed> [落点路径 ..]" >&2
  echo "  sh work-status.sh <status.yaml> guidance list [raw|all]" >&2
  echo "  sh work-status.sh <status.yaml> tasks list|validate|ready|repos" >&2
  echo "  sh work-status.sh <status.yaml> tasks set <task-id> <pending|in_progress|done|blocked>" >&2
  echo "  sh work-status.sh <status.yaml> tasks replace <normalized-tsv>" >&2
  echo "  sh work-status.sh <status.yaml> deploy list" >&2
  echo "  sh work-status.sh <status.yaml> deploy upsert <repo> <env> <lane> <route> <build> <url> <status>" >&2
  echo "  sh work-status.sh <status.yaml> deploy mark <repo> <env> <lane> <status>" >&2
  echo "  sh work-status.sh <status.yaml> branch register <repo> <name> <role> <source>" >&2
  echo "  sh work-status.sh <status.yaml> branch mark <repo> <name> cleaned" >&2
  echo "  sh work-status.sh <status.yaml> branch list" >&2
  echo "  sh work-status.sh <status.yaml> branch rename <old-name> <new-name>" >&2
}

if [ $# -lt 3 ]; then
  usage
  exit 2
fi
FILE="$1"
SUBCMD="$2"
shift 2
if [ ! -f "${FILE}" ]; then
  echo "work-status: 文件不存在: ${FILE}" >&2
  exit 1
fi
case "${SUBCMD}" in
  set|guidance|tasks|deploy|branch) ;;
  *)
    echo "work-status: 未知子命令: ${SUBCMD}（支持 set / guidance / tasks / deploy / branch）" >&2
    usage
    exit 2
    ;;
esac

# 临时文件优先放 tack 空间 .tack/tmp/（不写系统 temp，退出即清）；
# 仅当 FILE 不在规范空间布局内（<root>/space/<workspace>/status.yaml）时回退系统临时目录
SPACE_ROOT="$(cd "$(dirname "${FILE}")/../.." 2>/dev/null && pwd)" || SPACE_ROOT=""
TMP_DIR=""
if [ -n "${SPACE_ROOT}" ] && [ -d "${SPACE_ROOT}/harness" ]; then
    TMP_DIR="${SPACE_ROOT}/.tack/tmp"
    mkdir -p "${TMP_DIR}" 2>/dev/null || TMP_DIR=""
fi
if [ -n "${TMP_DIR}" ]; then
    PAIRS="${TMP_DIR}/work-status.$$.pairs"
    TMP="${TMP_DIR}/work-status.$$.out"
else
    PAIRS="$(mktemp "${TMPDIR:-/tmp}/tack-ws-pairs.XXXXXX")"
    TMP="$(mktemp "${TMPDIR:-/tmp}/tack-ws-out.XXXXXX")"
fi
trap 'rm -f "${PAIRS}" "${TMP}"; rmdir "${TMP_DIR}" 2>/dev/null || true' EXIT HUP INT TERM

# 共享 YAML 标量/行内列表函数（唯一事实源 script/yamlib.awk）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YAML_LIB="$(cat "${SCRIPT_DIR}/yamlib.awk")"

# guidance 子命令：固化结论回写（distilled 写「落点:」行；dismissed 仅置状态）
if [ "${SUBCMD}" = "guidance" ]; then
  # guidance list [raw|all]：跨工作区统一列举（TAB 分隔）
  if [ "${1:-}" = list ]; then
    GFILTER="${2:-raw}"
    case "${GFILTER}" in
      raw|all) ;;
      *) echo "work-status: guidance list 过滤值只允许 raw|all: ${GFILTER}" >&2; exit 2 ;;
    esac
    # 工作区名：优先 work_dir，缺失时取 status.yaml 所在目录名
    GWORK="$(awk "${YAML_LIB}"'
      /^work_dir[[:space:]]*:/ {
          v=val($0); if (v!="") { print v; exit }
      }
    ' "${FILE}")"
    if [ -z "${GWORK}" ]; then
      GWORK="$(basename "$(dirname "${FILE}")")"
    fi
    awk -v WANT="${GFILTER}" -v WS="${GWORK}" "${YAML_LIB}"'
      function flush() {
          if (cur_id != "" && (WANT == "all" || cur_status == "raw" || cur_status == ""))
              printf "%s\t%s\t%s\t%s\t%s\t%s\n", WS, cur_id, cur_status, cur_stage, cur_candidate, cur_summary
          cur_id=""; cur_status=""; cur_stage=""; cur_candidate=""; cur_summary=""
      }
      BEGIN { in_g=0; cur_id=""; cur_status=""; cur_stage=""; cur_candidate=""; cur_summary="" }
      /^guidance[[:space:]]*:/ { in_g=1; next }
      in_g && /^[A-Za-z_][A-Za-z0-9_]*:/ { flush(); in_g=0 }
      {
          if (!in_g) next
          if ($0 ~ /^[[:space:]]*#/) next
          if ($0 ~ /^[[:space:]]*-[[:space:]]*id[[:space:]]*:/) {
              flush()
              line=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", line)
              cur_id = val(line)
              next
          }
          if (cur_id == "") next
          if ($0 ~ /^[[:space:]]*status[[:space:]]*:/) { cur_status = val($0); next }
          if ($0 ~ /^[[:space:]]*stage[[:space:]]*:/) { cur_stage = val($0); next }
          if ($0 ~ /^[[:space:]]*candidate[[:space:]]*:/) { cur_candidate = val($0); next }
          if ($0 ~ /^[[:space:]]*guidance[[:space:]]*:/) { cur_summary = val($0); next }
      }
      END { flush() }
    ' "${FILE}"
    exit 0
  fi
  if [ $# -lt 2 ]; then
    echo "work-status: guidance 用法: guidance <id> <distilled|dismissed> [落点路径 ...]" >&2
    exit 2
  fi
  GID="$1"
  GSTATE="$2"
  shift 2
  case "${GSTATE}" in
    distilled|dismissed) ;;
    *) echo "work-status: guidance 状态只允许 distilled|dismissed: ${GSTATE}" >&2; exit 2 ;;
  esac
  GLAND=""
  if [ "${GSTATE}" = "distilled" ]; then
    [ $# -ge 1 ] || { echo "work-status: distilled 必须提供至少一个落点路径（相对 \$root，多落点空格分隔）" >&2; exit 2; }
    for _lp in "$@"; do GLAND="${GLAND} ${_lp}"; done
    GLAND="${GLAND# }"
  else
    [ $# -eq 0 ] || { echo "work-status: dismissed 不接受落点路径" >&2; exit 2; }
  fi
  if awk -v GID="${GID}" -v GSTATE="${GSTATE}" -v GLAND="${GLAND}" -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" "${YAML_LIB}"'
    # 目标条目在「下一条目 / 下一顶层键 / EOF」边界结束，补写缺失行
    function finish(   ind) {
        if (!target) { cur = ""; target = 0; return }
        ind = item_ind
        if (!saw_status) print ind "status: \"" GSTATE "\""
        if (GSTATE == "distilled" && !saw_land) print ind "落点: \"" GLAND "\""
        cur = ""; target = 0
    }
    BEGIN { in_g = 0; cur = ""; target = 0; saw_status = 0; saw_land = 0; found = 0 }
    /^[A-Za-z_][A-Za-z0-9_]*:/ {
        if (in_g) finish()
        in_g = ($0 ~ /^guidance[[:space:]]*:/)
        if ($0 ~ /^updated_at[[:space:]]*:/) { print "updated_at: \"" NOW "\""; next }
        print
        next
    }
    {
        if (!in_g) { print; next }
        if ($0 ~ /^[[:space:]]*-[[:space:]]*id[[:space:]]*:/) {
            finish()
            _idl = $0
            sub(/^[[:space:]]*-[[:space:]]*/, "", _idl)
            cur = vof(_idl)
            match($0, /^[[:space:]]*/)
            item_ind = sprintf("%" (RLENGTH + 2) "s", "")
            target = (cur == GID)
            if (target) { found = 1; saw_status = 0; saw_land = 0 }
            print
            next
        }
        if (target) {
            if ($0 ~ /^[[:space:]]*status[[:space:]]*:/) {
                print item_ind "status: \"" GSTATE "\""
                saw_status = 1
                next
            }
            if (GSTATE == "distilled" && index($0, "落点:") > 0) {
                print item_ind "落点: \"" GLAND "\""
                saw_land = 1
                next
            }
        }
        print
    }
    END {
        finish()
        if (!found) exit 3
    }
  ' "${FILE}" > "${TMP}"; then
    :
  else
    _rc=$?
    if [ "${_rc}" -eq 3 ]; then
      echo "work-status: guidance 条目不存在: ${GID}" >&2
    else
      echo "work-status: 写入失败" >&2
    fi
    exit "${_rc}"
  fi
  mv "${TMP}" "${FILE}"
  exit 0
fi

# tasks 子命令：任务清单的只读查询、依赖校验与结构化写入
if [ "${SUBCMD}" = tasks ]; then
  TACT="${1:-}"
  case "${TACT}" in
    list|validate|ready|repos|set|replace) shift ;;
    *)
      echo "work-status: tasks 子动作只支持 list|validate|ready|repos|set|replace: ${TACT}" >&2
      exit 2
      ;;
  esac

  # 任务区块解析（只读）：输出/校验共用同一套解析口径
  TASKS_AWK='
    function flush() {
        if (!item_open) return
        n++
        ids[n] = cur_id; titles[n] = cur_title; modules[n] = cur_module
        repos[n] = cur_repo; deps[n] = cur_deps
        statuses[n] = (cur_status == "" ? "pending" : cur_status)
        item_open = 0; cur_id = ""; cur_title = ""; cur_module = ""
        cur_repo = ""; cur_deps = ""; cur_status = ""
    }
    BEGIN { in_t = 0; item_open = 0; n = 0; cur_id = ""; cur_title = ""; cur_module = ""; cur_repo = ""; cur_deps = ""; cur_status = "" }
    /^[A-Za-z_][A-Za-z0-9_]*:/ {
        if (in_t) flush()
        in_t = ($0 ~ /^tasks[[:space:]]*:/)
        if (in_t && $0 ~ /^tasks[[:space:]]*:[[:space:]]*\[\][[:space:]]*$/) in_t = 0
        next
    }
    {
        if (!in_t) next
        if ($0 ~ /^[[:space:]]*#/) next
        if ($0 ~ /^[[:space:]]*-[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/) {
            flush()
            item_open = 1
            line = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", line)
            key = line; sub(/:.*/, "", key); key = trim(key)
            v = val(line)
            if (key == "id") cur_id = v
            else if (key == "title") cur_title = v
            else if (key == "module") cur_module = v
            else if (key == "repo") cur_repo = v
            else if (key == "deps") cur_deps = norm_csv(v)
            else if (key == "status") cur_status = v
            next
        }
        if (!item_open) next
        if ($0 ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/) {
            line = $0; sub(/^[[:space:]]*/, "", line)
            key = line; sub(/:.*/, "", key); key = trim(key)
            v = val(line)
            if (key == "id") cur_id = v
            else if (key == "title") cur_title = v
            else if (key == "module") cur_module = v
            else if (key == "repo") cur_repo = v
            else if (key == "deps") cur_deps = norm_csv(v)
            else if (key == "status") cur_status = v
            next
        }
        # 块格式 deps（- A-01）按逗号拼接
        if ($0 ~ /^[[:space:]]+-[[:space:]]/) {
            x = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", x)
            x = clean(x)
            if (x != "") cur_deps = (cur_deps == "" ? x : cur_deps "," x)
        }
    }
    END {
        if (in_t) flush()
        if (MODE == "list") {
            for (i = 1; i <= n; i++)
                printf "%s\t%s\t%s\t%s\t%s\n", ids[i], statuses[i], titles[i], repos[i], deps[i]
            exit 0
        }
        if (MODE == "repos") {
            for (i = 1; i <= n; i++) {
                if (repos[i] == "" || (repos[i] in seen)) continue
                seen[repos[i]] = 1; print repos[i]
            }
            exit 0
        }
        if (MODE == "status") {
            for (i = 1; i <= n; i++) {
                if (ids[i] == ARG) { print statuses[i]; exit 0 }
            }
            exit 3
        }
        if (MODE == "ready") {
            for (i = 1; i <= n; i++) st[ids[i]] = statuses[i]
            for (i = 1; i <= n; i++) {
                if (statuses[i] != "pending") continue
                m = split(deps[i], da, ","); ok = 1
                for (j = 1; j <= m; j++) if (da[j] != "" && st[da[j]] != "done") ok = 0
                if (ok) printf "%s\t%s\t%s\t%s\n", ids[i], titles[i], repos[i], deps[i]
            }
            exit 0
        }
        if (MODE == "validate") {
            bad = 0
            for (i = 1; i <= n; i++) {
                if (ids[i] == "") { printf "ERROR\tmissing-id\t-\t第 %d 条任务缺少 id\n", i; bad = 1; continue }
                if (ids[i] in id_count) {
                    printf "ERROR\tduplicate-id\t%s\t重复的任务 ID\n", ids[i]; bad = 1
                }
                id_count[ids[i]] = 1
                if (statuses[i] != "" && statuses[i] != "pending" && statuses[i] != "in_progress" \
                    && statuses[i] != "done" && statuses[i] != "blocked") {
                    printf "ERROR\tinvalid-status\t%s\t非法状态 %s\n", ids[i], statuses[i]; bad = 1
                }
            }
            for (i = 1; i <= n; i++) if (ids[i] != "") idx[ids[i]] = i
            for (i = 1; i <= n; i++) {
                if (ids[i] == "") continue
                m = split(deps[i], da, ",")
                for (j = 1; j <= m; j++) {
                    d = da[j]; if (d == "") continue
                    if (d == ids[i]) { printf "ERROR\tself-dep\t%s\t依赖自身\n", ids[i]; bad = 1; continue }
                    if (!(d in idx)) { printf "ERROR\tdangling-dep\t%s\t依赖不存在的任务 %s\n", ids[i], d; bad = 1 }
                }
            }
            # Kahn 拓扑检测循环依赖
            vn = 0
            for (i = 1; i <= n; i++) if (ids[i] != "") vn++
            for (i = 1; i <= n; i++) if (ids[i] != "") {
                m = split(deps[i], da, ",")
                for (j = 1; j <= m; j++) {
                    d = da[j]
                    if (d == "" || d == ids[i] || !(d in idx)) continue
                    indeg[i]++
                    succ[idx[d]] = succ[idx[d]] " " i
                }
            }
            qh = 0; qt = 0
            for (i = 1; i <= n; i++) if (ids[i] != "" && indeg[i] == 0) queue[++qt] = i
            processed = 0
            while (qh < qt) {
                u = queue[++qh]; processed++
                m = split(succ[u], sa, " ")
                for (j = 1; j <= m; j++) {
                    v = sa[j]; if (v == "") continue
                    if (--indeg[v] == 0) queue[++qt] = v
                }
            }
            if (processed < vn) {
                cyc = ""
                for (i = 1; i <= n; i++)
                    if (ids[i] != "" && indeg[i] > 0) cyc = (cyc == "" ? ids[i] : cyc "," ids[i])
                printf "ERROR\tcycle\t%s\t循环依赖\n", cyc
                bad = 1
            }
            if (bad) exit 4
            printf "tasks: ok (%d)\n", n
            exit 0
        }
    }
  '
  TASKS_AWK="${YAML_LIB}${TASKS_AWK}"

  case "${TACT}" in
    list|validate|ready|repos)
      if awk -v MODE="${TACT}" "${TASKS_AWK}" "${FILE}"; then
        exit 0
      else
        exit $?
      fi
      ;;
    set)
      [ $# -ge 2 ] || { echo "work-status: tasks set 需要 <task-id> <pending|in_progress|done|blocked>" >&2; exit 2; }
      TID="$1"; TNEW="$2"
      case "${TNEW}" in
        pending|in_progress|done|blocked) ;;
        *) echo "work-status: 非法任务状态: ${TNEW}" >&2; exit 2 ;;
      esac
      if TOLD="$(awk -v MODE="status" -v ARG="${TID}" "${TASKS_AWK}" "${FILE}")"; then
        :
      else
        echo "work-status: 任务不存在: ${TID}" >&2
        exit 3
      fi
      [ -n "${TOLD}" ] || TOLD="pending"
      if [ "${TOLD}" = "${TNEW}" ]; then
        exit 0
      fi
      case "${TOLD}:${TNEW}" in
        pending:in_progress|pending:blocked|\
        in_progress:pending|in_progress:done|in_progress:blocked|\
        blocked:pending|blocked:in_progress|done:pending) ;;
        *)
          echo "work-status: 非法状态迁移: ${TID} ${TOLD} -> ${TNEW}" >&2
          exit 4
          ;;
      esac
      if awk -v ID="${TID}" -v NEW="${TNEW}" -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" "${YAML_LIB}"'
        function finish() {
            if (target && !saw) print "    status: \"" NEW "\""
            target = 0; saw = 0
        }
        BEGIN { in_t = 0; target = 0; saw = 0; found = 0 }
        /^[A-Za-z_][A-Za-z0-9_]*:/ {
            finish()
            in_t = ($0 ~ /^tasks[[:space:]]*:/)
            if ($0 ~ /^updated_at[[:space:]]*:/) { print "updated_at: \"" NOW "\""; next }
            print; next
        }
        {
            if (!in_t) { print; next }
            if ($0 ~ /^[[:space:]]*-[[:space:]]*id[[:space:]]*:/) {
                finish()
                line = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", line)
                if (vof(line) == ID) { target = 1; found = 1 }
                print; next
            }
            if (target && $0 ~ /^[[:space:]]*status[[:space:]]*:/) {
                print "    status: \"" NEW "\""; saw = 1; next
            }
            print
        }
        END {
            finish()
            if (!found) exit 3
        }
      ' "${FILE}" > "${TMP}"; then
        mv "${TMP}" "${FILE}"
        exit 0
      else
        _rc=$?
        [ "${_rc}" -eq 3 ] && echo "work-status: 任务不存在: ${TID}" >&2
        exit "${_rc}"
      fi
      ;;
    replace)
      [ $# -ge 1 ] || { echo "work-status: tasks replace 需要 <normalized-tsv>（文件路径，- 表示 stdin）" >&2; exit 2; }
      TSV_IN="$1"
      TSV_FILE=""
      if [ "${TSV_IN}" = "-" ]; then
        TSV_FILE="${TMP}.tsv"
        cat > "${TSV_FILE}"
      else
        [ -f "${TSV_IN}" ] || { echo "work-status: TSV 文件不存在: ${TSV_IN}" >&2; exit 1; }
        TSV_FILE="${TSV_IN}"
      fi
      # TSV 基础校验：6 列、id/title 非空、状态合法
      if ! awk -F'\t' '
        BEGIN { bad = 0; first = 1 }
        /^[[:space:]]*$/ { next }
        {
            if (first && tolower($1) == "id" && tolower($2) == "title") { first = 0; next }
            first = 0
            if (NF != 6) { printf "ERROR\tbad-columns\t%s\t期望 6 列，实际 %d 列\n", $1, NF; bad = 1; next }
            if ($1 == "") { printf "ERROR\tmissing-id\t-\t第 %d 行缺少 id\n", NR; bad = 1 }
            if ($2 == "") { printf "ERROR\tmissing-title\t%s\t缺少 title\n", $1; bad = 1 }
            s = ($6 == "" ? "pending" : $6)
            if (s != "pending" && s != "in_progress" && s != "done" && s != "blocked") {
                printf "ERROR\tinvalid-status\t%s\t非法状态 %s\n", $1, s; bad = 1
            }
        }
        END { exit (bad ? 4 : 0) }
      ' "${TSV_FILE}"; then
        exit 4
      fi
      if ! awk -v TSV="${TSV_FILE}" -v SRC="${FILE}" -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" "${YAML_LIB}"'
        function emit_item(i) {
            print "  - id: " esc(tid[i])
            print "    title: " esc(ttitle[i])
            print "    module: " esc(tmodule[i])
            print "    repo: " esc(trepo[i])
            print "    deps: " inline_list(tdeps[i])
            if (tid[i] in acc) print "    acceptance: " esc(acc[tid[i]])
            if (tid[i] in par) print "    parallel_with: " inline_list(par[tid[i]])
            print "    status: " esc(tstatus[i])
        }
        BEGIN {
            nt = 0; first = 1
            while ((getline line < TSV) > 0) {
                if (line ~ /^[[:space:]]*$/) continue
                nf = split(line, f, "\t")
                if (first && tolower(f[1]) == "id" && tolower(f[2]) == "title") { first = 0; continue }
                first = 0
                nt++
                tid[nt] = f[1]; ttitle[nt] = f[2]; tmodule[nt] = f[3]
                trepo[nt] = f[4]; tdeps[nt] = f[5]
                tstatus[nt] = (f[6] == "" ? "pending" : f[6])
            }
            close(TSV)
            # 预读旧文件：保留同一 id 的 acceptance / parallel_with
            in_t = 0; cur = ""; open_item = 0
            while ((getline line < SRC) > 0) {
                if (line ~ /^tasks[[:space:]]*:/) { in_t = 1; continue }
                if (in_t && line ~ /^[A-Za-z_][A-Za-z0-9_]*:/) { in_t = 0; continue }
                if (!in_t) continue
                if (line ~ /^[[:space:]]*-[[:space:]]*id[[:space:]]*:/) {
                    l = line; sub(/^[[:space:]]*-[[:space:]]*/, "", l); cur = val(l); open_item = 1; continue
                }
                if (!open_item || cur == "") continue
                if (line ~ /^[[:space:]]*acceptance[[:space:]]*:/) acc[cur] = val(line)
                else if (line ~ /^[[:space:]]*parallel_with[[:space:]]*:/) par[cur] = norm_csv(val(line))
            }
            close(SRC)
            ARGV[1] = ""
        }
        /^tasks[[:space:]]*:/ {
            if (nt == 0) { print "tasks: []" }
            else {
                print "tasks:"
                for (i = 1; i <= nt; i++) emit_item(i)
            }
            in_t = 1; next
        }
        in_t && /^[A-Za-z_][A-Za-z0-9_]*:/ {
            in_t = 0
            if ($0 ~ /^updated_at[[:space:]]*:/) { print "updated_at: \"" NOW "\""; next }
            print; next
        }
        in_t { next }
        /^updated_at[[:space:]]*:/ { print "updated_at: \"" NOW "\""; next }
        { print }
      ' "${TSV_FILE}" "${FILE}" > "${TMP}"; then
        echo "work-status: tasks replace 写入失败" >&2
        exit 1
      fi
      # 写入前按同一口径校验依赖图，非法则不落盘
      if awk -v MODE="validate" "${TASKS_AWK}" "${TMP}" >/dev/null; then
        [ "${TSV_IN}" = "-" ] && rm -f "${TSV_FILE}"
        mv "${TMP}" "${FILE}"
        exit 0
      else
        _rc=$?
        awk -v MODE="validate" "${TASKS_AWK}" "${TMP}" >&2 || true
        [ "${TSV_IN}" = "-" ] && rm -f "${TSV_FILE}"
        exit "${_rc}"
      fi
      ;;
  esac
fi

# deploy 子命令：部署/泳道登记（(repo, env, lane) 复合键）
if [ "${SUBCMD}" = deploy ]; then
  DACT="${1:-}"
  case "${DACT}" in
    list|upsert|mark) shift ;;
    *)
      echo "work-status: deploy 子动作只支持 list|upsert|mark: ${DACT}" >&2
      exit 2
      ;;
  esac

  DSTATUSES="deploying deployed verified recycled"

  case "${DACT}" in
    list)
      awk "${YAML_LIB}"'
        function flush() {
            if (cur_repo != "" || cur_env != "" || cur_lane != "")
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", cur_repo, cur_env, cur_lane, cur_route, cur_build, cur_url, cur_status
            cur_repo=""; cur_env=""; cur_lane=""; cur_route=""; cur_build=""; cur_url=""; cur_status=""
        }
        BEGIN { in_d = 0; cur_repo=""; cur_env=""; cur_lane=""; cur_route=""; cur_build=""; cur_url=""; cur_status="" }
        /^deploy[[:space:]]*:/ {
            in_d = 1
            if ($0 ~ /\[\][[:space:]]*$/) in_d = 0
            next
        }
        in_d && /^[A-Za-z_][A-Za-z0-9_]*:/ { flush(); in_d = 0; next }
        {
            if (!in_d) next
            if ($0 ~ /^[[:space:]]*-[[:space:]]*repo[[:space:]]*:/) {
                flush()
                cur_repo = vof($0); next
            }
            if ($0 ~ /^[[:space:]]*env[[:space:]]*:/) { cur_env = vof($0); next }
            if ($0 ~ /^[[:space:]]*lane[[:space:]]*:/) { cur_lane = vof($0); next }
            if ($0 ~ /^[[:space:]]*route[[:space:]]*:/) { cur_route = vof($0); next }
            if ($0 ~ /^[[:space:]]*build[[:space:]]*:/) { cur_build = vof($0); next }
            if ($0 ~ /^[[:space:]]*url[[:space:]]*:/) { cur_url = vof($0); next }
            if ($0 ~ /^[[:space:]]*status[[:space:]]*:/) { cur_status = vof($0); next }
        }
        END { flush() }
      ' "${FILE}"
      exit 0
      ;;
    upsert)
      [ $# -ge 7 ] || { echo "work-status: deploy upsert 需要 <repo> <env> <lane> <route> <build> <url> <status>" >&2; exit 2; }
      D_REPO="$1"; D_ENV="$2"; D_LANE="$3"; D_ROUTE="$4"; D_BUILD="$5"; D_URL="$6"; D_STATUS="$7"
      case " ${DSTATUSES} " in
        *" ${D_STATUS} "*) ;;
        *) echo "work-status: 非法部署状态: ${D_STATUS}（允许 ${DSTATUSES}）" >&2; exit 2 ;;
      esac
      if awk -v REPO="${D_REPO}" -v ENV="${D_ENV}" -v LANE="${D_LANE}" -v ROUTE="${D_ROUTE}" \
            -v BUILD="${D_BUILD}" -v URL="${D_URL}" -v STATUS="${D_STATUS}" \
            -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" "${YAML_LIB}"'
        function emit_new() {
            print "  - repo: " esc(REPO)
            print "    env: " esc(ENV)
            print "    lane: " esc(LANE)
            print "    route: " esc(ROUTE)
            print "    build: " esc(BUILD)
            print "    url: " esc(URL)
            print "    status: " esc(STATUS)
        }
        # 条目边界收口：缓冲整条，命中 (repo, env, lane) 复合键时原位替换为新值，
        # 未命中则原样输出；缓冲让字段顺序不影响匹配
        function flush_entry(   i, key) {
            if (!in_entry) return
            repo = ""; env = ""; lane = ""
            for (i = 1; i <= nbuf; i++) {
                key = buf[i]
                sub(/^[[:space:]]*-[[:space:]]*/, "", key)
                sub(/^[[:space:]]*/, "", key)
                sub(/:.*/, "", key)
                if (key == "repo") repo = vof(buf[i])
                else if (key == "env") env = vof(buf[i])
                else if (key == "lane") lane = vof(buf[i])
            }
            if (repo == REPO && env == ENV && lane == LANE) { emit_new(); replaced = 1 }
            else for (i = 1; i <= nbuf; i++) print buf[i]
            in_entry = 0; nbuf = 0
        }
        function flush() {
            flush_entry()
            if (in_b && block_seen && !replaced) { emit_new(); replaced = 1 }
            in_b = 0
        }
        BEGIN { in_b = 0; block_seen = 0; replaced = 0; in_entry = 0; nbuf = 0 }
        /^[A-Za-z_][A-Za-z0-9_]*:/ {
            flush()
            if ($0 ~ /^deploy[[:space:]]*:/) {
                block_seen = 1
                if ($0 ~ /\[\][[:space:]]*$/) {
                    print "deploy:"
                    emit_new(); replaced = 1
                    in_b = 1; next
                }
                in_b = 1; print; next
            }
            if ($0 ~ /^updated_at[[:space:]]*:/) { print "updated_at: \"" NOW "\""; next }
            print; next
        }
        {
            if (!in_b) { print; next }
            # 注释/空行不并入条目：先收口，避免替换条目时误删注释
            if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) {
                flush_entry()
                print; next
            }
            if ($0 ~ /^[[:space:]]*-[[:space:]]*(repo|env|lane|route|build|url|status)[[:space:]]*:/) {
                flush_entry()
                in_entry = 1; nbuf = 1; buf[1] = $0
                next
            }
            if (!in_entry) { print; next }
            nbuf++; buf[nbuf] = $0
        }
        END {
            flush_entry()
            if (!block_seen) {
                print "deploy:"
                emit_new()
            } else if (in_b && !replaced) {
                emit_new()
            }
        }
      ' "${FILE}" > "${TMP}"; then
        mv "${TMP}" "${FILE}"
        exit 0
      fi
      echo "work-status: deploy upsert 写入失败" >&2
      exit 1
      ;;
    mark)
      [ $# -ge 4 ] || { echo "work-status: deploy mark 需要 <repo> <env> <lane> <status>" >&2; exit 2; }
      D_REPO="$1"; D_ENV="$2"; D_LANE="$3"; D_STATUS="$4"
      case " ${DSTATUSES} " in
        *" ${D_STATUS} "*) ;;
        *) echo "work-status: 非法部署状态: ${D_STATUS}（允许 ${DSTATUSES}）" >&2; exit 2 ;;
      esac
      if awk -v REPO="${D_REPO}" -v ENV="${D_ENV}" -v LANE="${D_LANE}" -v STATUS="${D_STATUS}" \
            -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" "${YAML_LIB}"'
        BEGIN { in_b = 0; cur_repo = ""; cur_env = ""; cur_lane = ""; target = 0; found = 0; saw = 0 }
        /^[A-Za-z_][A-Za-z0-9_]*:/ {
            if (target && !saw) { print "    status: \"" STATUS "\""; saw = 1 }
            in_b = ($0 ~ /^deploy[[:space:]]*:/)
            if ($0 ~ /^updated_at[[:space:]]*:/) { print "updated_at: \"" NOW "\""; next }
            print; next
        }
        {
            if (!in_b) { print; next }
            if ($0 ~ /^[[:space:]]*-[[:space:]]*repo[[:space:]]*:/) {
                if (target && !saw) { print "    status: \"" STATUS "\""; saw = 1 }
                cur_repo = vof($0); cur_env = ""; cur_lane = ""; target = 0; print; next
            }
            if ($0 ~ /^[[:space:]]*env[[:space:]]*:/) { cur_env = vof($0); print; next }
            if ($0 ~ /^[[:space:]]*lane[[:space:]]*:/) {
                cur_lane = vof($0)
                if (cur_repo == REPO && cur_env == ENV && cur_lane == LANE) { target = 1; found = 1; saw = 0 }
                print; next
            }
            if (target && $0 ~ /^[[:space:]]*status[[:space:]]*:/) {
                print "    status: \"" STATUS "\""; saw = 1; next
            }
            print
        }
        END {
            if (target && !saw) print "    status: \"" STATUS "\""
            if (!found) exit 3
        }
      ' "${FILE}" > "${TMP}"; then
        mv "${TMP}" "${FILE}"
        exit 0
      else
        _rc=$?
        [ "${_rc}" -eq 3 ] && echo "work-status: 部署条目不存在: ${D_REPO}/${D_ENV}/${D_LANE}" >&2
        exit "${_rc}"
      fi
      ;;
  esac
fi

# branch 子命令：branches 列表登记簿的 register / mark / list
if [ "${SUBCMD}" = branch ]; then
  BACT="${1:-}"
  [ -n "${BACT}" ] || { echo "work-status: branch 缺少子动作（register|mark|list）" >&2; exit 2; }
  shift
  case "${BACT}" in
    register)
      [ $# -ge 4 ] || { echo "work-status: branch register 需要 <repo> <name> <role> <source>" >&2; exit 2; }
      B_REP="$1"; B_NAM="$2"; B_ROL="$3"; B_SRC="$4"
      set +e
      awk -v REP="${B_REP}" -v NAM="${B_NAM}" -v ROL="${B_ROL}" -v SRC="${B_SRC}" -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" "${YAML_LIB}"'
        function emit_new() {
            print "  - repo: \"" REP "\""
            print "    name: \"" NAM "\""
            print "    role: \"" ROL "\""
            print "    source: \"" SRC "\""
            print "    cleaned: false"
        }
        BEGIN { in_b=0; cur_repo=""; dup=0; emitted=0; has_b=0 }
        /^[A-Za-z_][A-Za-z0-9_]*:/ {
            if (in_b && !emitted && !dup) { emit_new(); emitted=1 }
            in_b=0
            if ($0 ~ /^branches[[:space:]]*:[[:space:]]*\[\][[:space:]]*$/) {
                has_b=1
                print "branches:"
                emit_new(); emitted=1
                in_b=1
                next
            }
            if ($0 ~ /^branches[[:space:]]*:[[:space:]]*$/) { has_b=1; in_b=1 }
            if ($0 ~ /^updated_at[[:space:]]*:/) { print "updated_at: \"" NOW "\""; next }
            print
            next
        }
        {
            if (!in_b) { print; next }
            if ($0 ~ /^[[:space:]]*-[[:space:]]*repo[[:space:]]*:/) {
                cur_repo = vof($0)
                print; next
            }
            if ($0 ~ /^[[:space:]]*name[[:space:]]*:/ && cur_repo != "") {
                if (cur_repo == REP && vof($0) == NAM) dup=1
                print; next
            }
            print
        }
        END {
            if (!has_b) { print "branches:"; emit_new() }
            else if (in_b && !emitted && !dup) emit_new()
            if (dup) exit 2
        }
      ' "${FILE}" > "${TMP}"
      rc=$?
      set -e
      if [ "${rc}" -eq 2 ]; then
        rm -f "${TMP}"
        echo "work-status: branch 已存在，跳过: ${B_REP}/${B_NAM}"
        exit 0
      elif [ "${rc}" -ne 0 ]; then
        rm -f "${TMP}"
        echo "work-status: 写入失败" >&2
        exit 1
      fi
      mv "${TMP}" "${FILE}"
      echo "work-status: 已登记分支: ${B_REP}/${B_NAM}（${B_ROL}，${B_SRC}）"
      exit 0
      ;;
    mark)
      [ $# -ge 3 ] || { echo "work-status: branch mark 需要 <repo> <name> cleaned" >&2; exit 2; }
      B_REP="$1"; B_NAM="$2"; B_FLAG="$3"
      [ "${B_FLAG}" = cleaned ] || { echo "work-status: branch mark 仅支持 cleaned" >&2; exit 2; }
      set +e
      awk -v REP="${B_REP}" -v NAM="${B_NAM}" -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" "${YAML_LIB}"'
        BEGIN { in_b=0; cur_repo=""; target=0; found=0; saw_cleaned=0 }
        /^[A-Za-z_][A-Za-z0-9_]*:/ {
            if (target && !saw_cleaned) print "    cleaned: true"
            if (in_b) { target=0; saw_cleaned=0 }
            in_b=0
            if ($0 ~ /^branches[[:space:]]*:/) in_b=1
            if ($0 ~ /^updated_at[[:space:]]*:/) { print "updated_at: \"" NOW "\""; next }
            print
            next
        }
        {
            if (!in_b) { print; next }
            if ($0 ~ /^[[:space:]]*-[[:space:]]*repo[[:space:]]*:/) {
                if (target && !saw_cleaned) print "    cleaned: true"
                cur_repo = vof($0); target=0; saw_cleaned=0
                print; next
            }
            if ($0 ~ /^[[:space:]]*name[[:space:]]*:/ && cur_repo != "") {
                if (cur_repo == REP && vof($0) == NAM) { target=1; found=1 }
                print; next
            }
            if (target && $0 ~ /^[[:space:]]*cleaned[[:space:]]*:/) {
                print "    cleaned: true"; saw_cleaned=1; next
            }
            print
        }
        END {
            if (target && !saw_cleaned) print "    cleaned: true"
            if (!found) exit 3
        }
      ' "${FILE}" > "${TMP}"
      rc=$?
      set -e
      if [ "${rc}" -eq 3 ]; then
        rm -f "${TMP}"
        echo "work-status: branch 条目不存在: ${B_REP}/${B_NAM}" >&2
        exit 3
      elif [ "${rc}" -ne 0 ]; then
        rm -f "${TMP}"
        echo "work-status: 写入失败" >&2
        exit 1
      fi
      mv "${TMP}" "${FILE}"
      echo "work-status: 已标记 cleaned: ${B_REP}/${B_NAM}"
      exit 0
      ;;
    rename)
      [ $# -ge 2 ] || { echo "work-status: branch rename 需要 <old-name> <new-name>" >&2; exit 2; }
      B_OLD="$1"; B_NEW="$2"
      awk -v OLD="${B_OLD}" -v NEW="${B_NEW}" -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" "${YAML_LIB}"'
        BEGIN { in_b = 0; n = 0 }
        /^[A-Za-z_][A-Za-z0-9_]*:/ {
            in_b = ($0 ~ /^branches[[:space:]]*:/)
            if ($0 ~ /^updated_at[[:space:]]*:/) { print "updated_at: \"" NOW "\""; next }
            print; next
        }
        {
            if (!in_b) { print; next }
            if ($0 ~ /^[[:space:]]*name[[:space:]]*:/ && vof($0) == OLD) {
                print "    name: \"" NEW "\""
                n++
                next
            }
            print
        }
        END { print "RENAMED=" n }
      ' "${FILE}" > "${TMP}" || { echo "work-status: 写入失败" >&2; exit 1; }
      mv "${TMP}" "${FILE}"
      exit 0
      ;;
    list)
      awk "${YAML_LIB}"'
        BEGIN { in_b=0; cur_repo=""; cur_name=""; cur_role=""; cur_src=""; cur_cln="false" }
        /^[A-Za-z_][A-Za-z0-9_]*:/ {
            if (in_b && cur_repo != "") { print cur_repo "|" cur_name "|" cur_role "|" cur_src "|" cur_cln; cur_repo="" }
            in_b=0
            if ($0 ~ /^branches[[:space:]]*:/) in_b=1
            next
        }
        {
            if (!in_b) next
            if ($0 ~ /^[[:space:]]*-[[:space:]]*repo[[:space:]]*:/) {
                if (cur_repo != "") print cur_repo "|" cur_name "|" cur_role "|" cur_src "|" cur_cln
                cur_repo=vof($0); cur_name=""; cur_role=""; cur_src=""; cur_cln="false"
                next
            }
            if (cur_repo != "") {
                if ($0 ~ /^[[:space:]]*name[[:space:]]*:/) { cur_name=vof($0); next }
                if ($0 ~ /^[[:space:]]*role[[:space:]]*:/) { cur_role=vof($0); next }
                if ($0 ~ /^[[:space:]]*source[[:space:]]*:/) { cur_src=vof($0); next }
                if ($0 ~ /^[[:space:]]*cleaned[[:space:]]*:/) { cur_cln=vof($0); next }
            }
        }
        END {
            if (in_b && cur_repo != "") print cur_repo "|" cur_name "|" cur_role "|" cur_src "|" cur_cln
        }
      ' "${FILE}"
      exit 0
      ;;
    *)
      echo "work-status: 未知 branch 子动作: ${BACT}（register|mark|list|rename）" >&2
      exit 2
      ;;
  esac
fi

if [ $# -lt 2 ] || [ $(( $# % 2 )) -ne 0 ]; then
  echo "work-status: set 需要成对的 key/value 参数" >&2
  exit 2
fi

HAS_UPDATED_AT=0
while [ $# -gt 0 ]; do
  k="$1"; v="$2"; shift 2
  case "${k}" in
    status|stage|task|next|updated_at|mr_url|meego|tech_doc_url|work_id|work_dir|branch) ;;
    progress.*) ;;
    *) echo "work-status: 未知 key: ${k}（允许 status|stage|task|next|updated_at|mr_url|meego|tech_doc_url|work_id|work_dir|branch|progress.<名称>）" >&2; exit 3 ;;
  esac
  if [ "${k}" = "updated_at" ]; then HAS_UPDATED_AT=1; fi
  printf '%s\t%s\n' "${k}" "${v}" >> "${PAIRS}"
done
if [ "${HAS_UPDATED_AT}" = "0" ]; then printf 'updated_at\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "${PAIRS}"; fi

awk -F'\t' "${YAML_LIB}"'
function fmt(v) {
  if (v == "true" || v == "false") return v
  return esc(v)
}
FNR==1 { fi++ }
fi==1 {
  n++
  pval[n] = $2
  if ($1 == "status" || $1 == "updated_at" || $1 == "mr_url" || $1 == "meego" || $1 == "tech_doc_url" \
      || $1 == "work_id" || $1 == "work_dir" || $1 == "branch") { blk[n] = ""; fld[n] = $1 }
  else if (substr($1, 1, 9) == "progress.") { blk[n] = "progress"; fld[n] = substr($1, 10) }
  else { blk[n] = "current"; fld[n] = $1 }
  next
}
fi==2 {
  if ($0 ~ /^[^ \t#][^:]*:[ \t]*$/) {
    cur = $0; sub(/:.*/, "", cur)
  } else if (cur != "") {
    for (i = 1; i <= n; i++)
      if (blk[i] == cur && $0 ~ "^[ \t]+" fld[i] ":") found[i] = 1
  }
  for (i = 1; i <= n; i++)
    if (blk[i] == "" && $0 ~ "^" fld[i] ":") found[i] = 1
  next
}
fi==3 {
  if ($0 ~ /^[^ \t#][^:]*:[ \t]*$/) {
    print $0
    cur = $0; sub(/:.*/, "", cur)
    for (i = 1; i <= n; i++)
      if (blk[i] == cur && !found[i] && !done[i]) { print "  " fld[i] ": " fmt(pval[i]); done[i] = 1 }
    next
  }
  replaced = 0
  for (i = 1; i <= n; i++) {
    if (done[i]) continue
    if (blk[i] == "" && $0 ~ "^" fld[i] ":") { print fld[i] ": " fmt(pval[i]); done[i] = 1; replaced = 1; break }
    if (blk[i] == cur && $0 ~ "^[ \t]+" fld[i] ":") { print "  " fld[i] ": " fmt(pval[i]); done[i] = 1; replaced = 1; break }
  }
  if (!replaced) print $0
  next
}
END {
  for (i = 1; i <= n; i++) {
    if (done[i]) continue
    if (blk[i] == "") { print fld[i] ": " fmt(pval[i]); done[i] = 1 }
  }
  for (i = 1; i <= n; i++) {
    if (done[i]) continue
    if (!blkout[blk[i]]++) print blk[i] ":"
    print "  " fld[i] ": " fmt(pval[i])
    done[i] = 1
  }
}
' "${PAIRS}" "${FILE}" "${FILE}" > "${TMP}" || { echo "work-status: 写入失败" >&2; exit 1; }

mv "${TMP}" "${FILE}"
exit 0
