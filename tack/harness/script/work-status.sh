#!/bin/sh
# work-status.sh — 确定性回写工作区 status.yaml 的常用字段
#
# 用法: sh work-status.sh <status.yaml> set <key> <value> [<key> <value> ...]
#   key 取值:
#     status            顶层 status 字段（工作流状态机取值）
#     stage|task|next   current 区块下的 stage/task/next
#     progress.<名称>   progress 区块下的布尔开关（值 true/false）
#     updated_at        顶层 updated_at（一般不显式传；每次执行自动刷新为当前时间）
#
# 用法: sh work-status.sh <status.yaml> guidance <id> <distilled|dismissed> [落点路径 ..]
#   - distilled: 置该条 status，并写/更新「落点:」行（须给 ≥1 个落点，相对 $root，空格分隔）
#   - dismissed: 仅置该条 status（不接受落点参数）
#   - 条目（guidance 区块内 - id: "<id>"）不存在时退出码 3
#
# 用法: sh work-status.sh <status.yaml> branch register <repo> <name> <role> <source>
#   - 往 branches 列表追加一条（同 repo+name 已存在则跳过，退出码 0）
#   - role: main（工作区主分支）/ tmp（临时分支）；source: work / worktree / branch-op / rename
# 用法: sh work-status.sh <status.yaml> branch mark <repo> <name> cleaned
#   - 置匹配条目的 cleaned: true（条目不存在时退出码 3）
# 用法: sh work-status.sh <status.yaml> branch list
#   - 输出 branches 列表，每行一条：repo|name|role|source|merged|cleaned（供 close 遍历）
#
# 行为:
#   - 字段已存在则就地更新；缺失则插入对应区块头部（顶层缺失则追加到文件末尾）
#   - 每次执行自动刷新 updated_at（显式传入时以传入值为准）
#   - 字符串值一律双引号包裹（与模板风格一致）；true/false 不加引号
# 退出码: 0 成功；1 文件不存在或写入失败；2 用法错误；3 未知 key / guidance 条目不存在
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
  echo "  sh work-status.sh <status.yaml> branch register <repo> <name> <role> <source>" >&2
  echo "  sh work-status.sh <status.yaml> branch mark <repo> <name> cleaned" >&2
  echo "  sh work-status.sh <status.yaml> branch list" >&2
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
  set|guidance|branch) ;;
  *)
    echo "work-status: 未知子命令: ${SUBCMD}（支持 set / guidance / branch）" >&2
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
    PAIRS="$(mktemp)"
    TMP="$(mktemp)"
fi
trap 'rm -f "${PAIRS}" "${TMP}"; rmdir "${TMP_DIR}" 2>/dev/null || true' EXIT HUP INT TERM

