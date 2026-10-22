# yamlib.awk — tack 受控 YAML 子集的共享标量/行内列表函数（POSIX awk）
#
# 支持范围：双引号/单引号/裸标量、行尾注释、行内序列与 CSV、双引号输出。
# 本库不承诺解析任意 YAML；调用脚本负责区块边界和缩进层级。

function yaml_ltrim(s) { sub(/^[[:space:]]+/, "", s); return s }
function yaml_rtrim(s) { sub(/[[:space:]]+$/, "", s); return s }
function yaml_trim(s) { return yaml_ltrim(yaml_rtrim(s)) }

# 去除双引号外的行尾注释。# 位于引号内或未由空白分隔时保留。
function yaml_strip_comment(s,    i, c, prev, quote, escaped, out) {
    quote = ""; escaped = 0; out = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        prev = (i > 1 ? substr(s, i - 1, 1) : "")
        if (escaped) { out = out c; escaped = 0; continue }
        if (quote == "\"" && c == "\\") { out = out c; escaped = 1; continue }
        if (c == "\"" || c == "\047") {
            if (quote == c) quote = ""
            else if (quote == "") quote = c
            out = out c; continue
        }
        if (c == "#" && quote == "" && (i == 1 || prev ~ /[[:space:]]/)) break
        out = out c
    }
    return yaml_rtrim(out)
}

function yaml_unquote(s,    q) {
    s = yaml_trim(s)
    if (length(s) < 2) return s
    q = substr(s, 1, 1)
    if (substr(s, length(s), 1) != q || (q != "\"" && q != "\047")) return s
    s = substr(s, 2, length(s) - 2)
    if (q == "\"") {
        gsub(/\\"/, "\"", s)
        gsub(/\\\\/, "\\", s)
    } else {
        gsub(/\047\047/, "\047", s)
    }
    return s
}

function yaml_value(line,    v) {
    v = line
    sub(/^[^:]*:/, "", v)
    v = yaml_strip_comment(v)
    return yaml_unquote(v)
}

function yaml_key(line,    v) {
    v = line
    sub(/^[[:space:]]*-[[:space:]]*/, "", v)
    sub(/:.*/, "", v)
    return yaml_trim(v)
}

function yaml_escape(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    gsub(/\t/, "\\t", s)
    gsub(/\r/, "\\r", s)
    gsub(/\n/, "\\n", s)
    return s
}

function yaml_quote(s) { return "\"" yaml_escape(s) "\"" }

# 把 CSV 或 YAML 行内序列标准化为无引号 CSV。
function yaml_csv(v,    s, a, n, i, x, out) {
    s = yaml_trim(v)
    if (substr(s, 1, 1) == "[" && substr(s, length(s), 1) == "]")
        s = substr(s, 2, length(s) - 2)
    n = split(s, a, ","); out = ""
    for (i = 1; i <= n; i++) {
        x = yaml_unquote(yaml_trim(a[i]))
        if (x != "") out = (out == "" ? x : out "," x)
    }
    return out
}

function yaml_inline_list(csv,    n, a, i, x, out) {
    if (yaml_trim(csv) == "") return "[]"
    n = split(csv, a, ","); out = ""
    for (i = 1; i <= n; i++) {
        x = yaml_unquote(yaml_trim(a[i]))
        if (x == "") continue
        out = (out == "" ? "" : out ", ") yaml_quote(x)
    }
    return (out == "" ? "[]" : "[" out "]")
}

# 兼容核心脚本原有函数名，便于逐块迁移；实现只保留在本文件。
function trim(s) { return yaml_trim(s) }
function clean(s) { return yaml_unquote(yaml_trim(s)) }
function val(line) { return yaml_value(line) }
function vof(line) { return yaml_value(line) }
function norm_csv(v) { return yaml_csv(v) }
function inline_list(v) { return yaml_inline_list(v) }
function esc(v) { return yaml_quote(v) }
