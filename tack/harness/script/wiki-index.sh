#!/bin/sh
# wiki-index.sh — 项目 wiki 索引完整性检查
#
# Usage:
#   sh wiki-index.sh check <root> <project>
#
# 扫描 <root>/wiki/<project>/ 下全部 index.md，提取其中登记的文件/目录路径
# （支持 `path` 反引号与 [text](path) 两种写法，路径相对所在索引文件），
# 再与 wiki 下全部文件比对，输出未登记文件。
# 目录登记即覆盖该目录下全部文件（目录覆盖仅用于低层目录）。
#
# 输出:
#   UNREGISTERED<TAB><相对项目 wiki 的路径>   # 未登记文件（每行一个，已排序）
#   SUMMARY<TAB>missing=<N>
#   完整时输出 WIKI_INDEX=complete
#
# 退出码: 0 索引完整；1 root/project wiki 不存在；2 用法错误；3 存在未登记文件

set -eu

ACTION="${1:-}"
ROOT="${2:-}"
PROJECT="${3:-}"

usage() {
    echo "Usage: sh wiki-index.sh check <root> <project>" >&2
}

[ "${ACTION}" = "check" ] || { usage; exit 2; }
[ -n "${ROOT}" ] && [ -n "${PROJECT}" ] || { usage; exit 2; }
[ -d "${ROOT}" ] || { echo "Error: root not found: ${ROOT}" >&2; exit 1; }

case "${PROJECT}" in
    ""|.|..|*/*|*\\*) echo "Error: invalid project: ${PROJECT}" >&2; exit 2 ;;
esac

PROJ="${ROOT}/wiki/${PROJECT}"
[ -d "${PROJ}" ] || { echo "Error: project wiki not found: ${PROJ}" >&2; exit 1; }

TMP_BASE="${ROOT}/.tack/tmp"
mkdir -p "${TMP_BASE}"
FILES="${TMP_BASE}/wiki-index-files.$$"
DIRS="${TMP_BASE}/wiki-index-dirs.$$"
LIST="${TMP_BASE}/wiki-index-list.$$"
MISS="${TMP_BASE}/wiki-index-miss.$$"
trap 'rm -f "${FILES}" "${DIRS}" "${LIST}" "${MISS}"' EXIT HUP INT TERM
: > "${FILES}"
: > "${DIRS}"
: > "${MISS}"

# 从索引文件提取候选路径：反引号文本 + Markdown 链接目标
extract_tokens() {
    awk '
        {
            line = $0
            while (match(line, /\]\([^)]*\)/)) {
                print substr(line, RSTART + 2, RLENGTH - 3)
                line = substr(line, RSTART + RLENGTH)
            }
            line = $0
            while (match(line, /`[^`]*`/)) {
                print substr(line, RSTART + 1, RLENGTH - 2)
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "$1"
}

find "${PROJ}" -type f -name 'index.md' > "${LIST}"

while IFS= read -r idx; do
    [ -n "${idx}" ] || continue
    rel="${idx#${PROJ}/}"
    idxdir="$(dirname "${rel}")"
    [ "${idxdir}" = "." ] && idxdir=""
    extract_tokens "${idx}" | while IFS= read -r tok; do
        # 去掉锚点与包裹字符
        tok="${tok%%#*}"
        tok="${tok#\`}"
        tok="${tok%\`}"
        case "${tok}" in
            ""|*" "*|*"	"*) continue ;;
        esac
        # 跳过 URL、绝对路径、Windows 盘符与父目录跳转
        case "${tok}" in
            http*|https*|git@*|/*|[A-Za-z]:*|*..*) continue ;;
        esac
        # 去掉 ./ 前缀与 wiki/<project>/ 前缀
        while :; do
            case "${tok}" in
                ./*) tok="${tok#./}" ;;
                *) break ;;
            esac
        done
        case "${tok}" in
            "wiki/${PROJECT}/"*) tok="${tok#wiki/${PROJECT}/}" ;;
        esac
        [ -n "${tok}" ] || continue
        if [ -n "${idxdir}" ]; then
            cand="${idxdir}/${tok}"
        else
            cand="${tok}"
        fi
        if [ -d "${PROJ}/${cand}" ]; then
            printf '%s\n' "${cand%/}" >> "${DIRS}"
        elif [ -f "${PROJ}/${cand}" ]; then
            printf '%s\n' "${cand}" >> "${FILES}"
        fi
    done
done < "${LIST}"

while IFS= read -r f; do
    [ -n "${f}" ] || continue
    rel="${f#${PROJ}/}"
    # 项目总索引是根，不需要登记自身
    [ "${rel}" = "index.md" ] && continue
    covered=0
    if grep -qxF "${rel}" "${FILES}"; then
        covered=1
    fi
    if [ "${covered}" -eq 0 ]; then
        while IFS= read -r d; do
            [ -n "${d}" ] || continue
            case "${rel}" in
                "${d}"/*) covered=1; break ;;
            esac
        done < "${DIRS}"
    fi
    if [ "${covered}" -eq 0 ]; then
        printf '%s\n' "${rel}" >> "${MISS}"
    fi
done <<EOF
$(find "${PROJ}" -type f | sort)
EOF

if [ -s "${MISS}" ]; then
    sort "${MISS}" | while IFS= read -r m; do
        printf 'UNREGISTERED\t%s\n' "${m}"
    done
    printf 'SUMMARY\tmissing=%s\n' "$(grep -c . "${MISS}")"
    exit 3
fi

echo "WIKI_INDEX=complete"
exit 0
