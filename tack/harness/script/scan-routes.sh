#!/bin/sh
# scan-routes.sh — 扫描 harness 目录，动态生成「工作流 + 命令」路由（依赖注入的核心）
#
# 约定：
#   - 工作流是 <harness-dir>/workflow/*.md，front matter 字段：
#       workflow: development          # 工作流名
#       short:    dev                  # 简写（可选）
#       triggers: 开发工作流, dev       # 中英文触发词，逗号分隔
#       summary:  一句话作用
#   - 命令是 <harness-dir>/cmd/<group>/*.md，front matter 字段：
#       command:  init                 # 命令名
#       short:    i                    # 简写（可选）
#       triggers: 初始化, init         # 中英文触发词，逗号分隔
#       params:   [项目描述]           # 参数说明（可选）
#       summary:  初始化项目空间与仓库  # 一句话作用
#   - 可委派角色是 <harness-dir>/agents/*.md，front matter 字段：
#       agent:    code-explorer       # 角色名
#       short:    explorer            # 简写（可选）
#       triggers: 代码探索, explore    # 语义触发词，逗号分隔（仅供人工/语义参考）
#       tools:    Read, Grep          # 指令性工具边界（可选，运行时不强制）
#       summary:  何时委派这个角色     # 一句话作用（须含「做什么 + 何时用」）
#     角色只供发现与委派，不参与 resolve 路由匹配（不会与命令重名冲突）。
#   - group: base（项目空间）/ dev（需求开发）/ git（Git），也允许用户自定义新分组
#   - 文件名以 _ 开头的是私有文件，不参与路由/发现
#
# 性能：扫描、解析、匹配全部在单个 awk 进程内完成（避免在 Windows 上为每个
#       字段/文件启动数十上百个子进程）。
#
# Usage:
#   sh scan-routes.sh list      <harness-dir>             # 工作流表 + 全部命令表 + 角色表
#   sh scan-routes.sh workflows <harness-dir>             # 只输出工作流路由表（供意图识别）
#   sh scan-routes.sh commands  <harness-dir>             # 只输出命令路由表
#   sh scan-routes.sh agents    <harness-dir>             # 只输出可委派角色表
#   sh scan-routes.sh resolve   <harness-dir> <keyword>   # 解析触发词（仅 workflow/cmd）
#                                                         # 输出: workflow|-|<file>|... 或 cmd|<group>|<file>|...
#                                                         # 退出码: 0 唯一命中 / 1 无命中 / 2 多个命中

ACTION="${1:-list}"
HARNESS_DIR="$2"

if [ -z "$HARNESS_DIR" ] || [ ! -d "$HARNESS_DIR" ]; then
    echo "Error: harness dir not found: $HARNESS_DIR" >&2
    echo "Usage: sh scan-routes.sh <list|workflows|commands|agents|resolve> <harness-dir> [keyword]" >&2
    exit 1
fi

# 固定分组顺序，其余自定义分组按名称排序追加
GROUP_ORDER="base dev git"

