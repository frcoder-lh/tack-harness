#!/bin/sh
# trigger-extract.sh — 从工作区目的描述提取切换用触发词候选
#
# Usage:
#   sh trigger-extract.sh "<description>"
#
# 输出：一行逗号分隔的候选触发词（去停用词、去单字、中英文分别处理后合并去重）
#   - 中文：先去掉通用后缀（功能/模块/系统/服务/需求/页面/接口/流程/能力/平台），
#           4 字及以上纯中文短语额外给出首、尾两字核心词（按 UTF-8 3 字节字符切分）
#   - 英文：小写化，按空白与标点切分，去掉常见停用词
# 退出码: 0 成功（无候选时输出空行）；2 用法错误
#
# 最小用例:
#   sh trigger-extract.sh "用户登录功能"            # 用户登录,用户,登录
#   sh trigger-extract.sh "optimize checkout flow"  # optimize,checkout,flow
#
# 说明：脚本只产出候选，最终触发词由 AI 按语义筛选并补充遗漏项（见 work 命令第 3 步）。

set -eu

DESC="${1:-}"
if [ -z "${DESC}" ]; then
    echo "Usage: sh trigger-extract.sh <description>" >&2
    exit 2
fi

printf '%s' "${DESC}" \
    | tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C awk '
function add(w) {
    if (w == "" || (w in seen)) return
    seen[w] = 1
    out[++n] = w
}
function strip_suffix(w,    prev) {
    do {
        prev = w
        sub(/功能$/, "", w)
        sub(/模块$/, "", w)
        sub(/系统$/, "", w)
        sub(/服务$/, "", w)
        sub(/需求$/, "", w)
        sub(/页面$/, "", w)
        sub(/接口$/, "", w)
        sub(/流程$/, "", w)
        sub(/能力$/, "", w)
        sub(/平台$/, "", w)
    } while (w != prev)
    return w
}
BEGIN {
    split("the a an is are was were be been being of to for and or in on at by with from as it this that these those we you our your they their i me my", tmp, " ")
    for (k in tmp) stop[tmp[k]] = 1
    n = 0
}
{
    line = $0
    gsub(/[[:punct:]]+/, " ", line)
    gsub(/、|，|。|；|：|！|？|（|）|【|】|「|」|《|》|…|—|～|·/, " ", line)
    m = split(line, tok, /[[:space:]]+/)
    for (i = 1; i <= m; i++) {
        w = tok[i]
        if (w == "") continue
        if (w ~ /^[a-z0-9]+$/) {
            if (length(w) > 1 && !(w in stop)) add(w)
            continue
        }
        w = strip_suffix(w)
        sub(/^(的|了|在|是|和|与|及|或|等|把|从|对)/, "", w)
        sub(/(的|了|在|是|和|与|及|或|等)$/, "", w)
        if (length(w) >= 6) add(w)
        if (length(w) >= 12 && w !~ /[a-z0-9]/) {
            add(substr(w, 1, 6))
            add(substr(w, length(w) - 5, 6))
        }
    }
}
END {
    line = ""
    for (i = 1; i <= n; i++) line = (i == 1 ? out[i] : line "," out[i])
    print line
}
'
