#!/bin/sh
# lint-doc-scripts.sh — 文档中的 harness 脚本调用签名检查（初期仅 WARN）
#
# 第一版只检查四类明确事实，不做复杂 case/可选 flag 组合推断：
#   1. 脚本是否存在（harness/script/ 下同名 .sh）
#   2. 固定子命令是否有效
#   3. 必需位置参数数量是否足够（[可选] 参数不计入）
#   4. 明确 --flag 是否在脚本允许列表内
#
# 扫描范围：<harness-dir>/workflow|cmd|agents|reference|rule 下的 md 与 <root>/AGENTS.md；
# 只识别反引号内或代码行中以 `sh .../script/x.sh`、`run.ps1 x` 形式出现的调用。
#
# Usage:
#   sh lint-doc-scripts.sh <harness-dir>
#
# 输出：WARN  [文件] 脚本: 原因；末尾 lint-doc-scripts: N warning(s)
# 退出码: 0 完成（即使有 WARN）/ 1 目录无效 / 2 用法错误

set -eu

HARNESS_DIR="${1:-}"
if [ -z "${HARNESS_DIR}" ] || [ ! -d "${HARNESS_DIR}" ]; then
    echo "Usage: sh lint-doc-scripts.sh <harness-dir>" >&2
    exit 2
fi
HARNESS_DIR="$(cd "${HARNESS_DIR}" && pwd)"

ROOT_DIR="$(cd "${HARNESS_DIR}/.." && pwd)"

FILES=""
for f in "${HARNESS_DIR}/workflow"/*.md "${HARNESS_DIR}/agents"/*.md \
         "${HARNESS_DIR}/reference"/*.md "${HARNESS_DIR}/rule"/*.md \
         "${ROOT_DIR}/AGENTS.md"; do
    [ -f "${f}" ] && FILES="${FILES} ${f}"
done
if [ -d "${HARNESS_DIR}/cmd" ]; then
    for g in "${HARNESS_DIR}/cmd"/*/; do
        [ -d "${g}" ] || continue
        for f in "${g}"*.md; do
            [ -f "${f}" ] && FILES="${FILES} ${f}"
        done
    done
fi
[ -n "${FILES}" ] || { echo "lint-doc-scripts: 未找到待扫描文档" >&2; exit 1; }

