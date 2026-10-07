#!/bin/sh
# lint-harness.sh — harness 结构自检（evolution/record 落盘前后的硬门禁）
#
# 检查项：
#   E（ERROR，退出码 1，必须修复）
#     1. workflow/cmd/agents frontmatter 结构损坏：首行非 ---（缺失）或有开头无
#        结束 ---（未闭合，字段检查会因此失察）；以及必需字段缺失
#        - workflow 文件: workflow / triggers / summary
#        - cmd 文件:     command  / triggers / summary
#        - agents 文件:  agent    / triggers / summary
#     2. 名称字段与文件名不一致（如文件 foo.md 但 command: bar）
#     3. cmd 四段正文缺失：前置准入条件 / 指令内容 / 后置完成检验 / 下一步建议
#     4. 名称、short、triggers 词条在 workflow+cmd 之间冲突（scan-routes 会多命中）
#   W（WARN，仅提示，不改变退出码）
#     1. short 缺失（可选但建议有）
#     2. reference/*.md 未被任何 cmd/workflow/agents/rule 文件引用（孤儿）
#
# agents/ 不参与命令路由：其名称/short/triggers 不做冲突检测。
# 文件名以 _ 开头的私有文件跳过。
#
# Usage:
#   sh lint-harness.sh <harness-dir>
# Windows: powershell -ExecutionPolicy Bypass -File run.ps1 lint-harness <harness-dir>
# 退出码: 0 无 ERROR（允许有 WARN）/ 1 存在 ERROR / 2 用法错误

HARNESS_DIR="$1"

if [ -z "$HARNESS_DIR" ] || [ ! -d "$HARNESS_DIR" ]; then
    echo "Error: harness dir not found: $HARNESS_DIR" >&2
    echo "Usage: sh lint-harness.sh <harness-dir>" >&2
    exit 2
fi

