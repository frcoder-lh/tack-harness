#!/bin/sh
# command-context.sh — 按需上下文目录、证据指纹与 story 确认回执
# Usage:
#   sh command-context.sh packet <root> <workspace> [story]
#   sh command-context.sh evidence <root> <workspace> <label> [target]
#   sh command-context.sh accept <root> <workspace> <label> <target> <evidence-token>
#   sh command-context.sh confirm|check <root> <workspace> <story> <analysis|spec|plan>
#   sh command-context.sh stories <root> <workspace>
#   sh command-context.sh analysis <root> <workspace>
#       扫描 doc/analysis/*.md 与 story/*/analysis.md 头部并比对基准 commit，TAB 分隔：
#         DOC<TAB>路径<TAB>主题<TAB>最近更新
#         BASE<TAB>路径<TAB>仓库<TAB>基准<TAB>HEAD<TAB>落后提交数<TAB>fresh|stale|unknown
#       基准写法：`repo1@hash, repo2@hash`；单仓库可只写 hash（取「涉及仓库」首项）
#   sh command-context.sh roster <root> <workspace>
#       开场知识清单事实：WIKI<TAB>路径；COLD<TAB>仓库（code/anchors.md 无该仓库锚点）；
#       STORY<TAB>story 名；其后附 analysis 动作的全部输出
# evidence 写入候选指纹；accept 仅在输入仍匹配时记录已评审指纹。
# 回执存于 .tack/state，丢失时按未确认处理；指纹相同仅表示输入相同，不代表语义通过。
set -eu
ACTION="${1:-}"; ROOT="${2:-}"; WORKSPACE="${3:-}"
[ -d "${ROOT}" ] || exit 2
ROOT="$(cd "${ROOT}" && pwd -P)"
case "${WORKSPACE}" in ''|.|..|*/*|*\\*) exit 2 ;; esac
WORK="${ROOT}/space/${WORKSPACE}"
[ -f "${WORK}/status.yaml" ] || exit 2
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
STATE="${ROOT}/.tack/state/context/${WORKSPACE}"
mkdir -p "${STATE}"
TMP="$(mktemp "${STATE}/context.XXXXXX")"
trap 'rm -f "${TMP}" "${TMP}.files"' EXIT
trap 'exit 130' HUP INT TERM
hash_file() {
    if [ -f "$1" ]; then
        printf '%s\t%s\n' "$(git hash-object "$1")" "${1#"${ROOT}/"}"
    else
        printf 'MISSING\t%s\n' "${1#"${ROOT}/"}"
    fi
}
document_index() {
    for file in "$@"; do
        [ -f "${file}" ] || continue
        hash_file "${file}"
        LC_ALL=C awk '/^#{1,6} / {print NR ":" $0}' "${file}"
    done
}
documents() {
    hash_file "${ROOT}/AGENTS.md"
    hash_file "${ROOT}/tack.yaml"
    hash_file "${WORK}/context.md"
    project="$(awk "$(cat "${SCRIPT_DIR}/yamlib.awk")"'/^project:/ {print val($0); exit}' "${WORK}/status.yaml")"
    case "${project}" in */*|*\\*|.|..) echo "Error: invalid project" >&2; exit 2 ;; esac
    printf 'PROJECT\t%s\n' "${project}"
    if [ -n "${project}" ] && [ -d "${ROOT}/wiki/${project}" ]; then
        find "${ROOT}/wiki/${project}" -type f -name '*.md' -print | LC_ALL=C sort > "${TMP}.files"
        while IFS= read -r file; do hash_file "${file}"; done < "${TMP}.files"
    fi
    find "${ROOT}/harness/rule" "${ROOT}/harness/cmd" "${ROOT}/harness/workflow" -type f -name '*.md' -print | LC_ALL=C sort > "${TMP}.files"
    while IFS= read -r file; do hash_file "${file}"; done < "${TMP}.files"
}
sources() {
    documents
    for repo in "${WORK}/repo"/*/; do
        [ -d "${repo}" ] || continue
        name="$(basename "${repo}")"
        printf 'REPO\t%s\n' "${name}"
        git -C "${repo}" rev-parse HEAD
        git -C "${repo}" symbolic-ref -q HEAD || true
        for ref in "${TARGET:-HEAD}" "origin/${TARGET:-HEAD}" master main origin/master origin/main; do
            printf 'REF\t%s\t' "${ref}"
            git -C "${repo}" rev-parse --verify "${ref}^{commit}" 2>/dev/null || printf 'MISSING\n'
        done
        git -C "${repo}" diff --no-ext-diff --binary | git hash-object --stdin
        git -C "${repo}" diff --cached --no-ext-diff --binary | git hash-object --stdin
        # NUL 传递路径，未跟踪文件只计算摘要、不输出正文或凭据。
        git -C "${repo}" ls-files --others --exclude-standard -z | git hash-object --stdin
        git -C "${repo}" ls-files --others --exclude-standard -z |
            (cd "${repo}" && xargs -0 git hash-object --) | git hash-object --stdin
    done
}
# analysis_index：分析文档头部与基准新鲜度（只读头部 `> 字段:` 行，兼容同一行以全角空格分隔多字段）
analysis_index() {
    for file in "${WORK}/doc/analysis"/*.md "${WORK}/story"/*/analysis.md; do
        [ -f "${file}" ] || continue
        rel="${file#"${ROOT}/"}"
        LC_ALL=C awk -v P="${rel}" '
            NR > 30 { exit }
            /^> / {
                line = substr($0, 3); n = split(line, seg, "　")
                for (i = 1; i <= n; i++) {
                    s = seg[i]; k = s; sub(/:.*/, "", k); v = s; sub(/^[^:]*:[[:space:]]*/, "", v)
                    sub(/[[:space:]]+$/, "", v); sub(/（.*/, "", v)
                    if (k == "主题") topic = v
                    else if (k == "最近更新" || k == "生成时间") { if (updated == "" || k == "最近更新") updated = v }
                    else if (k == "涉及仓库" || k == "仓库") repos = v
                    else if (k == "基准 commit") base = v
                }
            }
            END {
                printf "DOC\037%s\037%s\037%s\n", P, topic, updated
                if (base == "") exit
                n = split(base, b, ",")
                split(repos, r, ",")
                for (i = 1; i <= n; i++) {
                    x = b[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", x)
                    if (index(x, "@")) { repo = substr(x, 1, index(x, "@") - 1); h = substr(x, index(x, "@") + 1) }
                    else { repo = r[1]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", repo); h = x }
                    printf "PAIR\037%s\037%s\037%s\n", P, repo, h
                }
            }
        ' "${file}"
    done > "${TMP}"
    # 单元分隔符 \037 不属 IFS 空白，空主题/空日期不会被折叠
    while IFS="$(printf '\037')" read -r kind path repo base; do
        if [ "${kind}" = DOC ]; then printf 'DOC\t%s\t%s\t%s\n' "${path}" "${repo}" "${base}"; continue; fi
        dir="${WORK}/repo/${repo}"
        [ -d "${dir}" ] || dir="${ROOT}/repo/${repo}"
        head="-"; behind="-"; state=unknown
        case "${repo}" in ''|.|..|*/*|*\\*) dir="" ;; esac
        if [ -n "${dir}" ] && [ -d "${dir}" ] && head="$(git -C "${dir}" rev-parse --short HEAD 2>/dev/null)"; then
            if git -C "${dir}" rev-parse --verify -q "${base}^{commit}" >/dev/null 2>&1; then
                behind="$(git -C "${dir}" rev-list --count "${base}..HEAD")"
                if [ "${behind}" = 0 ]; then state=fresh; else state=stale; fi
            fi
        else
            head="-"
        fi
        printf 'BASE\t%s\t%s\t%s\t%s\t%s\t%s\n' "${path}" "${repo}" "${base}" "${head}" "${behind}" "${state}"
    done < "${TMP}"
}
story_manifest() {
    documents
    hash_file "${WORK}/story/${STORY}/analysis.md"
    if [ "${STAGE}" != analysis ]; then hash_file "${WORK}/story/${STORY}/spec.md"; fi
    if [ "${STAGE}" = plan ]; then hash_file "${WORK}/story/${STORY}/plan.md"; fi
}
review_manifest() {
    printf 'TARGET\t%s\n' "${TARGET}"
    sources
    for file in "${WORK}/story"/*/*.md; do [ ! -f "${file}" ] || hash_file "${file}"; done
    hash_file "${WORK}/doc/tech-design.md"
    for file in "${WORK}/doc"/tech-design-*.md; do [ ! -f "${file}" ] || hash_file "${file}"; done
}
case "${ACTION}" in
    packet)
        printf 'WORK=%s\n' "${WORK}"
        LC_ALL=C awk '/^[A-Za-z_][A-Za-z0-9_]*:/ {show=($0 !~ /^(tasks|guidance|branches|deploy):/)} show {print}' "${WORK}/status.yaml"
        sh "${SCRIPT_DIR}/work-status.sh" "${WORK}/status.yaml" tasks list
        document_index "${WORK}/context.md"
        if [ -n "${4:-}" ]; then
            case "$4" in .|..|*/*|*\\*) exit 2 ;; esac
            document_index "${WORK}/story/$4/analysis.md" "${WORK}/story/$4/spec.md" "${WORK}/story/$4/plan.md"
        else
            for file in "${WORK}/story"/*/*.md "${WORK}/doc"/*.md; do document_index "${file}"; done
        fi
        ;;
    stories)
        for dir in "${WORK}/story"/*/; do
            [ -d "${dir}" ] || continue
            for stage in analysis spec plan; do
                sh "$0" check "${ROOT}" "${WORKSPACE}" "$(basename "${dir}")" "${stage}" || true
            done
        done
        ;;
    analysis)
        analysis_index
        ;;
    roster)
        project="$(awk "$(cat "${SCRIPT_DIR}/yamlib.awk")"'/^project:/ {print val($0); exit}' "${WORK}/status.yaml")"
        case "${project}" in */*|*\\*|.|..) echo "Error: invalid project" >&2; exit 2 ;; esac
        wiki="${ROOT}/wiki/${project}"
        if [ -n "${project}" ] && [ -d "${wiki}" ]; then
            find "${wiki}" -type f -name '*.md' -print | LC_ALL=C sort |
                while IFS= read -r file; do
                    case "${file}" in "${wiki}/history/"*/*) continue ;; esac
                    printf 'WIKI\t%s\n' "${file#"${ROOT}/"}"
                done
        fi
        services="$(awk "$(cat "${SCRIPT_DIR}/yamlib.awk")"'/^services:/ {print yaml_csv(val($0)); exit}' "${WORK}/status.yaml")"
        anchors="${wiki}/code/anchors.md"
        saved_ifs="${IFS}"; IFS=','; set -f
        for repo in ${services}; do
            [ -n "${repo}" ] || continue
            if [ ! -f "${anchors}" ] || ! LC_ALL=C grep -F -- "| ${repo} " "${anchors}" >/dev/null 2>&1; then
                printf 'COLD\t%s\n' "${repo}"
            fi
        done
        set +f; IFS="${saved_ifs}"
        for dir in "${WORK}/story"/*/; do
            [ -d "${dir}" ] || continue
            printf 'STORY\t%s\n' "$(basename "${dir}")"
        done
        analysis_index
        ;;
    confirm|check)
        STORY="${4:-}"; STAGE="${5:-}"; TARGET=HEAD
        case "${STORY}" in ''|.|..|*/*|*\\*) exit 2 ;; esac
        case "${STAGE}" in analysis|spec|plan) ;; *) exit 2 ;; esac
        receipt="${STATE}/story-${STORY}-${STAGE}"
        story_manifest > "${TMP}"
        if [ "${ACTION}" = confirm ]; then
            case "${STAGE}" in analysis) artifact=analysis ;; *) artifact="${STAGE}" ;; esac
            [ -f "${WORK}/story/${STORY}/${artifact}.md" ] || exit 2
            [ -f "${WORK}/context.md" ] && [ -f "${WORK}/story/${STORY}/analysis.md" ] || exit 2
            if [ "${STAGE}" = plan ]; then [ -f "${WORK}/story/${STORY}/spec.md" ] || exit 2; fi
            mv "${TMP}" "${receipt}"
            printf 'CONFIRMED=%s:%s\n' "${STORY}" "${STAGE}"
        elif [ -f "${receipt}" ] && cmp -s "${TMP}" "${receipt}"; then
            printf 'VALID=%s:%s\n' "${STORY}" "${STAGE}"
        else
            printf 'UNCONFIRMED=%s:%s\n' "${STORY}" "${STAGE}"
            exit 3
        fi
        ;;
    evidence|accept)
        LABEL="${4:-}"; TARGET="${5:-HEAD}"
        case "${LABEL}" in ''|*[!A-Za-z0-9_-]*) exit 2 ;; esac
        review_manifest > "${TMP}"
        receipt="${STATE}/review-${LABEL}"
        candidate="${receipt}.candidate"
        if [ "${ACTION}" = accept ]; then
            [ -n "${6:-}" ] && [ "$(git hash-object "${TMP}")" = "$6" ] || {
                echo "Error: evidence changed during review" >&2; exit 3;
            }
            mv "${TMP}" "${receipt}"
            echo "EVIDENCE=accepted"
        else
            if [ -f "${receipt}" ] && cmp -s "${TMP}" "${receipt}"; then
                echo "EVIDENCE=unchanged"
            else
                echo "EVIDENCE=changed"
                if [ -f "${receipt}" ]; then diff -u "${receipt}" "${TMP}" || true; fi
            fi
            TOKEN="$(git hash-object "${TMP}")"
            mv "${TMP}" "${candidate}"
            printf 'MANIFEST=%s\n' "${candidate}"
            printf 'EVIDENCE_TOKEN=%s\n' "${TOKEN}"
        fi
        ;;
    *) exit 2 ;;
esac
