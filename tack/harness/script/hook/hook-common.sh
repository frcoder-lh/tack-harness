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
    LC_ALL=C grep -qF "${_TACK_HOOK_MARK}" "$1" 2>/dev/null
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
    [ -n "${_dr}" ] || return 1
    while [ "${_dr}" != "." ] && [ "${_dr}" != "/" ] && [ "${_dr}" != "" ]; do
        if [ -f "${_dr}/AGENTS.md" ] && hook_grep_mark "${_dr}/AGENTS.md"; then
            printf '%s' "${_dr}"
            return 0
        fi
        _parent=$(dirname "${_dr}" 2>/dev/null) || return 1
        [ "${_parent}" = "${_dr}" ] && break
        _dr="${_parent}"
    done
    if [ "${_dr}" = "/" ] && [ -f "/AGENTS.md" ] && hook_grep_mark /AGENTS.md; then
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
        [ -f "${_f}" ] || continue
        _st=$(hook_yaml_top "${_f}" status)
        [ "${_st}" = "completed" ] && continue
        _ts=$(hook_yaml_top "${_f}" updated_at)
        _found="${_found}${_ts}|$(dirname "${_f}")
"
    done
    [ -n "${_found}" ] || return 1
    printf '%s' "${_found}" | sort -r | head -n 1 | sed 's/^[^|]*|//'
}

# ── 工作区解析（无状态：一律以当次 payload 的 cwd 为事实起点）──────────────────
#
# 不向环境变量缓存任何路径：多项目窗口、同空间多工作区并行时，会话级缓存
# 无法表达「当前这次调用属于哪个空间/工作区」；而缓存校验只能验证其自身仍
# 有效（目录还在、状态非 completed），无法验证与当次 cwd 的从属关系——只要
# 缓存指向的空间/工作区本身没消失，错配就不会触发回退。每次 hook 调用的
# payload 都带真实 cwd，root 向上探测、work 按路径归属精确判定，开销仅几次
# stat/grep（毫秒级），空间迁移、工作区关闭、多窗口并发下天然正确，无需
# 任何失效回退逻辑。

