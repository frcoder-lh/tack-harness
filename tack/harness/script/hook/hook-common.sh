#!/bin/sh
# hook-common.sh — tack hook 适配层公共函数库（被 on-*.sh 以 . 方式 source）
#
# 定位：agent 无关的「可选加速层」。本库与三个事件脚本只做确定性事实搬运
#   （空间探测、payload 解析、路由缓存、状态快照），不承载控制流、不做语义判断；
#   控制流与语义识别的唯一事实源始终是 $root/AGENTS.md 与 harness/cmd|workflow/。
#
# 铁律（防自锁，见 hook 设计约定）：
#   1. 任何内部异常都静默 exit 0、stdout 为空——hook 绝不能阻断用户会话
#   2. 非 tack 空间（向上找不到带空间标记的 AGENTS.md）一律零输出秒退
#   3. 只输出纯文本（SessionStart/UserPromptSubmit 自动注入）；PreToolUse
#      只有未来 TACK_HOOK_ENFORCE=1 时才输出 deny JSON，当前观察模式恒为空
#
# 依赖：POSIX sh + awk（与 scan-routes.sh 同一基线，Git for Windows / macOS 通用）

# tack 空间标记（与 AGENTS.md 第 3 行逐字一致，注意三处空格；
# 改标记时必须同步 SKILL.md 的探测说明）
_TACK_HOOK_MARK='本空间由 tack harness 驱动'

# hook_grep_mark <file> — 标记匹配统一走 C locale 纯字节比较：
# Git for Windows 的 GNU grep 3.0 在 zh_CN.UTF-8 下对中文模式行为不稳定，
# 模式与文件同为 UTF-8 字节时 LC_ALL=C 最可靠（macOS BSD grep 同样适用）
hook_grep_mark() {
    LC_ALL=C grep -qF "$_TACK_HOOK_MARK" "$1" 2>/dev/null
}

# hook_json_get <field> <payload-file> [occurrence]
# 从 hook stdin payload（JSON）中提取指定字符串字段的「值」（已做 JSON 反转义）。
# 只支持字符串值字段（cwd / prompt / tool_name / command / file_path 等）；
# occurrence 取第几个同名键（默认 1）——PreToolUse payload 中顶层 cwd 在前、
# tool_input.cwd 在后，可取第 2 个拿到命令执行目录。不引入完整 JSON 解析器。
hook_json_get() {
    awk -v F="$1" -v OCC="${3:-1}" '
    function hexval(ch,   H) {
        H="0123456789abcdef"
        return index(H, tolower(ch)) - 1
    }
    # 反转义 JSON 字符串内容（不含两侧引号）
    function unesc(s,   i, n, c, c2, hex, cp, out) {
        out=""; n=length(s); i=1
        while (i <= n) {
            c=substr(s, i, 1)
            if (c == "\\" && i < n) {
                c2=substr(s, i+1, 1)
                if (c2 == "u") {
                    hex=substr(s, i+2, 4)
                    if (length(hex) == 4 && hex ~ /^[0-9a-fA-F]{4}$/) {
                        cp=4096*hexval(substr(hex,1,1)) + 256*hexval(substr(hex,2,1)) \
                           + 16*hexval(substr(hex,3,1)) + hexval(substr(hex,4,1))
                        if (cp < 128) out=out sprintf("%c", cp)
                        else          out=out "\\u" hex   # 非 ASCII（含代理对）保留原转义；TRAE/Claude payload 内中文为原始 UTF-8，不走此路
                        i+=6; continue
                    }
                }
                if      (c2 == "n") out=out "\n"
                else if (c2 == "t") out=out "\t"
                else if (c2 == "r") out=out "\r"
                else if (c2 == "b") out=out "\b"
                else if (c2 == "f") out=out "\f"
                else                out=out c2
                i+=2; continue
            }
            out=out c; i++
        }
        return out
    }
    function is_ws(ch) { return (ch == " " || ch == "\t" || ch == "\n" || ch == "\r") }
    { text = text $0 ORS }
    END {
        n=length(text); i=1; hits=0
        while (i <= n) {
            c=substr(text, i, 1)
            if (c != "\"") { i++; continue }
            # 读取一个原始字符串 token（转义序列原样保留），右引号位置为 j
            j=i+1; buf=""
            while (j <= n) {
                cc=substr(text, j, 1)
                if (cc == "\\") { buf=buf substr(text, j, 2); j+=2; continue }
                if (cc == "\"") break
                buf=buf cc; j++
            }
            # 跳过右引号后的空白，判断是否为键（后跟冒号）
            k=j+1
            while (k <= n && is_ws(substr(text, k, 1))) k++
            if (substr(text, k, 1) != ":") { i=j+1; continue }
            if (unesc(buf) != F) { i=j+1; continue }
            # 命中目标键：取冒号后的字符串值
            v=k+1
            while (v <= n && is_ws(substr(text, v, 1))) v++
            if (substr(text, v, 1) != "\"") { i=j+1; continue }   # 非字符串值，继续找同名键
            vb=v+1; vbuf=""
            while (vb <= n) {
                vc=substr(text, vb, 1)
                if (vc == "\\") { vbuf=vbuf substr(text, vb, 2); vb+=2; continue }
                if (vc == "\"") break
                vbuf=vbuf vc; vb++
            }
            hits++
            if (hits == OCC) { printf "%s", unesc(vbuf); exit }
            i=j+1
        }
    }
    ' "$2"
}

