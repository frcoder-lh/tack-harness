#!/bin/sh
# work-status.sh — 确定性回写工作区 status.yaml 的常用字段
#
# 用法: sh work-status.sh <status.yaml> set <key> <value> [<key> <value> ...]
#   key 取值:
#     status            顶层 status 字段（工作流状态机取值）
#     stage|task|next   current 区块下的 stage/task/next
#     progress.<名称>   progress 区块下的布尔开关（值 true/false）
#     updated_at        顶层 updated_at（一般不显式传；每次执行自动刷新为当前时间）
# 行为:
#   - 字段已存在则就地更新；缺失则插入对应区块头部（顶层缺失则追加到文件末尾）
#   - 每次执行自动刷新 updated_at（显式传入时以传入值为准）
#   - 字符串值一律双引号包裹（与模板风格一致）；true/false 不加引号
# 退出码: 0 成功；1 文件不存在或写入失败；2 用法错误；3 未知 key
#
# 最小用例:
#   sh work-status.sh space/20261001-feat-x/status.yaml set status planning stage spec next "生成并确认 spec.md"
#   sh work-status.sh space/20261001-feat-x/status.yaml set progress.spec true

set -e

if [ $# -lt 4 ]; then
  echo "work-status: 用法: sh work-status.sh <status.yaml> set <key> <value> [key value ...]" >&2
  exit 2
fi
FILE="$1"; shift
if [ "$1" != "set" ]; then
  echo "work-status: 仅支持 set 子命令" >&2
  exit 2
fi
shift
if [ ! -f "$FILE" ]; then
  echo "work-status: 文件不存在: $FILE" >&2
  exit 1
fi
if [ $(( $# % 2 )) -ne 0 ]; then
  echo "work-status: key/value 必须成对出现" >&2
  exit 2
fi

# 临时文件优先放 tack 空间 .tack/tmp/（不写系统 temp，退出即清）；
# 仅当 FILE 不在规范空间布局内（<root>/space/<workspace>/status.yaml）时回退系统临时目录
SPACE_ROOT="$(cd "$(dirname "$FILE")/../.." 2>/dev/null && pwd)" || SPACE_ROOT=""
TMP_DIR=""
if [ -n "$SPACE_ROOT" ] && [ -d "$SPACE_ROOT/harness" ]; then
    TMP_DIR="$SPACE_ROOT/.tack/tmp"
    mkdir -p "$TMP_DIR" 2>/dev/null || TMP_DIR=""
fi
if [ -n "$TMP_DIR" ]; then
    PAIRS="$TMP_DIR/work-status.$$.pairs"
    TMP="$TMP_DIR/work-status.$$.out"
else
    PAIRS="$(mktemp)"
    TMP="$(mktemp)"
fi
trap 'rm -f "$PAIRS" "$TMP"; rmdir "$TMP_DIR" 2>/dev/null || true' EXIT HUP INT TERM

HAS_UPDATED_AT=0
while [ $# -gt 0 ]; do
  k="$1"; v="$2"; shift 2
  case "$k" in
    status|stage|task|next|updated_at) ;;
    progress.*) ;;
    *) echo "work-status: 未知 key: $k（允许 status|stage|task|next|updated_at|progress.<名称>）" >&2; exit 3 ;;
  esac
  if [ "$k" = "updated_at" ]; then HAS_UPDATED_AT=1; fi
  printf '%s\t%s\n' "$k" "$v" >> "$PAIRS"
done
if [ "$HAS_UPDATED_AT" = "0" ]; then printf 'updated_at\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$PAIRS"; fi

awk -F'\t' '
function fmt(v) {
  if (v == "true" || v == "false") return v
  gsub(/"/, "\\\"", v)
  return "\"" v "\""
}
ARGIND==1 {
  n++
  val[n] = $2
  if ($1 == "status" || $1 == "updated_at") { blk[n] = ""; fld[n] = $1 }
  else if (substr($1, 1, 9) == "progress.") { blk[n] = "progress"; fld[n] = substr($1, 10) }
  else { blk[n] = "current"; fld[n] = $1 }
  next
}
ARGIND==2 {
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
ARGIND==3 {
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
' "$PAIRS" "$FILE" "$FILE" > "$TMP" || { echo "work-status: 写入失败" >&2; exit 1; }

mv "$TMP" "$FILE"
exit 0
