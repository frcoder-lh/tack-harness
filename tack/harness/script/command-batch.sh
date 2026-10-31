#!/bin/sh
# command-batch.sh — 合并已确定的机械步骤，保留子脚本的验证与退出码
# Usage:
#   sh command-batch.sh finish <root> <workspace> <stage> <next> <message> <file> [...]
#   sh command-batch.sh work-create <root> <project> <branch> <description> <services> <triggers> <workflow>
#   sh command-batch.sh attach <root> <workspace> <branch> <repo>
#   sh command-batch.sh register <root> <project> <tsv>
#     TSV：set<TAB>key<TAB>value；keywords<TAB>csv；repo<TAB>service<TAB>name<TAB>git<TAB>path
#   sh command-batch.sh guidance <root> <workspace> <tsv>
#     TSV：id<TAB>applied|rejected<TAB>落点1<TAB>落点2...
#   sh command-batch.sh close-facts <root> <workspace>
#   sh command-batch.sh close-remove <root> <workspace> <work-id>
# 所有动作共用空间锁；失败即停，成功记录可用于续跑。finish 才统一提交已列出的文件。
set -eu
ACTION="${1:-}"; ROOT="${2:-}"
[ -d "${ROOT}" ] || exit 2
ROOT="$(cd "${ROOT}" && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
shift 2
. "${SCRIPT_DIR}/space-lock.sh"
tack_space_lock_acquire "${ROOT}"
mkdir -p "${ROOT}/.tack/tmp"
TMP="$(mktemp "${ROOT}/.tack/tmp/command-batch.XXXXXX")"
trap 'rm -f "${TMP}" "${TMP}.status" "${TMP}.store"; tack_space_lock_release' EXIT
trap 'exit 130' HUP INT TERM
workspace() {
    case "$1" in ''|.|..|*/*|*\\*) exit 2 ;; esac
    WORKSPACE="$1"; WORK="${ROOT}/space/${WORKSPACE}"
}
field() {
    LC_ALL=C awk -v K="$1" '
        index($0,K "=")==1 {print substr($0,length(K)+2); exit}
    ' "${TMP}"
}
case "${ACTION}" in
    finish)
        [ $# -ge 5 ] || exit 2
        workspace "$1"; STAGE="$2"; NEXT="$3"; MESSAGE="$4"; shift 4
        sh "${SCRIPT_DIR}/work-status.sh" "${WORK}/status.yaml" set stage "${STAGE}" "progress.${STAGE}" true next "${NEXT}"
        sh "${SCRIPT_DIR}/space.sh" commit "${ROOT}" "${MESSAGE}" "${WORK}/status.yaml" "$@"
        printf 'FINISHED=%s\n' "${STAGE}"
        ;;
    work-create)
        [ $# -eq 6 ] || exit 2
        PROJECT="$1"; BRANCH="$2"; DESCRIPTION="$3"; SERVICES="$4"; TRIGGERS="$5"
        # 第六个参数为已确认的工作流；保持工作区创建与登记在一次调用内完成。
        WORKFLOW="$6"
        case "${WORKFLOW}" in *[!A-Za-z0-9_-]*) exit 2 ;; esac
        if [ -n "${WORKFLOW}" ]; then
            ROUTE="$(sh "${SCRIPT_DIR}/scan-routes.sh" show "${ROOT}/harness" "${WORKFLOW}")" || exit 2
            case "${ROUTE}" in workflow\|*) ;; *) echo "Error: workflow not found: ${WORKFLOW}" >&2; exit 2 ;; esac
        fi
        sh "${SCRIPT_DIR}/work.sh" --no-worktree --no-commit "${ROOT}" "${PROJECT}" "${BRANCH}" > "${TMP}"
        workspace "$(field WORKSPACE)"
        BRANCH="$(field BRANCH)"
        if sh "${SCRIPT_DIR}/project.sh" work-get "${ROOT}" "${BRANCH}" >/dev/null 2>&1; then
            echo "Error: work_id already registered; use work switch" >&2; exit 3
        fi
        sh "${SCRIPT_DIR}/project.sh" work-add "${ROOT}" "${PROJECT}" "${BRANCH}" "${DESCRIPTION}" "${WORK}" "${BRANCH}" "${SERVICES}" "${TRIGGERS}" --no-commit
        if [ -n "${SERVICES}" ]; then
            sh "${SCRIPT_DIR}/project.sh" work-services "${ROOT}" "${BRANCH}" "${SERVICES}" "${WORK}/status.yaml" --no-commit
        fi
        # workflow 模板字段按地址范围替换，名称与定义已验证。
        LC_ALL=C awk -v W="${WORKFLOW}" '/^workflow:/ {$0="workflow: \"" W "\""; seen=1} {print} END {if(!seen) exit 3}' "${WORK}/status.yaml" > "${TMP}.status"
        mv "${TMP}.status" "${WORK}/status.yaml"
        printf '\n## 本次工作目的\n\n%s\n' "${DESCRIPTION}" >> "${WORK}/context.md"
        printf 'WORKSPACE=%s\nBRANCH=%s\n' "${WORKSPACE}" "${BRANCH}"
        ;;
    attach)
        [ $# -eq 3 ] || exit 2
        workspace "$1"; BRANCH="$2"; REPO="$3"
        case "${REPO}" in ''|.|..|*/*|*\\*) exit 2 ;; esac
        [ -f "${WORK}/status.yaml" ] || exit 2
        ID="$(LC_ALL=C awk '/^work_id:/ {sub(/^[^:]*:[[:space:]]*"/,""); sub(/".*$/,""); print; exit}' "${WORK}/status.yaml")"
        sh "${SCRIPT_DIR}/project.sh" work-get "${ROOT}" "${ID}" > "${TMP}"
        SERVICES="$(field SERVICES)"
        mkdir -p "${ROOT}/.tack/state/attach/${WORKSPACE}"
        MARKER="${ROOT}/.tack/state/attach/${WORKSPACE}/${REPO}"
        if [ ! -f "${MARKER}" ]; then
            if git -C "${ROOT}/repo/${REPO}" show-ref --verify --quiet "refs/heads/${BRANCH}"; then created=0; else created=1; fi
            printf '%s\n' "${created}" > "${MARKER}"
        fi
        sh "${SCRIPT_DIR}/git-worktree-helper.sh" create "${ROOT}" "${WORKSPACE}" "${BRANCH}" "${REPO}"
        [ "$(git -C "${WORK}/repo/${REPO}" symbolic-ref --short HEAD)" = "${BRANCH}" ] || exit 3
        SERVICES="$(printf '%s,%s' "${SERVICES}" "${REPO}" | awk -F ',' '{for(i=1;i<=NF;i++) if($i!=""&&!seen[$i]++){printf "%s%s",sep,$i; sep=","}}')"
        sh "${SCRIPT_DIR}/project.sh" work-services "${ROOT}" "${ID}" "${SERVICES}" "${WORK}/status.yaml" --no-commit
        if [ "$(cat "${MARKER}")" = 1 ]; then
            sh "${SCRIPT_DIR}/work-status.sh" "${WORK}/status.yaml" branch register "${REPO}" "${BRANCH}" main worktree
        fi
        rm -f "${MARKER}"
        printf 'ATTACHED=%s\n' "${REPO}"
        ;;
    register)
        [ $# -eq 2 ] && [ -f "$2" ] || exit 2
        PROJECT="$1"; TSV="$2"
        # TAB 转换为非空白分隔符，保留 repo_git 等允许为空的字段。
        if LC_ALL=C grep -q '|' "${TSV}"; then echo "Error: TSV values cannot contain |" >&2; exit 2; fi
        LC_ALL=C awk -F '\t' '
          ($1=="set"&&NF==3)||($1=="keywords"&&NF==2)||($1=="repo"&&NF==5) {next}
          {bad=1} END {exit bad}
        ' "${TSV}" || exit 2
        tr '\t' '|' < "${TSV}" > "${TMP}"
        while IFS='|' read -r op a b c d; do
            case "${op}" in
                set) sh "${SCRIPT_DIR}/project.sh" project-set "${ROOT}" "${PROJECT}" "${a}" "${b}" --no-commit ;;
                keywords) sh "${SCRIPT_DIR}/project.sh" project-keywords "${ROOT}" "${PROJECT}" "${a}" --no-commit ;;
                repo) sh "${SCRIPT_DIR}/project.sh" project-service-repo "${ROOT}" "${PROJECT}" "${a}" "${b}" "${c}" "${d}" --no-commit ;;
            esac
        done < "${TMP}"
        ;;
    guidance)
        [ $# -eq 2 ] && [ -f "$2" ] || exit 2
        workspace "$1"; TSV="$2"
        LC_ALL=C awk -F '\t' 'NF<2 || ($2!="applied"&&$2!="rejected") {bad=1} END {exit bad}' "${TSV}" || exit 2
        while IFS= read -r row; do
            # 已固定为 TAB 协议；禁用 glob，保留路径中的空格。
            saved_ifs="${IFS}"; IFS="$(printf '\t')"; set -f
            set -- ${row}
            set +f; IFS="${saved_ifs}"
            sh "${SCRIPT_DIR}/work-status.sh" "${WORK}/status.yaml" guidance "$@"
        done < "${TSV}"
        printf 'GUIDANCE_STATUS=%s\n' "${WORK}/status.yaml"
        ;;
    close-facts)
        [ $# -eq 1 ] || exit 2
        workspace "$1"
        sh "${SCRIPT_DIR}/command-context.sh" packet "${ROOT}" "${WORKSPACE}"
        sh "${SCRIPT_DIR}/work-status.sh" "${ROOT}" related children "${WORKSPACE}"
        sh "${SCRIPT_DIR}/work-status.sh" "${WORK}/status.yaml" deploy list
        sh "${SCRIPT_DIR}/work-status.sh" "${WORK}/status.yaml" guidance list pending
        sh "${SCRIPT_DIR}/workspace-archive.sh" list "${ROOT}" "${WORKSPACE}"
        for repo in "${WORK}/repo"/*/; do
            [ -d "${repo}" ] || continue
            printf 'REPO=%s\n' "$(basename "${repo}")"
            sh "${SCRIPT_DIR}/git-facts.sh" status "${repo}"
        done
        ;;
    close-remove)
        [ $# -eq 2 ] || exit 2
        workspace "$1"; ID="$2"
        sh "${SCRIPT_DIR}/project.sh" work-get "${ROOT}" "${ID}" > "${TMP}"
        REGISTERED="$(field WORK_PATH)"
        case "${REGISTERED}" in "${WORK}"|"space/${WORKSPACE}") ;; *)
            echo "Error: work_id does not identify the requested workspace" >&2; exit 3 ;;
        esac
        if [ -d "${WORK}" ]; then
            sh "${SCRIPT_DIR}/work-status.sh" "${WORK}/status.yaml" guidance list pending > "${TMP}"
            [ ! -s "${TMP}" ] || { echo "Error: resolve pending guidance before removal" >&2; exit 3; }
            [ ! -d "${WORK}/run" ] || { echo "Error: archive run/ before removal" >&2; exit 3; }
            sh "${SCRIPT_DIR}/work-status.sh" "${ROOT}" related children "${WORKSPACE}" > "${TMP}"
            [ ! -s "${TMP}" ] || { echo "Error: close children first" >&2; exit 3; }
            sh "${SCRIPT_DIR}/work.sh" purge "${ROOT}" "${WORKSPACE}"
        fi
        sh "${SCRIPT_DIR}/project.sh" work-remove "${ROOT}" "${ID}" --no-commit
        printf 'CLOSED=%s\n' "${WORKSPACE}"
        ;;
    *) exit 2 ;;
esac