# 按「workflow → base/dev/git → 其余自定义分组」的顺序构造文件列表
FILES=""
# 1) 工作流
for f in "$HARNESS_DIR/workflow"/*.md; do
    [ -f "$f" ] && FILES="$FILES $f"
done
# 2) 命令：固定分组
for g in $GROUP_ORDER; do
    [ -d "$HARNESS_DIR/cmd/$g" ] || continue
    for f in "$HARNESS_DIR/cmd/$g"/*.md; do
        [ -f "$f" ] && FILES="$FILES $f"
    done
done
# 3) 命令：自定义分组
for g in $(ls -1 "$HARNESS_DIR/cmd" 2>/dev/null); do
    [ -d "$HARNESS_DIR/cmd/$g" ] || continue
    echo "$GROUP_ORDER" | tr ' ' '\n' | grep -qx "$g" && continue
    for f in "$HARNESS_DIR/cmd/$g"/*.md; do
        [ -f "$f" ] && FILES="$FILES $f"
    done
done
# 4) 可委派角色（只供 list/agents 发现，不参与 resolve）
for f in "$HARNESS_DIR/agents"/*.md; do
    [ -f "$f" ] && FILES="$FILES $f"
done

AWK_PROG='
function ltrim(s) { sub(/^[[:space:]]+/, "", s); return s }
function rtrim(s) { sub(/[[:space:]]+$/, "", s); return s }
function trim(s)  { return ltrim(rtrim(s)) }
function basename(path,   n, a) { n = split(path, a, "/"); return a[n] }
function parent(path,   n, a)   { n = split(path, a, "/"); return a[n-1] }
function grandp(path,   n, a)   { n = split(path, a, "/"); return a[n-2] }

# 从 front matter 行中取 key 的值
function fval(line, key) {
    if (index(line, key ":") == 1) {
        return trim(substr(line, length(key) + 2))
    }
    return ""
}

# 解析单个 md 文件，产出一条 8 字段路由行写入 entries；无效文件跳过
function parse(file,   bn, d1, d2, type, group, name, shortv, trig, paramsv, summ, fence, line, v) {
    bn = basename(file)
    if (substr(bn, 1, 1) == "_") return
    d1 = parent(file); d2 = grandp(file)
    if (d1 == "workflow") { type = "workflow"; group = "-" }
    else if (d2 == "cmd") { type = "cmd"; group = d1 }
    else if (d1 == "agents") { type = "agent"; group = "-" }
    else return

    fence = 0
    while ((getline line < file) > 0) {
        if (line ~ /^---[[:space:]]*$/) {
            fence++
            if (fence >= 2) break
            continue
        }
        if (fence != 1) continue
        if (type == "workflow") { v = fval(line, "workflow"); if (v != "") name = v }
        else if (type == "cmd") { v = fval(line, "command");  if (v != "") name = v }
        else                   { v = fval(line, "agent");    if (v != "") name = v }
        v = fval(line, "short");    if (v != "") shortv = v
        v = fval(line, "triggers"); if (v != "") trig = v
        v = fval(line, "params");   if (v != "") paramsv = v
        v = fval(line, "summary");  if (v != "") summ = v
    }
    close(file)
    if (name == "") return

    n_ent++
    ent_type[n_ent] = type; ent_group[n_ent] = group; ent_file[n_ent] = file
    ent_name[n_ent] = name; ent_short[n_ent] = shortv; ent_trig[n_ent] = trig
    ent_params[n_ent] = paramsv; ent_summ[n_ent] = summ
}

function relpath(file,   r) {
    r = file
    sub("^" H "/", "", r)
    return r
}

function glabel(g) {
    if (g == "base") return "项目空间 (base)"
    if (g == "dev")  return "需求开发 (dev)"
    if (g == "git")  return "Git (git)"
    return g
}

function dash(v) { return (v == "" ? "—" : v) }

# 渲染某一类型的表（workflow：5 列；cmd：按分组 6 列）
function render_wf(   i, printed) {
    printed = 0
    for (i = 1; i <= n_ent; i++) {
        if (ent_type[i] != "workflow") continue
        if (!printed) {
            print "## 工作流 (workflow)"
            print ""
            print "| 工作流 | 简写 | 触发词 | 作用 | 文件 |"
            print "|--------|------|--------|------|------|"
            printed = 1
        }
        print "| " ent_name[i] " | " dash(ent_short[i]) " | " ent_trig[i] " | " ent_summ[i] " | " relpath(ent_file[i]) " |"
    }
    if (printed) print ""
}

function render_cmd(   g, i, printed) {
    # 按出现顺序渲染分组（entries 已按固定分组顺序构造）
    for (gidx = 1; gidx <= n_grp; gidx++) {
        g = grp_order[gidx]
        printed = 0
        for (i = 1; i <= n_ent; i++) {
            if (ent_type[i] != "cmd" || ent_group[i] != g) continue
            if (!printed) {
                print "## " glabel(g)
                print ""
                print "| 命令 | 简写 | 触发词 | 参数 | 作用 | 文件 |"
                print "|------|------|--------|------|------|------|"
                printed = 1
            }
            print "| " ent_name[i] " | " dash(ent_short[i]) " | " ent_trig[i] " | " dash(ent_params[i]) " | " ent_summ[i] " | " relpath(ent_file[i]) " |"
        }
        if (printed) print ""
    }
}

# 渲染可委派角色表（5 列，同 workflow）
function render_agents(   i, printed) {
    printed = 0
    for (i = 1; i <= n_ent; i++) {
        if (ent_type[i] != "agent") continue
        if (!printed) {
            print "## 可委派角色 (agents)"
            print ""
            print "| 角色 | 简写 | 触发词 | 作用 | 文件 |"
            print "|------|------|--------|------|------|"
            printed = 1
        }
        print "| " ent_name[i] " | " dash(ent_short[i]) " | " ent_trig[i] " | " ent_summ[i] " | " relpath(ent_file[i]) " |"
    }
    if (printed) print ""
}

BEGIN {
    n_ent = 0; n_grp = 0
}

FNR == 1 { parse(FILENAME) }   # 每个文件只在首行触发一次（parse 内用独立句柄读全文）

END {
    # 记录命令分组的实际顺序（去重，保持文件出现顺序）
    for (i = 1; i <= n_ent; i++) {
        if (ent_type[i] != "cmd") continue
        g = ent_group[i]; seen = 0
        for (j = 1; j <= n_grp; j++) if (grp_order[j] == g) seen = 1
        if (!seen) { n_grp++; grp_order[n_grp] = g }
    }

    if (MODE == "list") {
        print "# 路由表（由 scan-routes.sh 扫描 harness/workflow、harness/cmd 与 harness/agents 自动生成）"
        print ""
        render_wf()
        render_cmd()
        render_agents()
        print "> 在 workflow/、cmd/ 或 agents/ 目录新增/修改文件后路由表自动更新，无需改动 skill。"
        print "> agents/ 下的角色仅供委派发现，不参与 resolve 路由匹配。"
        exit 0
    }
    if (MODE == "workflows") { render_wf(); exit 0 }
    if (MODE == "commands")  { render_cmd(); exit 0 }
    if (MODE == "agents")    { render_agents(); exit 0 }

    if (MODE == "resolve") {
        if (KEYWORD == "") { print "Error: resolve 需要传入 keyword" > "/dev/stderr"; exit 1 }
        kw = tolower(KEYWORD)
        exact_n = 0; fuzzy_n = 0
        delete exact; delete fuzzy
        for (i = 1; i <= n_ent; i++) {
            if (ent_type[i] == "agent") continue   # 角色不参与命令/工作流路由
            nm = tolower(ent_name[i]); sh = tolower(ent_short[i]); tg = tolower(ent_trig[i])
            hit = (kw == nm)
            if (!hit && sh != "" && kw == sh) hit = 1
            if (!hit) {
                m = split(tg, parts, ",")
                for (k = 1; k <= m; k++) {
                    if (kw == tolower(trim(parts[k]))) { hit = 1; break }
                }
            }
            line = ent_type[i] "|" ent_group[i] "|" ent_file[i] "|" ent_name[i] "|" ent_short[i] "|" ent_trig[i] "|" ent_params[i] "|" ent_summ[i]
            if (hit) { exact_n++; exact[exact_n] = line }
            else if (index(nm "|" tg, kw) > 0) { fuzzy_n++; fuzzy[fuzzy_n] = line }
        }
        if (exact_n == 1) { print exact[1]; exit 0 }
        if (exact_n > 1) {
            print "多个路由匹配 \x27" KEYWORD "\x27，请使用更精确的触发词：" > "/dev/stderr"
            for (i = 1; i <= exact_n; i++) print exact[i] > "/dev/stderr"
            exit 2
        }
        if (fuzzy_n == 1) { print fuzzy[1]; exit 0 }
        if (fuzzy_n > 1) {
            print "多个路由与 \x27" KEYWORD "\x27 相似，请补充触发词：" > "/dev/stderr"
            for (i = 1; i <= fuzzy_n; i++) print fuzzy[i] > "/dev/stderr"
            exit 2
        }
        print "未找到匹配 \x27" KEYWORD "\x27 的工作流或命令" > "/dev/stderr"
        exit 1
    }

    print "Error: 未知动作（支持 list / workflows / commands / agents / resolve）" > "/dev/stderr"
    exit 1
}
'

# 无任何文件时给 awk 喂 /dev/null，避免其挂起读 stdin
if [ -z "$FILES" ]; then
    FILES="/dev/null"
fi

if [ "$ACTION" = "resolve" ]; then
    # awk 以退出码表达命中结果（0/1/2），需绕开 set -e
    set +e
    awk -v MODE=resolve -v H="$HARNESS_DIR" -v KEYWORD="$3" "$AWK_PROG" $FILES
    rc=$?
    exit $rc
fi

case "$ACTION" in
    list)      awk -v MODE=list      -v H="$HARNESS_DIR" "$AWK_PROG" $FILES ;;
    workflows) awk -v MODE=workflows -v H="$HARNESS_DIR" "$AWK_PROG" $FILES ;;
    commands)  awk -v MODE=commands  -v H="$HARNESS_DIR" "$AWK_PROG" $FILES ;;
    agents)    awk -v MODE=agents    -v H="$HARNESS_DIR" "$AWK_PROG" $FILES ;;
    *) echo "Error: 未知动作 '$ACTION'（支持 list / workflows / commands / agents / resolve）" >&2; exit 1 ;;
esac
