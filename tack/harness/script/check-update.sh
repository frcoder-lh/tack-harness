#!/bin/sh
# check-update.sh — tack 空间 harness 版本检查（自动更新提醒）
#
# 挂载点：close / evolution / record / help 命令收尾时调用（Windows 经 run.ps1 启动）；
# 不在会话加载路由时执行（避免与用户当前任务抢占注意力）。
# 内部双节流，默认对用户完全静默：
#   1. 时间节流：距上次真实检查不足 7 天，不发网络请求直接返回
#   2. 版本节流：同一新版本只提醒一次（下一个更新版本出现才再次提醒）
#
# Usage:
#   sh check-update.sh <root>
#
# 参数:
#   root   tack 空间根目录（读 AGENTS.md 项目信息区块 skill_version 与状态文件）
#
# 输出协议（AI 消费约定，见 close / evolution / record / help cmd）:
#   退出 0 且无输出       -> 无事发生，AI 不提及
#   退出 0 且 stdout 非空 -> 「有新版本」提醒（首行）+ 本次更新内容摘要（可能没有），
#                            AI 在原样转述后引导用户执行 update 命令
#   非零退出              -> 内部异常，AI 忽略，不向用户报错
#
# 版本事实源（依次回退）: AGENTS.md 项目信息区块 skill_version（project.sh 维护）->
#   本机已安装 skill 的 SKILL.md front matter version（探测逻辑与 skill-update.sh 一致）。
# 检查目标: <update-url>/releases/latest 的 302 重定向地址尾段（单次 HEAD 请求，
#   不走 GitHub API、无响应体）。变更说明取 <update-url>/raw/master/CHANGELOG.md
#   中「本机版本(不含)→最新版本」区间的全部版本段落。update-url 默认取出厂仓库地址，
#   环境变量 TACK_UPDATE_URL 可覆盖（隔离测试用）。
# 状态文件: <root>/.tack/state/update-state（本机运行时状态，.gitignore 已排除），行格式:
#   last_check=<epoch 秒>   上次发起真实检查的时间（含失败尝试）
#   notified=<tag>          已提醒过的版本

set -eu

CHECK_INTERVAL=604800   # 节流间隔：7 天（秒）
DEFAULT_UPDATE_URL="https://github.com/frcoder-lh/tack-harness"

usage() {
    sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
}

[ $# -eq 1 ] || { usage >&2; exit 1; }
case "$1" in
    -h|--help) usage; exit 0 ;;
esac
ROOT="$1"
[ -f "$ROOT/AGENTS.md" ] || { echo "错误：不是 tack 空间（缺 AGENTS.md）: $ROOT" >&2; exit 1; }

STATE="$ROOT/.tack/state/update-state"
UPDATE_URL="${TACK_UPDATE_URL:-$DEFAULT_UPDATE_URL}"

# 临时文件统一放空间 .tack/tmp/ 下的运行私有目录（不写系统 temp），退出即清；
# state 目录与临时目录一并确保存在（state 文件首次写入前父目录必须就位）
TMP_DIR="$ROOT/.tack/tmp/check-update.$$"
mkdir -p "$TMP_DIR" "$ROOT/.tack/state"
cleanup_tmp() { rm -rf "$TMP_DIR" 2>/dev/null || true; }
trap cleanup_tmp EXIT
trap 'cleanup_tmp; exit 130' INT
trap 'cleanup_tmp; exit 143' TERM

# now — 当前 epoch 秒（GNU/BSD date 通用）
now() { date +%s; }

# read_state <key> — 读状态文件中的一个 key 值，缺省为空
read_state() {
    [ -f "$STATE" ] || return 0
    sed -n "s/^$1=//p" "$STATE" | head -n 1
}

# write_state <key> <value> — 写入/更新状态文件的一个 key（保留其余行）
# 禁 sed -i：写临时文件 + mv（GNU/BSD 兼容）；临时文件在 TMP_DIR 内，退出统一清理
write_state() {
    _k="$1"; _v="$2"
    _tmp="$TMP_DIR/state"
    : > "$_tmp"
    if [ -f "$STATE" ]; then
        sed "/^${_k}=/d" "$STATE" > "$_tmp" || :
    fi
    printf '%s=%s\n' "$_k" "$_v" >> "$_tmp"
    mv "$_tmp" "$STATE"
}

# space_version — AGENTS.md 项目信息区块内的 skill_version（区块边界限定，防误伤正文）
space_version() {
    sed -n '/<!-- tack:info:start -->/,/<!-- tack:info:end -->/ s/^skill_version:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$ROOT/AGENTS.md" | head -n 1
}

# local_skill_version — 回退版本源：本机已安装 skill 的 SKILL.md front matter version
# 探测失败（零个/多个安装）返回非零，调用方静默放弃
local_skill_version() {
    _found=""
    for _agent in .trae-cn .trae .cursor .windsurf .cline .codeium .aider .devbox; do
        _dir="${HOME}/${_agent}/skills/tack"
        [ -f "$_dir/SKILL.md" ] || continue
        if [ -n "$_found" ]; then
            return 1
        fi
        _found="$_dir"
    done
    [ -n "$_found" ] || return 1
    sed -n '2,/^---$/ s/^version:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$_found/SKILL.md" | head -n 1
}

# seg_num — 取版本段的前导数字（容错 "9-beta" 类尾巴；非数字段计为 0）
seg_num() {
    _n=${1%%[!0-9]*}
    [ -n "$_n" ] || _n=0
    printf '%s' "$_n"
}