# hook_work_from_cwd <root> <start-dir>
# 纯路径归属精确判定：start-dir 位于 <root>/space/<name>/ 内（含恰为该目录），
# 且 status.yaml 存在、状态非 completed，stdout 输出该工作区绝对路径；
# 不归属任何活跃工作区时无输出、返回 1（不做任何扫描，高频路径适用）。
hook_work_from_cwd() {
    _wc_root="$(printf '%s' "${1:-}" | tr '\\' '/')"
    _wc_dir="$(printf '%s' "${2:-}" | tr '\\' '/')"
    [ -n "${_wc_root}" ] && [ -n "${_wc_dir}" ] || return 1
    case "${_wc_dir}" in
        "${_wc_root}"/space/*)
            _wc_rest="${_wc_dir#"${_wc_root}"/space/}"
            _wc_name="${_wc_rest%%/*}"
            _wc_cand="${_wc_root}/space/${_wc_name}"
            if [ -n "${_wc_name}" ] && [ -f "${_wc_cand}/status.yaml" ] \
                && [ "$(hook_yaml_top "${_wc_cand}/status.yaml" status)" != "completed" ]; then
                printf '%s' "${_wc_cand}"
                return 0
            fi
            ;;
    esac
    return 1
}

# hook_detect_work <root> <start-dir>
# 先按 cwd 精确命中工作区；cwd 不在任何活跃工作区内（如空间根、worktree 外）
# 时回退 hook_active_work（最近活跃，仅供会话启动/提示场景，调用方仍须向用户
# 确认当前工作）。
hook_detect_work() {
    hook_work_from_cwd "$1" "$2" || hook_active_work "$1"
}

# hook_work_snapshot <work-dir>
# 输出工作区状态快照（供注入模型）：status/workflow + current 三件套
hook_work_snapshot() {
    _sf="$1/status.yaml"
    [ -f "${_sf}" ] || return 1
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
    }' "${_sf}"
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

# ── 统一 Hook 日志（环境变量 TACK_HOOK_LOG=1 开启；默认关闭，零开销、零行为变化）────
#
# 三个事件脚本在解析完 CWD 后统一调用 hook_log_setup 接入，一次调用记录：
#   时间 / 事件名 / pid / cwd / 环境（TACK_HOOK_LOG、TACK_HOOK_ENFORCE 开关）/
#   输入 payload 全文 / $root、$work / 过程备注（如 PreToolUse 规则命中）/
#   输出全文 / rc / 输出字节数 / 耗时（秒）
#
# 落点：$root/.tack/log/hook.log（.tack/ 不入库、可随时清理）；探测不到 tack
#   空间时回退 ${TMPDIR:-/tmp}/tack-hook.log，供排查「空间外为何不生效」。
#
# 两条铁律：
#   1. 日志只写文件、任何异常静默吞掉，绝不写 stdout/stderr——hook 注入文本与
#      deny JSON 必须与不开日志时逐字节一致（stdout 先落临时缓冲，退出 trap 中
#      恢复原 stdout 后原样回放）
#   2. 一次调用的记录先写本次专属缓冲，收尾时单次 append——多个 hook 进程并发时
#      日志块不相互穿插

_HL_EVENT=""
_HL_PAYLOAD=""
_HL_EXTRA=""
_HL_ROOT=""
_HL_WORK=""
_HL_CTX=0
_HL_ROOT_DONE=""
_HL_WORK_DONE=""
_HOOKLOG=""
_HL_OUT=""
_HL_T0=""

# hook_log_enabled — 仅 TACK_HOOK_LOG=1 开启（未设置/其他值均关闭）
hook_log_enabled() {
    [ "${TACK_HOOK_LOG:-}" = "1" ]
}

# hook_log_ts — 本地时间戳（与 .tack/log 其他日志同格式）
hook_log_ts() {
    date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf -- '-'
}

# hook_log_block <file> — 给文件每一行加 "  | " 前缀，作为日志多行块输出
hook_log_block() {
    [ -f "$1" ] || return 0
    awk '{ print "  | " $0 }' "$1" 2>/dev/null
}

# hook_log_setup <event> <payload-file> [extra-tmp-file]
# 注册退出清理 trap（开关关闭也注册，接管事件脚本的临时文件清理）；开关开启时
# 额外创建日志缓冲与 stdout 缓冲、重定向 stdout、写入 begin 块。
# 必须在 CWD 解析之后、任何 stdout 产出之前调用。
hook_log_setup() {
    _HL_EVENT="$1"
    _HL_PAYLOAD="$2"
    _HL_EXTRA="${3:-}"
    if hook_log_enabled; then
        _HOOKLOG="$(mktemp 2>/dev/null)" || _HOOKLOG=""
        _HL_OUT="$(mktemp 2>/dev/null)" || _HL_OUT=""
        _HL_T0="$(date '+%s' 2>/dev/null)" || _HL_T0=""
        if [ -n "${_HOOKLOG}" ]; then
            {
                printf '===== %s event=%s pid=%s phase=begin =====\n' \
                    "$(hook_log_ts)" "${_HL_EVENT}" "$$"
                printf 'cwd: %s\n' "${CWD:-}"
                printf 'env: TACK_HOOK_LOG=%s TACK_HOOK_ENFORCE=%s\n' \
                    "${TACK_HOOK_LOG:-}" "${TACK_HOOK_ENFORCE:-}"
                printf 'input.payload:\n'
                hook_log_block "${_HL_PAYLOAD}"
            } >> "${_HOOKLOG}" 2>/dev/null || true
        fi
        if [ -n "${_HL_OUT}" ]; then
            # 保存宿主 stdout 到 fd3，后续 stdout 全部进缓冲，cleanup 中回放
            exec 3>&1
            exec >"${_HL_OUT}"
        fi
    fi
    trap _hook_log_cleanup EXIT HUP INT TERM
}

# hook_log_ctx <root> [work] — 空间探测后补记 $root/$work；可重复调用：
# ROOT 刚探到时先调一次，WORK 探到后再调一次。仅落盘新拿到的非空字段，
# 空串视为「尚不知道」，不覆盖、不落盘；始终缺省的字段由 finish 补 <none>。
hook_log_ctx() {
    [ -n "${1:-}" ] && _HL_ROOT="$1"
    [ -n "${2:-}" ] && _HL_WORK="$2"
    if [ -n "${_HL_ROOT}" ] || [ -n "${_HL_WORK}" ]; then
        _HL_CTX=1
    fi
    [ -n "${_HOOKLOG}" ] || return 0
    if [ -n "${_HL_ROOT}" ] && [ -z "${_HL_ROOT_DONE}" ]; then
        _HL_ROOT_DONE=1
        printf 'root: %s\n' "${_HL_ROOT}" >> "${_HOOKLOG}" 2>/dev/null || true
    fi
    if [ -n "${_HL_WORK}" ] && [ -z "${_HL_WORK_DONE}" ]; then
        _HL_WORK_DONE=1
        printf 'work: %s\n' "${_HL_WORK}" >> "${_HOOKLOG}" 2>/dev/null || true
    fi
}

# hook_log_note <text> — 追加过程备注（如 PreToolUse 规则命中原因）
hook_log_note() {
    [ -n "${_HOOKLOG}" ] || return 0
    printf '%s\n' "$*" >> "${_HOOKLOG}" 2>/dev/null || true
}

# hook_log_finish <rc> — 追加输出块并把本次缓冲一次性落盘（须在 stdout 恢复后调用）
hook_log_finish() {
    [ -n "${_HOOKLOG}" ] || return 0
    _rc="${1:-0}"
    # 上下文缺省字段补 <none>：ctx 从未生效（ROOT 探测前早退）两行都补；
    # 已在 tack 空间但无活跃工作区则只补 work
    if [ "${_HL_CTX}" -eq 0 ]; then
        {
            printf 'root: <none>\n'
            printf 'work: <none>\n'
        } >> "${_HOOKLOG}" 2>/dev/null || true
    else
        [ -n "${_HL_WORK_DONE}" ] || printf 'work: <none>\n' >> "${_HOOKLOG}" 2>/dev/null || true
    fi
    _t1="$(date '+%s' 2>/dev/null)" || _t1=""
    if [ -n "${_HL_T0}" ] && [ -n "${_t1}" ]; then
        _dur="$((_t1 - _HL_T0))s"
    else
        _dur="?"
    fi
    _bytes=0
    if [ -f "${_HL_OUT}" ]; then
        _bytes=$(wc -c < "${_HL_OUT}" 2>/dev/null | tr -d '[:space:]')
    fi
    {
        printf 'output: rc=%s bytes=%s duration=%s\n' "${_rc}" "${_bytes:-0}" "${_dur}"
        hook_log_block "${_HL_OUT}"
        printf '===== %s event=%s pid=%s phase=end =====\n\n' \
            "$(hook_log_ts)" "${_HL_EVENT}" "$$"
    } >> "${_HOOKLOG}" 2>/dev/null || true
    if [ -n "${_HL_ROOT}" ] && mkdir -p "${_HL_ROOT}/.tack/log" 2>/dev/null; then
        _logf="${_HL_ROOT}/.tack/log/hook.log"
    else
        # 无 root 或日志目录创建失败（权限等）：回退系统临时目录，绝不因日志报错
        _logf="${TMPDIR:-/tmp}/tack-hook.log"
    fi
    hook_log_append "${_HOOKLOG}" "${_logf}"
}

# hook_log_append <src> <dst> — 互斥串行化追加：多个 hook 进程并发退出时
# （如同一轮并行工具调用触发多个 PreToolUse），保证整块日志不交错。
# mkdir 在 POSIX 下原子创建，充当自旋锁；约 1s 拿不到锁则兜底直写（宁交错不丢日志）。
# 进程被强杀可能残留 .lock 目录，只影响后来者的等待时间，不阻断写入。
hook_log_append() {
    _la_src="$1"
    _la_dst="$2"
    _la_lock="${_la_dst}.lock"
    _la_i=0
    while ! mkdir "${_la_lock}" 2>/dev/null; do
        _la_i=$((_la_i + 1))
        if [ "${_la_i}" -ge 50 ]; then
            _la_i=-1
            break
        fi
        sleep 0.02 2>/dev/null || { _la_i=-1; break; }
    done
    cat "${_la_src}" >> "${_la_dst}" 2>/dev/null || true
    [ "${_la_i}" -ge 0 ] && rmdir "${_la_lock}" 2>/dev/null || true
}

# _hook_log_cleanup — EXIT/信号统一清理：先恢复 stdout 并原样回放，再落盘日志
_hook_log_cleanup() {
    _HL_RC=$?
    trap - EXIT HUP INT TERM
    if [ -n "${_HL_OUT}" ]; then
        exec 1>&3 3>&- 2>/dev/null || true
        cat "${_HL_OUT}" 2>/dev/null || true
    fi
    [ -n "${_HOOKLOG}" ] && hook_log_finish "${_HL_RC}"
    rm -f "${_HL_PAYLOAD}" 2>/dev/null || true
    [ -n "${_HL_EXTRA}" ] && rm -f "${_HL_EXTRA}" 2>/dev/null
    rm -f "${_HOOKLOG}" "${_HL_OUT}" 2>/dev/null || true
    exit "${_HL_RC}"
}