# guidance 子命令：固化结论回写（distilled 写「落点:」行；dismissed 仅置状态）
if [ "${SUBCMD}" = "guidance" ]; then
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
  if awk -v GID="${GID}" -v GSTATE="${GSTATE}" -v GLAND="${GLAND}" -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" '
    function vof(line,   v) {
        v = line; sub(/^[^:]*:/, "", v)
        sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
        sub(/[[:space:]]*#.*$/, "", v)
        sub(/^[[:space:]]+$/, "", v)
        gsub(/^"|"$/, "", v)
        return v
    }
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
      awk -v REP="${B_REP}" -v NAM="${B_NAM}" -v ROL="${B_ROL}" -v SRC="${B_SRC}" -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" '
        function vof(line,   v) {
            v = line; sub(/^[^:]*:/, "", v)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            sub(/[[:space:]]*#.*$/, "", v)
            gsub(/^"|"$/, "", v)
            return v
        }
        function emit_new() {
            print "  - repo: \"" REP "\""
            print "    name: \"" NAM "\""
            print "    role: \"" ROL "\""
            print "    source: \"" SRC "\""
            print "    merged: false"
            print "    cleaned: false"
        }
        BEGIN { in_b=0; cur_repo=""; found=0 }
        /^[A-Za-z_][A-Za-z0-9_]*:/ {
            if (in_b && !found) { emit_new(); found=1 }
            in_b=0
            if ($0 ~ /^branches[[:space:]]*:[[:space:]]*\[\][[:space:]]*$/) {
                print "branches:"
                if (!found) { emit_new(); found=1 }
                in_b=1
                next
            }
            if ($0 ~ /^branches[[:space:]]*:[[:space:]]*$/) in_b=1
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
                if (cur_repo == REP && vof($0) == NAM) found=1
                print; next
            }
            print
        }
        END {
            if (in_b && !found) emit_new()
            if (found) exit 2
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
      awk -v REP="${B_REP}" -v NAM="${B_NAM}" -v NOW="$(date '+%Y-%m-%d %H:%M:%S')" '
        function vof(line,   v) {
            v = line; sub(/^[^:]*:/, "", v)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            sub(/[[:space:]]*#.*$/, "", v)
            gsub(/^"|"$/, "", v)
            return v
        }
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
    list)
      awk '
        function vof(line,   v) {
            v = line; sub(/^[^:]*:/, "", v)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            sub(/[[:space:]]*#.*$/, "", v)
            gsub(/^"|"$/, "", v)
            return v
        }
        BEGIN { in_b=0; cur_repo=""; cur_name=""; cur_role=""; cur_src=""; cur_mrg="false"; cur_cln="false"; has=0 }
        /^[A-Za-z_][A-Za-z0-9_]*:/ {
            if (in_b && cur_repo != "") { print cur_repo "|" cur_name "|" cur_role "|" cur_src "|" cur_mrg "|" cur_cln; cur_repo="" }
            in_b=0
            if ($0 ~ /^branches[[:space:]]*:/) in_b=1
            next
        }
        {
            if (!in_b) next
            if ($0 ~ /^[[:space:]]*-[[:space:]]*repo[[:space:]]*:/) {
                if (cur_repo != "") print cur_repo "|" cur_name "|" cur_role "|" cur_src "|" cur_mrg "|" cur_cln
                cur_repo=vof($0); cur_name=""; cur_role=""; cur_src=""; cur_mrg="false"; cur_cln="false"; has=1
                next
            }
            if (cur_repo != "") {
                if ($0 ~ /^[[:space:]]*name[[:space:]]*:/) { cur_name=vof($0); next }
                if ($0 ~ /^[[:space:]]*role[[:space:]]*:/) { cur_role=vof($0); next }
                if ($0 ~ /^[[:space:]]*source[[:space:]]*:/) { cur_src=vof($0); next }
                if ($0 ~ /^[[:space:]]*merged[[:space:]]*:/) { cur_mrg=vof($0); next }
                if ($0 ~ /^[[:space:]]*cleaned[[:space:]]*:/) { cur_cln=vof($0); next }
            }
        }
        END {
            if (in_b && cur_repo != "") print cur_repo "|" cur_name "|" cur_role "|" cur_src "|" cur_mrg "|" cur_cln
        }
      ' "${FILE}"
      exit 0
      ;;
    *)
      echo "work-status: 未知 branch 子动作: ${BACT}（register|mark|list）" >&2
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
    status|stage|task|next|updated_at) ;;
    progress.*) ;;
    *) echo "work-status: 未知 key: ${k}（允许 status|stage|task|next|updated_at|progress.<名称>）" >&2; exit 3 ;;
  esac
  if [ "${k}" = "updated_at" ]; then HAS_UPDATED_AT=1; fi
  printf '%s\t%s\n' "${k}" "${v}" >> "${PAIRS}"
done
if [ "${HAS_UPDATED_AT}" = "0" ]; then printf 'updated_at\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "${PAIRS}"; fi

awk -F'\t' '
function fmt(v) {
  if (v == "true" || v == "false") return v
  gsub(/"/, "\\\"", v)
  return "\"" v "\""
}
FNR==1 { fi++ }
fi==1 {
  n++
  val[n] = $2
  if ($1 == "status" || $1 == "updated_at") { blk[n] = ""; fld[n] = $1 }
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
      if (blk[i] == cur && !found[i] && !done[i]) { print "  " fld[i] ": " fmt(val[i]); done[i] = 1 }
    next
  }
  replaced = 0
  for (i = 1; i <= n; i++) {
    if (done[i]) continue
    if (blk[i] == "" && $0 ~ "^" fld[i] ":") { print fld[i] ": " fmt(val[i]); done[i] = 1; replaced = 1; break }
    if (blk[i] == cur && $0 ~ "^[ \t]+" fld[i] ":") { print "  " fld[i] ": " fmt(val[i]); done[i] = 1; replaced = 1; break }
  }
  if (!replaced) print $0
  next
}
END {
  for (i = 1; i <= n; i++) {
    if (done[i]) continue
    if (blk[i] == "") { print fld[i] ": " fmt(val[i]); done[i] = 1 }
  }
  for (i = 1; i <= n; i++) {
    if (done[i]) continue
    if (!blkout[blk[i]]++) print blk[i] ":"
    print "  " fld[i] ": " fmt(val[i])
    done[i] = 1
  }
}
' "${PAIRS}" "${FILE}" "${FILE}" > "${TMP}" || { echo "work-status: 写入失败" >&2; exit 1; }

mv "${TMP}" "${FILE}"
exit 0
