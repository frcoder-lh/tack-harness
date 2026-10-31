#!/bin/sh
# repo.sh — 代码主仓库接入与同步（扫描本地 / 软链已有 / 克隆远端 / 更新远端）
#
# Usage:
#   sh repo.sh scan  <root> <scan-dir>         # 深度 <= 5 扫描本地 git 仓库，逐行输出绝对路径
#   sh repo.sh link  <root> <local-path> ...   # 将本地仓库软链到 <root>/repo/<repo-name>
#   sh repo.sh clone <root> <git-url>  ...     # 克隆远端仓库到 <root>/repo/<repo-name>
#                                                     clone 支持 -force 覆盖已存在仓库
#   sh repo.sh fetch <root> [repo-name...]     # 更新全部（省略仓库名）或指定主仓库到远端最新；
#                                                     逐仓库复用 git-fetch-helper.sh sync
#
# fetch 退出码: 0 全部同步成功；1 存在普通失败；10 存在 pull 冲突；11 存在需人工介入项

set -e

ACTION="$1"
ROOT="$2"

if [ -z "${ACTION}" ] || [ -z "${ROOT}" ]; then
    echo "Usage: sh repo.sh <scan|link|clone|fetch> <root> [args...]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 解析仓库名：路径末段，去掉尾部斜杠与 .git
get_repo_name() {
    name="$1"
    while [ "${name}" != "${name%/}" ]; do
        name="${name%/}"
    done
    name="${name##*/}"
    name="${name%.git}"
    echo "${name}"
}

# 仓库名必须是单层目录名；空名、.、.. 会把目标退化为 <root>/repo，直接拒绝
require_repo_name() {
    case "$1" in
        ''|.|..)
            echo "Error: 无法解析有效仓库名: $2" >&2
            exit 1
            ;;
    esac
}

# link_dir <src> <target> — 目录链接：Windows 用 junction（Git Bash 的 ln -s
# 在未开启 winsymlinks 时会退化为复制），其余平台用符号链接
link_dir() {
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*)
            cmd //c mklink //J "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null 2>&1
            ;;
        *)
            ln -s "$1" "$2"
            ;;
    esac
}

case "${ACTION}" in

    scan)
        SCAN_DIR="$3"
        if [ -z "${SCAN_DIR}" ] || [ ! -d "${SCAN_DIR}" ]; then
            echo "Error: 扫描目录不存在: ${SCAN_DIR}" >&2
            exit 1
        fi
        # -maxdepth 5：只向下最多 5 层；-prune 避免钻进仓库内部继续扫描
        find "${SCAN_DIR}" -maxdepth 5 -type d -name .git -prune 2>/dev/null | while IFS= read -r gitdir; do
            dirname "${gitdir}"
        done
        ;;

    link)
        shift 2
        if [ $# -lt 1 ]; then
            echo "Usage: sh repo.sh link <root> <local-path> ..." >&2
            exit 1
        fi
        mkdir -p "${ROOT}/repo"
        for src in "$@"; do
            [ -d "${src}" ] || { echo "跳过（目录不存在）: ${src}"; continue; }
            abs="$(cd "${src}" && pwd)"
            name=$(get_repo_name "${abs}")
            require_repo_name "${name}" "${src}"
            target="${ROOT}/repo/${name}"
            if [ -e "${target}" ]; then
                echo "已存在，跳过: repo/${name}"
                continue
            fi
            if link_dir "${abs}" "${target}"; then
                echo "已软链: repo/${name} -> ${abs}"
            else
                echo "Error: 创建目录链接失败: repo/${name} -> ${abs}" >&2
                exit 1
            fi
        done
        ;;

    clone)
        shift 2
        if [ $# -lt 1 ]; then
            echo "Usage: sh repo.sh clone <root> <git-url> ... [-force]" >&2
            exit 1
        fi
        mkdir -p "${ROOT}/repo"

        FORCE=0
        for arg in "$@"; do
            [ "${arg}" = "-force" ] || [ "${arg}" = "--force" ] && FORCE=1
        done

        for repo in "$@"; do
            [ "${repo}" = "-force" ] || [ "${repo}" = "--force" ] && continue

            repo_name=$(get_repo_name "${repo}")
            require_repo_name "${repo_name}" "${repo}"
            target_dir="${ROOT}/repo/${repo_name}"
            if [ "${target_dir}" = "${ROOT}/repo" ]; then
                echo "Error: 目标目录不能是 ${ROOT}/repo" >&2
                exit 1
            fi

            if [ -d "${target_dir}" ]; then
                if [ "${FORCE}" -eq 1 ]; then
                    echo "覆盖已有仓库: ${repo_name}"
                    rm -rf "${target_dir}"
                else
                    echo "仓库已存在: ${repo_name}（加 -force 可重新克隆），尝试拉取更新..."
                    git -C "${target_dir}" pull 2>/dev/null || echo "  拉取失败，跳过"
                    continue
                fi
            fi

            echo "克隆: ${repo} -> repo/${repo_name}"
            if git clone "${repo}" "${target_dir}"; then
                echo "  成功: ${repo_name}"
            else
                echo "  失败: ${repo_name}"
                rm -rf "${target_dir}" 2>/dev/null
            fi
        done
        ;;

    fetch)
        shift 2
        REPO_DIR="${ROOT}/repo"
        if [ ! -d "${REPO_DIR}" ]; then
            echo "Error: 主仓库目录不存在: ${REPO_DIR}" >&2
            exit 1
        fi

        FETCH_HELPER="${SCRIPT_DIR}/git-fetch-helper.sh"
        if [ ! -f "${FETCH_HELPER}" ]; then
            echo "Error: 缺少同步脚本: ${FETCH_HELPER}" >&2
            exit 1
        fi

        total=0; ok=0; manual=0; conflict=0; failed=0

        fetch_one() {
            total=$((total + 1))
            rc=0
            sh "${FETCH_HELPER}" sync "$1" || rc=$?
            case "${rc}" in
                0)  ok=$((ok + 1)) ;;
                10) conflict=$((conflict + 1)) ;;
                11) manual=$((manual + 1)) ;;
                *)  failed=$((failed + 1)) ;;
            esac
        }

        if [ $# -eq 0 ]; then
            for d in "${REPO_DIR}"/*/; do
                [ -d "${d}" ] || continue
                fetch_one "${d%/}"
            done
        else
            # 先校验全部指定仓库存在，避免逐个静默跳过
            for name in "$@"; do
                if [ ! -d "${REPO_DIR}/${name}" ]; then
                    echo "Error: 主仓库不存在: repo/${name}" >&2
                    echo "可用仓库:" >&2
                    for d in "${REPO_DIR}"/*/; do
                        [ -d "${d}" ] && echo "  ${d%/}" >&2
                    done
                    exit 1
                fi
            done
            for name in "$@"; do
                fetch_one "${REPO_DIR}/${name}"
            done
        fi

        [ "${total}" -gt 0 ] || echo "未找到可更新的主仓库: ${REPO_DIR}"
        echo "REPO_FETCH_SUMMARY=total:${total} ok:${ok} manual:${manual} conflict:${conflict} failed:${failed}"
        [ "${failed}" -eq 0 ] || exit 1
        [ "${conflict}" -eq 0 ] || exit 10
        [ "${manual}" -eq 0 ] || exit 11
        exit 0
        ;;

    *)
        echo "Error: 未知动作 '${ACTION}'（支持 scan / link / clone / fetch）" >&2
        exit 1
        ;;
esac
