#!/bin/sh
# common.sh — 安装、升级与版本检查共享能力的唯一事实源
#
# 安装、升级、版本检查与发版链路以 `.`（POSIX source）加载本文件，不独立执行。
# 新增或修改 agent 预设、分发清单、下载回退、版本提取、摘要校验时只改这里，
# 其他脚本只做正向引用。
#
# 提供：
#   TACK_SKILL_FILES          分发包文件清单（相对 skill 根，空格分隔）
#   tack_agent_presets        每行 "name|detect_dir|skill_dir"；detect_dir 存在即视为该 agent 已安装
#   tack_find_skill_dirs      逐行输出本机已安装的 skill 目录（须含 SKILL.md）
#   tack_is_windows           输出 1/0（Git for Windows 的 MINGW/MSYS/CYGWIN 环境）
#   tack_download_to          URL 下载到文件（curl → curl --ssl-no-revoke → wget）
#   tack_latest_release_tag   解析 GitHub releases/latest 的 302 目标 tag（V* 形式）
#   tack_skill_version        读取 skill 根目录 SKILL.md front matter 的 version
#   tack_sha256_file          输出文件 SHA-256（openssl → shasum）
#   tack_verify_sha256        按 .sha256 文件首字段核验目标文件

# 分发包清单：安装与升级链路共用
TACK_SKILL_FILES="SKILL.md README.md README.en.md CHANGELOG.md CHANGELOG.en.md install.sh tack"

# agent 预设：新增 agent 只改这里，安装/升级/检查三条链路同时生效
tack_agent_presets() {
    cat <<EOF
trae-cn|${HOME}/.trae-cn|${HOME}/.trae-cn/skills/tack
trae|${HOME}/.trae|${HOME}/.trae/skills/tack
cursor|${HOME}/.cursor|${HOME}/.cursor/skills/tack
windsurf|${HOME}/.windsurf|${HOME}/.windsurf/skills/tack
cline|${HOME}/.cline|${HOME}/.cline/skills/tack
codeium|${HOME}/.codeium|${HOME}/.codeium/skills/tack
aider|${HOME}/.aider|${HOME}/.aider/skills/tack
devbox|${HOME}/.devbox|${HOME}/.devbox/skills/tack
claude|${HOME}/.claude|${HOME}/.claude/skills/tack
EOF
}

# tack_find_skill_dirs — 按预设顺序逐行输出已安装目录（多装时由调用方决定如何处理）
tack_find_skill_dirs() {
    _tack_old_ifs="${IFS}"
    IFS='
'
    set -f
    for _tack_line in $(tack_agent_presets); do
        [ -n "${_tack_line}" ] || continue
        _tack_rest="${_tack_line#*|}"
        _tack_path="${_tack_rest#*|}"
        if [ -n "${_tack_path}" ] && [ -f "${_tack_path}/SKILL.md" ]; then
            printf '%s\n' "${_tack_path}"
        fi
    done
    set +f
    IFS="${_tack_old_ifs}"
}

# tack_is_windows — Git for Windows 的 bash 环境（POSIX sh 下输出 1，其余 0）
tack_is_windows() {
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) printf '1' ;;
        *) printf '0' ;;
    esac
}

# tack_download_to <url> <outfile> — 三下载器回退；全部失败返回非零
# --ssl-no-revoke 是 Git for Windows（schannel）专有回退，仅 Windows 使用
tack_download_to() {
    _tack_url="$1"
    _tack_out="$2"
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL "${_tack_url}" -o "${_tack_out}" 2>/dev/null; then
            return 0
        fi
        if [ "$(tack_is_windows)" -eq 1 ] \
            && curl -fsSL --ssl-no-revoke "${_tack_url}" -o "${_tack_out}" 2>/dev/null; then
            return 0
        fi
    fi
    if command -v wget >/dev/null 2>&1; then
        if wget -q -O "${_tack_out}" "${_tack_url}" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# tack_latest_release_tag <update-url> — 取 releases/latest 的 302 重定向地址尾段 tag
# 单次 HEAD 请求，不走 GitHub API；curl 不带 -L（不跟随重定向），用 -w redirect_url 拿目标
tack_latest_release_tag() {
    _tack_base="${1%/}"
    _tack_loc=""
    if command -v curl >/dev/null 2>&1; then
        _tack_loc="$(curl -fsSI -o /dev/null -w '%{redirect_url}' "${_tack_base}/releases/latest" 2>/dev/null || true)"
        if [ -z "${_tack_loc}" ] && [ "$(tack_is_windows)" -eq 1 ]; then
            _tack_loc="$(curl -fsSI --ssl-no-revoke -o /dev/null -w '%{redirect_url}' "${_tack_base}/releases/latest" 2>/dev/null || true)"
        fi
    fi
    if [ -z "${_tack_loc}" ] && command -v wget >/dev/null 2>&1; then
        _tack_loc="$(wget -q --spider --server-response -O /dev/null "${_tack_base}/releases/latest" 2>&1 | sed -n 's/^[[:space:]]*[Ll]ocation:[[:space:]]*//p' | tail -n 1 || true)"
    fi
    [ -n "${_tack_loc}" ] || return 1
    _tack_tag=${_tack_loc%%[[:space:]]*}
    _tack_tag=${_tack_tag##*/}
    case "${_tack_tag}" in
        V*|v*) printf '%s' "${_tack_tag}"; return 0 ;;
        *) return 1 ;;
    esac
}

# tack_skill_version <skill-root> — SKILL.md front matter version（仅前两个 --- 之间）
tack_skill_version() {
    [ -f "$1/SKILL.md" ] || return 1
    sed -n '2,/^---$/ s/^version:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$1/SKILL.md" | head -n 1
}

# tack_sha256_file <file> — openssl 优先（Git for Windows/macOS/Linux 均自带），
# 回退 shasum -a 256；都不可用或计算失败返回非零
tack_sha256_file() {
    [ -f "$1" ] || return 1
    if command -v openssl >/dev/null 2>&1; then
        _tack_hash="$(openssl dgst -sha256 -r "$1" 2>/dev/null | awk '{print $1; exit}')"
        if [ -n "${_tack_hash}" ]; then
            printf '%s' "${_tack_hash}"
            return 0
        fi
    fi
    if command -v shasum >/dev/null 2>&1; then
        _tack_hash="$(shasum -a 256 "$1" 2>/dev/null | awk '{print $1; exit}')"
        if [ -n "${_tack_hash}" ]; then
            printf '%s' "${_tack_hash}"
            return 0
        fi
    fi
    return 1
}

# tack_verify_sha256 <file> <checksum-file> — 校验文件首字段与目标文件摘要一致
tack_verify_sha256() {
    _tack_expected="$(awk 'NR==1 {print $1}' "$2" 2>/dev/null)"
    [ -n "${_tack_expected}" ] || return 1
    _tack_actual="$(tack_sha256_file "$1")" || return 1
    [ "${_tack_expected}" = "${_tack_actual}" ]
}
