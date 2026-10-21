#!/bin/sh
# run-plan.sh — run 清单只读检查（不执行任何脚本）
#
# 机器可读清单冻结格式：位于 <run-dir>/run.md 的
#   <!-- run-plan:start --> 与 <!-- run-plan:end --> 之间，
#   Tab 分隔五列，首行为固定表头：
#     seq	script	command	deps	requires
#   - seq:      执行顺序（正整数，按文件顺序严格递增）
#   - script:   相对 <run-dir> 的脚本路径
#   - command:  实际运行命令（原样保留，不由本脚本执行）
#   - deps:     前置步骤 seq，逗号分隔；必须存在且小于当前 seq；无依赖留空
#   - requires: 相对 <run-dir> 的必需文件（通常为 local/ 下凭据），逗号分隔；无则留空
#
# Usage:
#   sh run-plan.sh check <run-dir>
#
# 输出:
#   ERROR<TAB>code<TAB>seq<TAB>detail   校验失败项（seq 未知时为 -）
#   成功时输出 run-plan: ok (N steps)
#
# 退出码: 0 校验通过；1 run 目录/run.md 不存在；2 用法错误；
#         3 未找到机器可读清单块；4 清单结构、顺序或依赖非法

set -eu

ACTION="${1:-}"
RUN_DIR="${2:-}"

usage() {
    echo "Usage: sh run-plan.sh check <run-dir>" >&2
}

[ "${ACTION}" = "check" ] && [ -n "${RUN_DIR}" ] || { usage; exit 2; }
if [ ! -d "${RUN_DIR}" ]; then
    echo "Error: run dir not found: ${RUN_DIR}" >&2
    exit 1
fi
RUN_MD="${RUN_DIR}/run.md"
if [ ! -f "${RUN_MD}" ]; then
    echo "Error: run.md not found: ${RUN_MD}" >&2
    exit 1
fi

TMP="$(mktemp "${TMPDIR:-/tmp}/tack-run-plan.XXXXXX")"
trap 'rm -f "${TMP}"' EXIT HUP INT TERM

set +e
awk '
    index($0, "<!-- run-plan:start -->") > 0 { inb = 1; seen = 1; next }
    index($0, "<!-- run-plan:end -->") > 0 { if (inb) closed = 1; inb = 0; next }
    inb { print }
    END {
        if (!seen) exit 3
        if (!closed) exit 4
    }
' "${RUN_MD}" > "${TMP}"
extract_rc=$?
set -e
if [ "${extract_rc}" -eq 3 ]; then
    echo "Error: 未找到机器可读清单块（<!-- run-plan:start/end -->）: ${RUN_MD}" >&2
    exit 3
elif [ "${extract_rc}" -eq 4 ]; then
    echo "Error: 机器可读清单块未闭合: ${RUN_MD}" >&2
    exit 4
elif [ "${extract_rc}" -ne 0 ]; then
    echo "Error: 读取 run.md 失败" >&2
    exit 1
fi

set +e
# 路径经 awk -v 传入时，Windows 反斜杠会被当作转义序列（如 \U、\T）；统一转成正斜杠
RUN_AWK="$(printf '%s' "${RUN_DIR}" | tr '\\' '/')"
awk -F"$(printf '\t')" -v RUN="${RUN_AWK}" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function err(code, step, detail) {
        printf "ERROR\t%s\t%s\t%s\n", code, (step == "" ? "-" : step), detail
        bad = 1
    }
    function safe_path(p) {
        if (p == "" || p ~ /^\// || p ~ /\.\./) return 0
        if (p ~ /[[:space:]]/) return 0
        return 1
    }
    function split_list(s, arr,   n, i) {
        s = trim(s)
        if (s == "" || s == "-") return 0
        n = split(s, arr, ",")
        for (i = 1; i <= n; i++) arr[i] = trim(arr[i])
        return n
    }
    BEGIN { n = 0; hdr = 0; bad = 0 }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    {
        if (!hdr) {
            if ($0 != "seq\tscript\tcommand\tdeps\trequires") {
                err("bad-header", "-", "首行必须为 seq<TAB>script<TAB>command<TAB>deps<TAB>requires")
                hdr = 2
                exit 4
            }
            hdr = 1
            next
        }
        if (NF != 5) { err("bad-columns", trim($1), "期望 5 列，实际 " NF " 列"); next }
        step[++n] = trim($1)
        script[n] = trim($2)
        command[n] = trim($3)
        deps[n] = trim($4)
        req[n] = trim($5)
    }
    END {
        if (hdr == 0) { err("missing-header", "-", "清单只有标记、没有表头"); exit 4 }
        prev = 0
        for (i = 1; i <= n; i++) {
            s = step[i]
            if (s !~ /^[0-9]+$/ || s + 0 <= 0) { err("bad-seq", s, "seq 必须是正整数"); continue }
            if (s + 0 <= prev) err("order", s, "seq 必须严格递增")
            prev = s + 0
            if (s in seen_seq) err("duplicate-seq", s, "seq 重复")
            seen_seq[s] = 1
            order[s] = i
            if (script[i] == "") err("missing-script", s, "script 不能为空")
            if (command[i] == "") err("missing-command", s, "command 不能为空")
            if (script[i] != "" && !safe_path(script[i]))
                err("bad-path", s, "script 必须是 run/ 下的相对路径且不含空白/..")
            if (script[i] != "" && safe_path(script[i])) {
                cmd = "test -f \"" RUN "/" script[i] "\""
                if (system(cmd) != 0) err("missing-script-file", s, script[i])
            }
            k = split_list(req[i], rr)
            for (j = 1; j <= k; j++) {
                if (!safe_path(rr[j])) { err("bad-path", s, "requires 路径非法: " rr[j]); continue }
                cmd = "test -e \"" RUN "/" rr[j] "\""
                if (system(cmd) != 0) err("missing-requires", s, rr[j])
            }
        }
        # 依赖引用只能指向已出现且更早的 seq
        for (i = 1; i <= n; i++) {
            k = split_list(deps[i], dd)
            for (j = 1; j <= k; j++) {
                d = dd[j]
                if (d !~ /^[0-9]+$/) { err("bad-dep", step[i], "deps 必须是 seq 列表: " d); continue }
                if (!(d in seen_seq)) { err("unknown-dep", step[i], "依赖不存在的 seq: " d); continue }
                if (d + 0 >= step[i] + 0) err("order-dep", step[i], "依赖必须早于当前步骤: " d)
            }
        }
        if (bad) exit 4
        printf "run-plan: ok (%d steps)\n", n
        exit 0
    }
' "${TMP}"
plan_rc=$?
set -e
exit "${plan_rc}"
