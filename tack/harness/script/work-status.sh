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
# 用法: sh work-status.sh <status.yaml> guidance <id> <distilled|dismissed> [落点路径 ...]
#   - distilled: 置该条 status，并写/更新「落点:」行（须给 ≥1 个落点，相对 $root，空格分隔）
#   - dismissed: 仅置该条 status（不接受落点参数）
#   - 条目（guidance 区块内 - id: "<id>"）不存在时退出码 3
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
  echo "  sh work-status.sh <status.yaml> guidance <id> <distilled|dismissed> [落点路径 ...]" >&2
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
  set|guidance) ;;
  *)
    echo "work-status: 未知子命令: ${SUBCMD}（支持 set / guidance）" >&2
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
