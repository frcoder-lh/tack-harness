#!/bin/sh
# check-guidance.sh — 校验 guidance distilled 条目的落点文件是否仍然存在
#
# close 回写 guidance、evolution 固化后，落点文件可能在后续演进中被改名/删除，
# 导致 distilled 证据链悬空。本脚本扫描 status.yaml，核对落点路径。
#
# 落点格式（规范，见 harness/template/work-status.yaml）：
#     - id: "G-01"
#       status: "distilled"
#       落点: "harness/cmd/dev/code.md"      # 相对 $root，多落点空格分隔
#   - 规范「落点:」行中的路径失效 → ERROR，退出码 1（close 硬门禁）
#   - 旧格式条目（无「落点:」行，路径散见正文）失效 → WARN，仅提示升级格式
#   - distilled 但找不到任何落点路径 → WARN（可能漏填，请人工核对）
#
# Usage:
#   sh check-guidance.sh <root> [work_id]
#     不传 work_id：扫描 $root/space/*/status.yaml（evolution 全局审查用）
#     传 work_id  ：只扫 $root/space/<work_id>/status.yaml（close 单工作区用）
# Windows: powershell -ExecutionPolicy Bypass -File run.ps1 check-guidance <root> [work_id]
# 退出码: 0 无失效落点（WARN 不改变退出码）/ 1 存在规范失效落点 / 2 用法错误

ROOT="$1"
WORK_ID="$2"

if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
    echo "Error: tack space root not found: $ROOT" >&2
    echo "Usage: sh check-guidance.sh <root> [work_id]" >&2
    exit 2
fi

if [ -n "$WORK_ID" ]; then
    if [ ! -f "$ROOT/space/$WORK_ID/status.yaml" ]; then
        echo "Error: status.yaml not found: $ROOT/space/$WORK_ID/status.yaml" >&2
        exit 2
    fi
    FILES="$ROOT/space/$WORK_ID/status.yaml"
else
    FILES=$(find "$ROOT/space" -maxdepth 2 -name status.yaml -type f 2>/dev/null)
fi

if [ -z "$FILES" ]; then
    echo "check-guidance: 无 status.yaml，跳过"
    exit 0
fi

TMP_OUT="${TMPDIR:-/tmp}/check-guidance.$$.txt"
trap 'rm -f "$TMP_OUT"' EXIT INT TERM
: > "$TMP_OUT"

for f in $FILES; do
    awk -v ROOT="$ROOT" -v F="$f" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function val(line, key,   v) {
        v = line
        sub(/^[^:]*:/, "", v)
        v = trim(v)
        sub(/[[:space:]]*#.*$/, "", v)
        v = trim(v)
        gsub(/^"|"$/, "", v)
        return v
    }
    # 刷新上一个条目：distilled 时核对其落点
    function flush(   s, p, found, norm, cmd) {
        if (cur_id == "") return
        if (cur_status == "distilled") {
            norm = (cur_landing != "")
            s = (norm ? cur_landing : cur_text)
            found = 0
            while (match(s, /[A-Za-z0-9_./-]+\.(md|sh|yaml|yml)/)) {
                p = substr(s, RSTART, RLENGTH)
                found = 1
                cmd = "test -e \"" ROOT "/" p "\""
                if (system(cmd) != 0) {
                    if (norm)
                        print "BROKEN\t" F "\t" cur_id "\t" p
                    else
                        print "OLDFMT\t" F "\t" cur_id "\t" p
                }
                s = substr(s, RSTART + RLENGTH)
            }
            if (!found) print "NOLAND\t" F "\t" cur_id "\t-"
        }
        cur_id = ""; cur_status = ""; cur_landing = ""; cur_text = ""
    }
    BEGIN { in_g = 0; cur_id = ""; cur_status = ""; cur_landing = ""; cur_text = "" }
    {
        line = $0
        # 跳过注释行（模板中 guidance 下的字段说明全是注释）
        if (line ~ /^[[:space:]]*#/) next

        # guidance 区进入/离开（顶层键）
        if (line ~ /^guidance[[:space:]]*:/) { in_g = 1; next }
        if (line ~ /^[A-Za-z_][A-Za-z0-9_]*:/) { if (in_g) { flush(); in_g = 0 }; next }
        if (!in_g) next

        # 新条目开始
        if (line ~ /^[[:space:]]*-[[:space:]]*id[[:space:]]*:/) {
            flush()
            idline = line
            sub(/^[[:space:]]*-[[:space:]]*/, "", idline)
            cur_id = val(idline, "id")
            next
        }

        if (cur_id != "") {
            cur_text = cur_text "\n" line
            if (line ~ /^[[:space:]]*status[[:space:]]*:/) cur_status = val(line, "status")
            if (index(line, "落点:") > 0) {
                lp = line
                sub(/^[^:]*:/, "", lp)
                cur_landing = trim(lp)
            }
        }
    }
    END { flush() }
    ' "$f"
done > "$TMP_OUT"

BROKEN_N=$(grep -c '^BROKEN' "$TMP_OUT" 2>/dev/null || true); BROKEN_N=${BROKEN_N:-0}
OLD_N=$(grep -c '^OLDFMT' "$TMP_OUT" 2>/dev/null || true); OLD_N=${OLD_N:-0}
NOLAND_N=$(grep -c '^NOLAND' "$TMP_OUT" 2>/dev/null || true); NOLAND_N=${NOLAND_N:-0}

if [ "$BROKEN_N" -gt 0 ]; then
    echo "check-guidance: ${BROKEN_N} 个 distilled 条目的规范落点文件不存在（已失效）：" >&2
    grep '^BROKEN' "$TMP_OUT" | while IFS="$(printf '\t')" read -r _ f id p; do
        echo "  BROKEN  $f  $id -> $p" >&2
    done
    echo "请补回落点文件或更正「落点:」路径后重试；不要删除 guidance 来源条目。" >&2
fi
if [ "$OLD_N" -gt 0 ]; then
    echo "check-guidance: ${OLD_N} 个旧格式 distilled 条目的落点路径不存在（WARN，请升级为「落点:」行）："
    grep '^OLDFMT' "$TMP_OUT" | while IFS="$(printf '\t')" read -r _ f id p; do
        echo "  OLDFMT  $f  $id -> $p"
    done
fi
if [ "$NOLAND_N" -gt 0 ]; then
    echo "check-guidance: ${NOLAND_N} 个 distilled 条目缺少落点路径（WARN，请补填「落点:」）："
    grep '^NOLAND' "$TMP_OUT" | while IFS="$(printf '\t')" read -r _ f id _p; do
        echo "  NOLAND  $f  $id"
    done
fi

if [ "$BROKEN_N" -eq 0 ] && [ "$OLD_N" -eq 0 ] && [ "$NOLAND_N" -eq 0 ]; then
    echo "check-guidance: distilled 落点全部有效"
fi
[ "$BROKEN_N" -gt 0 ] && exit 1
exit 0