# version_gt <a> <b> — 语义化版本比较：a > b 时成功（V 前缀可省，逐段数字比较）
version_gt() {
    _a=${1#V}; _a=${_a#v}
    _b=${2#V}; _b=${_b#v}
    _oifs="$IFS"
    IFS=.
    set -- $_a
    _a1=$(seg_num "${1:-0}"); _a2=$(seg_num "${2:-0}"); _a3=$(seg_num "${3:-0}")
    set -- $_b
    IFS="$_oifs"
    _b1=$(seg_num "${1:-0}"); _b2=$(seg_num "${2:-0}"); _b3=$(seg_num "${3:-0}")
    if [ "$_a1" -gt "$_b1" ]; then return 0; fi
    if [ "$_a1" -lt "$_b1" ]; then return 1; fi
    if [ "$_a2" -gt "$_b2" ]; then return 0; fi
    if [ "$_a2" -lt "$_b2" ]; then return 1; fi
    [ "$_a3" -gt "$_b3" ]
}

# latest_tag — 取 releases/latest 的 302 重定向地址尾段 tag；失败返回非零
# curl 不带 -L（不跟随重定向），用 -w redirect_url 拿 302 目标；
# Windows Git Bash schannel 受限网络回退 --ssl-no-revoke；再回退 wget --spider
latest_tag() {
    _loc=""
    if command -v curl >/dev/null 2>&1; then
        _loc="$(curl -fsSI -o /dev/null -w '%{redirect_url}' "$UPDATE_URL/releases/latest" 2>/dev/null || true)"
        if [ -z "$_loc" ]; then
            _loc="$(curl -fsSI --ssl-no-revoke -o /dev/null -w '%{redirect_url}' "$UPDATE_URL/releases/latest" 2>/dev/null || true)"
        fi
    fi
    if [ -z "$_loc" ] && command -v wget >/dev/null 2>&1; then
        _loc="$(wget -q --spider --server-response -O /dev/null "$UPDATE_URL/releases/latest" 2>&1 | sed -n 's/^[[:space:]]*[Ll]ocation:[[:space:]]*//p' | tail -n 1 || true)"
    fi
    [ -n "$_loc" ] || return 1
    # 地址形如 .../releases/tag/V0.1.0，取最后一段且须为版本 tag
    _tag=${_loc%%[[:space:]]*}
    _tag=${_tag##*/}
    case "$_tag" in
        V*|v*) printf '%s' "$_tag"; return 0 ;;
        *) return 1 ;;
    esac
}

# —— 1. 时间节流：距上次真实检查不足间隔，静默退出（零网络、零输出） ——
_last="$(read_state last_check)"
case "$_last" in
    ''|*[!0-9]*) _last="" ;;
esac
_now="$(now)"
if [ -n "$_last" ] && [ $((_now - _last)) -lt "$CHECK_INTERVAL" ]; then
    exit 0
fi

# —— 2. 本地版本（skill_version 为空时回退本机 skill；两者皆无则静默放弃） ——
_ver="$(space_version)"
if [ -z "$_ver" ]; then
    if ! _ver="$(local_skill_version)"; then
        write_state last_check "$_now"
        exit 0
    fi
fi
if [ -z "$_ver" ]; then
    write_state last_check "$_now"
    exit 0
fi

# —— 3. 远端最新 tag（失败也记录检查时间，避免断网环境每次会话都重试） ——
if ! _tag="$(latest_tag)"; then
    write_state last_check "$_now"
    exit 0
fi
write_state last_check "$_now"

# —— 4. 版本比较：远端不比本地新，静默退出 ——
version_gt "$_tag" "$_ver" || exit 0

# —— 5. 版本节流：同一版本只提醒一次 ——
_notified="$(read_state notified)"
if [ "$_notified" = "$_tag" ]; then
    exit 0
fi

write_state notified "$_tag"

# —— 6. 拉取变更说明（CHANGELOG 区间段落：本机版本(不含)→最新版本；失败降级为仅一行提醒，不阻塞） ——
_changes=""
_tmp_cl="$TMP_DIR/changelog"
_changelog_url="${UPDATE_URL%/}/raw/master/CHANGELOG.md"
if curl -fsSL "$_changelog_url" -o "$_tmp_cl" 2>/dev/null \
    || curl -fsSL --ssl-no-revoke "$_changelog_url" -o "$_tmp_cl" 2>/dev/null \
    || wget -q -O "$_tmp_cl" "$_changelog_url" 2>/dev/null; then
    # 抽取「## <最新tag>」至「## <本机版本>」（不含）之间的全部版本段落（保留各版本标题行，
    # 去空行，限 20 行）。标题边界精确匹配整行或后跟空格（日期后缀），避免 V0.0.1 误配 V0.0.10；
    # 本机版本段落在 CHANGELOG 中缺失时打印到文件尾（由 head 限行兜底）
    _old="$_ver"
    case "$_old" in V*|v*) ;; *) _old="V$_old" ;; esac
    _changes="$(awk -v new="$_tag" -v old="$_old" '
        index($0, "## " new) == 1 && (length($0) == length(new) + 3 || substr($0, length(new) + 4, 1) == " ") { f = 1 }
        f && index($0, "## " old) == 1 && (length($0) == length(old) + 3 || substr($0, length(old) + 4, 1) == " ") { exit }
        f && $0 !~ /^[[:space:]]*$/ { print }
    ' "$_tmp_cl" | head -n 20)"
fi
rm -f "$_tmp_cl"

echo "tack harness 有新版本 ${_tag}（当前 ${_ver}），说「更新」即可升级"
if [ -n "$_changes" ]; then
    echo "本次更新内容："
    printf '%s\n' "$_changes"
fi