# hook_detect_root <start-dir>
# 从起始目录向上查找首个「AGENTS.md 含空间标记」的目录，stdout 输出绝对路径。
# 兼容 Git Bash（/d/x、D:/x、反斜杠）；找不到无输出并返回 1。
hook_detect_root() {
    _dr=$(printf '%s' "$1" | tr '\\' '/')
    [ -n "$_dr" ] || return 1
    while [ "$_dr" != "." ] && [ "$_dr" != "/" ] && [ "$_dr" != "" ]; do
        if [ -f "$_dr/AGENTS.md" ] && hook_grep_mark "$_dr/AGENTS.md"; then
            printf '%s' "$_dr"
            return 0
        fi
        _parent=$(dirname "$_dr" 2>/dev/null) || return 1
        [ "$_parent" = "$_dr" ] && break
        _dr=$_parent
    done
    if [ "$_dr" = "/" ] && [ -f "/AGENTS.md" ] && hook_grep_mark /AGENTS.md; then
        printf '/'
        return 0
    fi
    return 1
}

# hook_yaml_top <file> <key>
# 读 status.yaml 顶层标量（去引号/去行尾注释/trim）
hook_yaml_top() {
    awk -v k="$2" '
    function trim(s) { sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
    $0 ~ "^" k ":[[:space:]]*" {
        line=$0; sub(/^[^:]*:/,"",line)
        sub(/[[:space:]]*#.*$/, "", line)
        line=trim(line); gsub(/^"|"$/, "", line)
        printf "%s", line; exit
    }' "$1"
}

# hook_active_work <root>
# 找出非 completed 的活跃工作区（多个时取 updated_at 最新），stdout 输出其绝对路径；
# 无活跃工作区时无输出、返回 1。
hook_active_work() {
    _found=""
    for _f in "$1"/space/*/status.yaml; do
        [ -f "$_f" ] || continue
        _st=$(hook_yaml_top "$_f" status)
        [ "$_st" = "completed" ] && continue
        _ts=$(hook_yaml_top "$_f" updated_at)
        _found="${_found}${_ts}|$(dirname "$_f")
"
    done
    [ -n "$_found" ] || return 1
    printf '%s' "$_found" | sort -r | head -n 1 | sed 's/^[^|]*|//'
}

# hook_work_snapshot <work-dir>
# 输出工作区状态快照（供注入模型）：status/workflow + current 三件套
hook_work_snapshot() {
    _sf="$1/status.yaml"
    [ -f "$_sf" ] || return 1
    awk '
    function trim(s) { sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
    function val(line,   v) {
        v=line; sub(/^[^:]*:/,"",v)
        sub(/[[:space:]]*#.*$/, "", v)
        v=trim(v); gsub(/^"|"$/, "", v); return v
    }
    /^status:[[:space:]]/   && st == ""  { st=val($0) }
    /^workflow:[[:space:]]/ && wf == ""  { wf=val($0) }
    /^current:[[:space:]]*$/             { inc=1; next }
    inc && /^[^[:space:]]/               { inc=0 }
    inc && /^[[:space:]]+stage:/         { stage=val($0) }
    inc && /^[[:space:]]+task:/          { task=val($0) }
    inc && /^[[:space:]]+next:/          { nxt=val($0) }
    END {
        print "  状态: " (st == "" ? "—" : st)
        print "  工作流: " (wf == "" ? "—" : wf)
        print "  当前环节: " (stage == "" ? "—" : stage)
        print "  当前任务: " (task == "" ? "—" : task)
        print "  下一步: " (nxt == "" ? "—" : nxt)
    }' "$_sf"
}

# hook_strip_frontmatter <file>
# 输出去掉 YAML front matter（首尾 --- 围栏之间）的正文；无围栏时输出全文
hook_strip_frontmatter() {
    awk '
    BEGIN { fence=0; body=0 }
    /^---[[:space:]]*$/ {
        if (body == 0) { fence++; if (fence >= 2) body=1; next }
    }
    body == 1 { print }
    ' "$1"
}

# hook_shq <string> — POSIX shell 单引号安全包裹
hook_shq() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}