FILES=""
for f in "$HARNESS_DIR/workflow"/*.md "$HARNESS_DIR/agents"/*.md \
         "$HARNESS_DIR/reference"/*.md "$HARNESS_DIR/rule"/*.md; do
    [ -f "$f" ] && FILES="$FILES $f"
done
if [ -d "$HARNESS_DIR/cmd" ]; then
    for g in $(ls -1 "$HARNESS_DIR/cmd" 2>/dev/null); do
        [ -d "$HARNESS_DIR/cmd/$g" ] || continue
        for f in "$HARNESS_DIR/cmd/$g"/*.md; do
            [ -f "$f" ] && FILES="$FILES $f"
        done
    done
fi

[ -z "$FILES" ] && FILES="/dev/null"

awk -v H="$HARNESS_DIR" '
function ltrim(s) { sub(/^[[:space:]]+/, "", s); return s }
function rtrim(s) { sub(/[[:space:]]+$/, "", s); return s }
function trim(s)  { return ltrim(rtrim(s)) }
function basename(path,   n, a) { n = split(path, a, "/"); return a[n] }
function parent(path,   n, a)   { n = split(path, a, "/"); return a[n-1] }
function grandp(path,   n, a)   { n = split(path, a, "/"); return a[n-2] }
function stem(path,   b) { b = basename(path); sub(/\.md$/, "", b); return b }
function relpath(file,   r) { r = file; sub("^" H "/", "", r); return r }

function fval(line, key) {
    if (index(line, key ":") == 1) return trim(substr(line, length(key) + 2))
    return ""
}

function err(file, msg)  { n_err++; print "ERROR [" relpath(file) "] " msg }
function warn(file, msg) { n_warn++; print "WARN  [" relpath(file) "] " msg }

# 登记路由 token（仅 workflow/cmd）；重复即冲突
function register(kind, token, file,   key) {
    if (token == "") return
    key = kind "|" tolower(token)
    if (key in tok_owner) {
        err(file, kind " \x27" token "\x27 与 " relpath(tok_owner[key]) " 冲突（scan-routes 会多命中）")
    } else {
        tok_owner[key] = file
    }
}

# 独立句柄读全文：解析 frontmatter、cmd 四段标题，并把正文累积进 allbody
function inspect(file,   bn, d1, d2, kind, namefield, fence, line, v,
                       namev, shortv, trigv, summv, sec, m, i, parts) {
    bn = basename(file)
    if (substr(bn, 1, 1) == "_") return
    d1 = parent(file); d2 = grandp(file)
    if (d1 == "workflow")      { kind = "workflow"; namefield = "workflow" }
    else if (d2 == "cmd")      { kind = "cmd";      namefield = "command" }
    else if (d1 == "agents")  { kind = "agent";    namefield = "agent" }
    else if (d1 == "reference"){ kind = "reference"; namefield = "" }
    else if (d1 == "rule")     { kind = "rule";     namefield = "" }
    else return

    fence = 0
    nline = 0
    first_is_fence = 0
    while ((getline line < file) > 0) {
        nline++
        if (nline == 1 && line ~ /^---[[:space:]]*$/) first_is_fence = 1
        if (line ~ /^---[[:space:]]*$/) { fence++; if (fence >= 2) break; continue }
        if (fence == 1) {
            v = fval(line, "workflow"); if (v != "") namev = v
            v = fval(line, "command");  if (v != "") namev = v
            v = fval(line, "agent");    if (v != "") namev = v
            v = fval(line, "short");    if (v != "") shortv = v
            v = fval(line, "triggers"); if (v != "") trigv = v
            v = fval(line, "summary");  if (v != "") summv = v
        }
    }
    close(file)

    if (kind == "reference") { refs[stem(file) ".md"] = file; }

    # 全文二次读取：cmd 四段检测 + 正文累积（reference 自身不进 allbody）
    if (kind == "cmd") {
        sec["前置准入条件"] = 0; sec["指令内容"] = 0
        sec["后置完成检验"] = 0; sec["下一步建议"] = 0
        has_mode = 0
    }
    while ((getline line < file) > 0) {
        if (kind != "reference") allbody = allbody "\n" line
        if (kind == "cmd" && line ~ /^##[[:space:]]+/) {
            t = line; sub(/^##[[:space:]]+/, "", t); t = trim(t)
            if (t in sec) sec[t] = 1
            if (line ~ /^##[[:space:]]+模式/) has_mode = 1
        }
    }
    close(file)

    if (kind == "reference" || kind == "rule") return

    # frontmatter 完整性：首行须为 ---，且必须有结束 ---（结束缺失时正文会被误当字段区）
    if (nline > 0 && !first_is_fence)
        err(file, "缺少 frontmatter（文件首行须为 \x27---\x27）")
    else if (first_is_fence && fence == 1)
        err(file, "frontmatter 未闭合（缺少结束行 \x27---\x27）")

    # 必需字段
    if (namev == "") {
        err(file, "缺少 frontmatter 字段 \x27" namefield "\x27")
    } else if (kind == "workflow") {
        # workflow 文件名允许 <name>.md 或 <name>-workflow.md 两种约定
        if (namev != stem(file) && namev "-workflow" != stem(file))
            err(file, "workflow \x27" namev "\x27 与文件名 \x27" stem(file) ".md\x27 不一致（允许 <name>.md 或 <name>-workflow.md）")
    } else if (namev != stem(file)) {
        err(file, namefield " \x27" namev "\x27 与文件名 \x27" stem(file) ".md\x27 不一致")
    }
    if (trigv == "") err(file, "缺少 frontmatter 字段 \x27triggers\x27（语义路由需要）")
    if (summv == "") err(file, "缺少 frontmatter 字段 \x27summary\x27（须含做什么+何时用）")
    if (shortv == "") warn(file, "缺少可选字段 \x27short\x27（简写，建议补充）")

    # cmd 四段正文（「指令内容」允许由「## 模式N：…」多模式结构替代）
    if (kind == "cmd") {
        for (t in sec) {
            if (t == "指令内容") continue
            if (!sec[t]) err(file, "缺少正文章节 \x27## " t "\x27（命令四段契约）")
        }
        if (!sec["指令内容"] && !has_mode)
            err(file, "缺少正文章节 \x27## 指令内容\x27（多模式命令可改为 \x27## 模式N：…\x27 结构）")
    }

    # 路由 token 唯一性（agents 不参与）
    if (kind == "workflow" || kind == "cmd") {
        register("名称", namev, file)
        if (shortv != "") register("简写", shortv, file)
        m = split(trigv, parts, ",")
        for (i = 1; i <= m; i++) if (trim(parts[i]) != "") register("触发词", trim(parts[i]), file)
    }
}

BEGIN { n_err = 0; n_warn = 0; allbody = "" }

FNR == 1 { inspect(FILENAME) }

END {
    # reference 孤儿检测：任何 cmd/workflow/agents/rule 文本中出现 <name>.md 即视为被引用
    for (r in refs) {
        if (index(allbody, r) == 0) warn(refs[r], "reference 未被任何 cmd/workflow/agents/rule 引用（孤儿文件）")
    }

    print "lint-harness: " (n_err + 0) " error(s), " (n_warn + 0) " warning(s)"
    if (n_err > 0) exit 1
    exit 0
}
' $FILES