# macOS BSD awk 在 UTF-8 locale 下读长中文行会触发 towc 多字节转换失败；
# 本脚本的签名解析只依赖 ASCII 语法标记，固定 C locale 按字节处理
LC_ALL=C awk -v H="${HARNESS_DIR}" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function rel(file,   r) { r = file; sub("^" H "/", "", r); return r }
    function warn(file, script, msg) {
        n_warn++
        printf "WARN  [%s] %s: %s\n", rel(file), script, msg
    }
    # 引号感知分词；out 为调用方局部数组
    function tokenize(s, out,   i, c, tok, inq, esc, n) {
        n = 0; tok = ""; inq = ""; esc = 0
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (esc) { tok = tok c; esc = 0; continue }
            if (c == "\\") { tok = tok c; esc = 1; continue }
            if (c == "\"" || c == "\047") {
                if (inq == c) inq = ""
                else if (inq == "") inq = c
                tok = tok c
                continue
            }
            if ((c == " " || c == "\t") && inq == "") {
                if (tok != "") { out[++n] = tok; tok = "" }
                continue
            }
            tok = tok c
        }
        if (tok != "") out[++n] = tok
        return n
    }
    function check_flags(base, FL, NFL, file,   i, f, ok) {
        for (i = 1; i <= NFL; i++) {
            f = FL[i]
            if (base == "work.sh") ok = (f == "--no-worktree" || f == "--dry-run" || f == "--apply")
            else if (base == "project.sh") ok = (f == "--no-commit" || f == "--if-empty")
            else if (base == "harness-diff.sh") ok = (f == "--profile")
            else if (base == "scan-secrets.sh") ok = (f == "--changed")
            else if (base == "branch-clean.sh") ok = (f == "--apply" || f == "--trunk")
            else if (base == "skill-update.sh") ok = (f == "--skill-root" || f == "--tack-root")
            else if (base == "git-diff-context.sh") ok = 0
            else continue
            if (!ok) warn(file, base, "未知 flag: " f)
        }
    }
    function check_sig(base, P, NP, FL, NFL, file,   sc, sub2, min) {
        if (base == "work-status.sh") {
            # work-status 的第一位置参数是 status.yaml（related 为空间根），子命令在其后
            if (NP < 2) { warn(file, base, "需要 <status.yaml> <子命令>"); return }
            sc = P[2]
            if (sc ~ /\|/) return
            if (sc != "set" && sc != "guidance" && sc != "tasks" && sc != "deploy" && sc != "branch" && sc != "related") {
                warn(file, base, "未知子命令: " sc); return
            }
            if (sc == "set") {
                if (NP < 4) warn(file, base, "set 至少需要一对 <key> <value>")
            } else if (sc == "guidance") {
                if (NP < 3) { warn(file, base, "guidance 缺少 <id> 或 list"); return }
                if (P[3] == "list" || P[3] == "all") {
                    if (NP > 3 && P[4] != "pending" && P[4] != "all")
                        warn(file, base, "guidance " P[3] " 过滤值只允许 pending|all: " P[4])
                } else if (NP < 4) {
                    warn(file, base, "guidance 需要 <id> <applied|rejected>")
                } else if (P[4] == "applied" && NP < 5) {
                    warn(file, base, "guidance applied 需要至少一个落点")
                }
            } else if (sc == "tasks") {
                if (NP < 3) { warn(file, base, "tasks 缺少子动作"); return }
                sub2 = P[3]
                if (sub2 ~ /\|/) return
                if (sub2 == "list" || sub2 == "validate" || sub2 == "ready" || sub2 == "repos") min = 3
                else if (sub2 == "set") min = 5
                else if (sub2 == "replace") min = 4
                else { warn(file, base, "未知 tasks 子动作: " sub2); return }
                if (NP < min) warn(file, base, "tasks " sub2 " 参数不足")
            } else if (sc == "deploy") {
                if (NP < 3) { warn(file, base, "deploy 缺少子动作"); return }
                sub2 = P[3]
                if (sub2 ~ /\|/) return
                if (sub2 == "list") min = 3
                else if (sub2 == "upsert") min = 10
                else if (sub2 == "mark") min = 7
                else { warn(file, base, "未知 deploy 子动作: " sub2); return }
                if (NP < min) warn(file, base, "deploy " sub2 " 参数不足")
            } else if (sc == "branch") {
                if (NP < 3) { warn(file, base, "branch 缺少子动作"); return }
                sub2 = P[3]
                if (sub2 ~ /\|/) return
                if (sub2 == "register") min = 7
                else if (sub2 == "mark") min = 6
                else if (sub2 == "list") min = 3
                else if (sub2 == "rename") min = 5
                else { warn(file, base, "未知 branch 子动作: " sub2); return }
                if (NP < min) warn(file, base, "branch " sub2 " 参数不足")
            } else if (sc == "related") {
                if (NP < 3) { warn(file, base, "related 缺少子动作"); return }
                sub2 = P[3]
                if (sub2 ~ /\|/) return
                if (sub2 == "children") min = 4
                else { warn(file, base, "未知 related 子动作: " sub2); return }
                if (NP < min) warn(file, base, "related " sub2 " 参数不足")
            }
            return
        }
        if (base == "project.sh") {
            if (NP < 1) { warn(file, base, "缺少子命令"); return }
            sc = P[1]
            if (sc ~ /\|/) return
            if (sc == "ensure") min = 2
            else if (sc == "migrate") min = 2
            else if (sc == "store-path") min = 2
            else if (sc == "space-info") min = 2
            else if (sc == "project-add") min = 3
            else if (sc == "project-set") min = 5
            else if (sc == "project-keywords") min = 4
            else if (sc == "project-service-repo") min = 7
            else if (sc == "project-list") min = 2
            else if (sc == "project-get") min = 3
            else if (sc == "repo-list") min = 3
            else if (sc == "skill-version") min = 3
            else if (sc == "work-add") min = 7
            else if (sc == "work-set") min = 4
            else if (sc == "work-remove") min = 3
            else if (sc == "work-path") min = 4
            else if (sc == "work-rename") min = 6
            else if (sc == "work-reconcile") min = 2
            else if (sc == "work-list") min = 2
            else if (sc == "work-get") min = 3
            else if (sc == "work-services") min = 4
            else if (sc == "work-trigger") min = 4
            else { warn(file, base, "未知子命令: " sc); return }
            if (NP < min) warn(file, base, sc " 至少需要 " (min - 1) " 个参数")
            return
        }
        if (base == "work.sh") {
            if (NP < 1) { warn(file, base, "缺少 <root>"); return }
            sc = P[1]
            if (sc == "rename") { if (NP < 4) warn(file, base, "rename 需要 <root> <old-work-id> <new-work-id>") }
            else if (sc == "purge") { if (NP < 3) warn(file, base, "purge 需要 <root> <workspace>") }
            else if (NP < 3) warn(file, base, "新建工作区至少需要 <root> <project> <branch>")
            return
        }
        if (base == "git-facts.sh") {
            if (NP < 1) { warn(file, base, "缺少子命令"); return }
            sc = P[1]; if (sc ~ /\|/) return
            if (sc == "freshness") min = 3
            else if (sc == "repos" || sc == "status" || sc == "default-branch" || sc == "conflicts") min = 2
            else { warn(file, base, "未知子命令: " sc); return }
            if (NP < min) warn(file, base, sc " 至少需要 " (min - 1) " 个参数")
            return
        }
        if (base == "git-diff-context.sh") {
            min = (P[1] == "batch") ? 3 : 2
            if (NP < min) warn(file, base, "至少需要 " (min - 1) " 个参数")
            return
        }
        if (base == "git-fetch-helper.sh") {
            if (P[1] != "sync" && P[1] != "fetch" && P[1] !~ /\|/) warn(file, base, "未知子命令: " P[1])
            if (NP < 2) warn(file, base, P[1] " 需要 <repo-path>")
            return
        }
        if (base == "repo.sh") {
            if (NP < 1) { warn(file, base, "缺少子命令"); return }
            sc = P[1]; if (sc ~ /\|/) return
            if (sc == "scan" || sc == "link" || sc == "clone") min = 3
            else if (sc == "fetch") min = 2
            else { warn(file, base, "未知子命令: " sc); return }
            if (NP < min) warn(file, base, sc " 至少需要 " (min - 1) " 个参数")
            return
        }
        if (base == "git-commit-helper.sh") {
            if (P[1] != "inspect" && P[1] != "commit" && P[1] !~ /\|/) { warn(file, base, "未知子命令: " P[1]); return }
            min = (P[1] == "commit") ? 3 : 2
            if (NP < min) warn(file, base, P[1] " 至少需要 " (min - 1) " 个参数")
            return
        }
        if (base == "git-push-helper.sh") {
            if (P[1] != "inspect" && P[1] != "push" && P[1] !~ /\|/) { warn(file, base, "未知子命令: " P[1]); return }
            if (NP < 2) warn(file, base, P[1] " 需要 <repo-path>")
            return
        }
        if (base == "harness-diff.sh") {
            if (NP < 3) warn(file, base, "需要 <incoming> <local> 与 --profile update")
            return
        }
        if (base == "harness-backup.sh") {
            if (P[1] != "backup" && P[1] != "restore" && P[1] != "verify" && P[1] !~ /\|/) {
                warn(file, base, "未知子命令: " P[1]); return
            }
            if (NP < 3) warn(file, base, P[1] " 需要 <root> <label|backup-dir>")
            return
        }
        if (base == "scan-secrets.sh") {
            if (NP < 1) warn(file, base, "缺少 <root>")
            return
        }
        if (base == "scan-routes.sh") {
            if (NP < 1) { warn(file, base, "缺少子命令"); return }
            sc = P[1]; if (sc ~ /\|/) return
            if (sc == "resolve" || sc == "show") min = 3
            else if (sc == "list" || sc == "index" || sc == "workflows" || sc == "commands" || sc == "agents") min = 2
            else { warn(file, base, "未知子命令: " sc); return }
            if (NP < min) warn(file, base, sc " 至少需要 " (min - 1) " 个参数")
            return
        }
        if (base == "branch-op.sh") {
            if (NP < 1) { warn(file, base, "缺少子命令"); return }
            sc = P[1]; if (sc ~ /\|/) return
            if (sc == "prepare" || sc == "integrate") min = 7
            else if (sc == "continue" || sc == "abort") min = 5
            else if (sc == "push") min = 9
            else if (sc == "cleanup") min = 6
            else { warn(file, base, "未知子命令: " sc); return }
            if (NP < min) warn(file, base, sc " 至少需要 " (min - 1) " 个参数")
            return
        }
        if (base == "branch-clean.sh") {
            if (NP < 2) warn(file, base, "需要 <root> <workspace>")
            return
        }
        if (base == "git-worktree-helper.sh") {
            if (NP < 1) { warn(file, base, "缺少子命令"); return }
            sc = P[1]; if (sc ~ /\|/) return
            if (sc == "create") min = 5
            else if (sc == "remove") min = 3
            else if (sc == "list") min = 2
            else { warn(file, base, "未知子命令: " sc); return }
            if (NP < min) warn(file, base, sc " 至少需要 " (min - 1) " 个参数")
            return
        }
        if (base == "git-bug-trace.sh") {
            if (NP < 3) warn(file, base, "需要 <repo-path> <file> <line>")
            return
        }
        if (base == "skill-update.sh") {
            if (NP < 2) warn(file, base, "需要 <update-url> <tag>")
            return
        }
        if (base == "check-update.sh" || base == "init-tack.sh" || \
            base == "lint-harness.sh" || base == "lint-shell-portability.sh") {
            if (NP < 1) warn(file, base, "缺少 <root|harness-dir>")
            return
        }
        if (base == "run-plan.sh") {
            if (P[1] != "check" && P[1] !~ /\|/) { warn(file, base, "未知子命令: " P[1]); return }
            if (NP < 2) warn(file, base, "check 需要 <instruction-dir>")
            return
        }
        if (base == "workspace-archive.sh") {
            if (NP < 1) { warn(file, base, "缺少子命令"); return }
            sc = P[1]; if (sc ~ /\|/) return
            if (sc == "list") min = 3
            else if (sc == "move") min = 5
            else { warn(file, base, "未知子命令: " sc); return }
            if (NP < min) warn(file, base, sc " 至少需要 " (min - 1) " 个参数")
            return
        }
        if (base == "wiki-index.sh") {
            if (NP < 1) { warn(file, base, "缺少子命令"); return }
            sc = P[1]; if (sc ~ /\|/) return
            if (sc != "check") { warn(file, base, "未知子命令: " sc); return }
            if (NP < 3) warn(file, base, "check 需要 <root> <project>")
            return
        }
        if (base == "space.sh") {
            if (P[1] != "commit" && P[1] !~ /\|/) { warn(file, base, "未知子命令: " P[1]); return }
            if (NP < 2) warn(file, base, "commit 需要 <root>")
            return
        }
    }
    # 占位符被空格拆开（如 <来源 status.yaml>）时无法可靠计数，直接跳过以免误报
    function unbalanced(A, n,   i, t, o, c) {
        for (i = 1; i <= n; i++) {
            t = A[i]; o = gsub(/</, "", t)
            t = A[i]; c = gsub(/>/, "", t)
            if ((o > 0) != (c > 0)) return 1
        }
        return 0
    }
    function check_cmd(cmd, file,   spath, script, base, rest, n, A, i, t, NP, P, NFL, FL, cmdline) {
        # 只检查真实调用行；纯引用（如 `space.sh commit`）没有 sh/bash/powershell/run.ps1 前缀，跳过
        if (cmd !~ /(^|[[:space:]])(sh|bash|powershell|run\.ps1)([[:space:]]|$)/) return
        if (match(cmd, /script\/[A-Za-z0-9._\/-]+\.sh/)) {
            spath = substr(cmd, RSTART, RLENGTH)
            script = spath; sub(/^.*\//, "", script)
            rest = substr(cmd, RSTART + RLENGTH)
        } else if (match(cmd, /run\.ps1[[:space:]]+[A-Za-z0-9._\/-]+/)) {
            spath = substr(cmd, RSTART, RLENGTH)
            sub(/^run\.ps1[[:space:]]+/, "", spath)
            script = spath
            if (script !~ /\.sh$/) script = script ".sh"
            rest = substr(cmd, RSTART + RLENGTH)
        } else {
            return
        }
        base = script; sub(/^.*\//, "", base)
        if (base ~ /xxx|example|sample/) return

        cmdline = "test -f \"" H "/script/" script "\""
        if (system(cmdline) != 0) {
            warn(file, base, "脚本不存在: harness/script/" script)
            return
        }

        sub(/^["\047]/, "", rest)
        n = tokenize(rest, A)
        if (unbalanced(A, n)) return
        NP = 0; NFL = 0
        split("", P); split("", FL)
        for (i = 1; i <= n; i++) {
            t = A[i]
            sub(/[。；;]+$/, "", t)
            if (t == "") continue
            if (t ~ /^\[/ || t ~ /\]$/) continue
            if (t ~ /^--/) {
                if (t ~ /\|/) continue
                FL[++NFL] = t
                continue
            }
            P[++NP] = t
        }
        check_sig(base, P, NP, FL, NFL, file)
        check_flags(base, FL, NFL, file)
    }
    BEGIN { n_warn = 0 }
    {
        line = $0
        while (match(line, /`[^`]*`/)) {
            span = substr(line, RSTART + 1, RLENGTH - 2)
            if ((span ~ /script\/[A-Za-z0-9._\/-]+\.sh/ || span ~ /run\.ps1[[:space:]]/) \
                && !((FILENAME SUBSEP span) in seen)) {
                seen[FILENAME SUBSEP span] = 1
                check_cmd(span, FILENAME)
            }
            line = substr(line, RSTART + RLENGTH)
        }
        if (($0 ~ /(^|[[:space:]])sh[[:space:]]+[^`]*script\/[A-Za-z0-9._\/-]+\.sh/ || $0 ~ /run\.ps1[[:space:]]+/) \
            && !((FILENAME SUBSEP $0) in seen)) {
            seen[FILENAME SUBSEP $0] = 1
            check_cmd($0, FILENAME)
        }
    }
    END { printf "lint-doc-scripts: %d warning(s)\n", n_warn }
' ${FILES}

exit 0
