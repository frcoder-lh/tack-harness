# AGENTS.md

> 本文件面向在 **tack-harness 源仓库**工作的 AI 代理，沉淀在此开发、改脚本、发版时必须遵守的约定。
> 随发布包分发、驱动用户 tack 空间的说明在 [tack/AGENTS.md](tack/AGENTS.md)，两者用途不同，不互相复制内容。

## 仓库定位

- 本仓库是 tack skill 的源仓库：[SKILL.md](SKILL.md)（AI 消费的 skill 入口，含版本号）、`tack/harness/`（物化到用户空间的骨架）、`install.sh` / `release.sh`（安装与发布脚本）
- 发布由 CI 完成：推送匹配 `V*.*.*` 的 tag 触发 [.github/workflows/release.yml](.github/workflows/release.yml)，自动打包并创建 GitHub Release，**不手工制作发布包**
- README.md（中文）/ README.en.md（English）面向人类读者，SKILL.md 面向运行时AI，AGENTS.md 面向开发时AI，三处内容不重复

## 发布与版本号（release.sh）

1. **版本号单一事实源（single source of truth）**：Git tag（`Vx.y.z`）与 [SKILL.md](SKILL.md) front matter 的 `version: "Vx.y.z"` 必须一致。发版时由 `release.sh` 自动同步，禁止只打 tag 不改正文，也禁止手工改两处
2. 同步随发布提交一起落库，不产生游离的「bump version」提交：
   - 多个未推送提交：`reset --soft` 压缩时把 SKILL.md 修正并入唯一的 release 提交
   - 仅 1 个未推送提交：不压缩，用 `git commit --amend --no-edit` 把修正折入该提交，保留原提交信息
   - 版本已与目标 tag 一致：跳过修改、不 amend，直接打 tag
3. **fast-forward 安全模型**：只压缩/amend「尚未推送」的提交，新提交父节点始终是 `origin/<branch>` 头，普通 push 即为 fast-forward，**严禁 force push**；远端有本地缺失提交时脚本会中止，先 rebase/merge 后再发
4. 修改发布流程后先 `sh release.sh -n` dry-run，确认「发布计划」（版本同步前后值、压缩方式、提交清单）无误再执行
5. **README 随发版更新（AI 职责，非脚本）**：发版前由 AI 全仓扫描本次新增/变更能力，在保持 README 整体结构不变的前提下融入对应章节；扫描源与落点——
   - `tack/harness/script/*.sh` → README「空间结构」script/ 清单、「安全模型」表
   - `tack/harness/cmd/**/*.md` → README「命令参考」表（7.1/7.2/7.3）
   - `tack/harness/workflow/*.md` → README「工作流模型」表
   - `CHANGELOG.md` 本版本段落 → 够格的新能力补入「核心特性」表
   - 原则：只融入已落地的新增/变更能力，不重写既有条目、不动章节结构
6. **面向人类读者的文档中英双语同步**：`README.md`↔`README.en.md`、`CHANGELOG.md`↔`CHANGELOG.en.md` 同版本条目一一对应、同一提交内同步落库，禁止只改一种语言；发版前 `release.sh` 校验两份 CHANGELOG 均含目标 tag 段落（任一缺失即中止），CI 抽取双份段落拼接双语 Release body，`check-update.sh`/`update` 双语展示更新内容；新增/变更命令与工作流的英文触发词须同步写入两份 README 的命令/工作流表；安装（install.sh）、升级（skill-update.sh）分发清单必须同时包含两份 README 与两份 CHANGELOG

## POSIX sh 脚本规范

仓库内 `.sh` 均为 `#!/bin/sh`，须同时兼容 Git for Windows（GNU 工具）与 macOS（BSD 工具）：

- **禁止依赖 `sed -i`**：GNU 与 BSD 的 `-i` 参数语义不同；就地修改一律「写临时文件 + `mv`」，例如 `sed '...' file > tmp && mv tmp file`
- 结构化文本的替换必须限定地址范围，防止误伤正文——如 SKILL.md front matter 用 `2,/^---$/`；执行前先校验目标字段存在（文件缺失/字段缺失即报错中止），避免静默产出错误结果
- 只用 POSIX 特性（`set -eu`、`[ ]`、`case`），不引入 bashism
- **变量引用默认写 `"${VAR}"`**：命名变量一律「双引号 + 花括号」——花括号界定变量名边界（如拼接后缀 `"${name}_tmp"`），双引号防止词分割与通配展开；仅一位特殊参数保留惯用简写：`"$0"`、`"$1"`…`"$9"`、`"$@"`、`"$*"`、`"$#"`、`"$?"`、`"$$"`、`"$!"`（两位以上位置参数仍须 `"${10}"`）；刻意利用分词/glob 而不加引号仅限局部且意图明显（如命令位置的 `$PRIV`、`for x in $items`）；`${var:-x}`、`$((...))`、`"$(...)"` 按各自语法书写
- 新建或修改 `.sh` 后必须 `sh -n` 语法检查

## 文档与注释写作纪律（硬约束）

编写或修改仓库内任何 markdown 文件与代码注释（`.sh`、`.ps1`、CI yml 中的注释等）时：

- **非必要的反向描述不保留**：事实一旦被取消或移除、且没有"必须阻止该行为"的意图，直接删除相关描述——不留「不再做 X」「X 已废弃」式反向描述，不追加「不要做 X」「注意别再 X」式否定补丁；旧事实不存在了，文字里就不再出现它。禁止以否定句给已删除的事实"立碑"或用文档补丁替代真实逻辑收敛
- **否定表述只用于真实禁令**：某行为当下仍可能被执行、必须明确阻止时（如「严禁 force push」「禁止 `git add -A`」「禁止依赖 `sed -i`」）才使用否定句，并写清阻止的行为与原因
- **删除前确认无消费者**：先全仓 grep 确认该事实无文档引用、编号交叉引用、脚本调用或字段读写等真实消费者再删，删除后同步清理失效编号与交叉引用；判断不准时不擅自删，在汇报中提出交用户决定
- 随包分发的同一硬约束在 [tack/AGENTS.md](tack/AGENTS.md) 核心约束第 13 条（面向用户空间内的 md 文件与代码注释）；存量文档的反向描述清理由 `evolution` 命令的 cleanup 候选承接，两处规则口径一致、不重复展开细节

## 变更验证纪律

`release.sh` 等带写操作的脚本，不得仅凭静态阅读交付，按以下顺序验证：

1. `sh -n <script>.sh` 语法检查
2. 关键片段（如 sed 读写）先在**临时副本**上验证输入输出
3. 端到端在**隔离临时仓库**验证：`mktemp -d` 下 `git init --bare` 模拟 origin，clone 出工作副本，构造不同状态覆盖全部分支路径（本次覆盖：dry-run 零改动、多提交压缩、单提交 amend、版本已一致跳过），并断言 HEAD 位置、工作区干净、本地/远端 tag、被改文件内容
4. **绝不在真实仓库直接试跑发布脚本**；临时测试脚本放系统 temp 目录，验证完毕立即删除

## 提交约定（任务完成自动本地提交）

- 一项任务完成且按「变更验证纪律」验证通过（`sh -n`、E2E/ lint 等该过的检查全过）后，**自动本地 commit，无需等用户下达"提交"指令**；提交后在汇报中说明 commit 哈希与内容
- **一次任务一个 commit**：以用户交付的任务为粒度，不把任务内部的实施步骤拆成多个 commit，也不自行制造"内部子任务"提交
- **只本地提交，不自动 push**：commit 是默认动作，push 与打 tag/发版仍必须有用户明确指令（发版走 release.sh，见上节）
- **精确暂存**：只 `git add` 本次任务实际改动的文件，禁止 `git add -A` / `git add .`——工作区可能存在 CRLF 噪音（整文件脏 diff、无内容变化）或会话前遗留改动，须先 `git status` / `git diff` 甄别后排除
- 不 amend、不 reset 历史、不 force push（与 fast-forward 安全模型一致）；commit message 概括任务意图，多行正文用多个 `-m`（PowerShell 宿主不支持 heredoc）
- 例外：用户明确要求"先不提交/攒着"时遵从；拿不准任务是否已完成（验证未过、等待用户确认）时先问再提

## Windows（PowerShell 宿主）执行要点

通用纪律统一见 [tack/harness/rule/windows-env.md](tack/harness/rule/windows-env.md)（bash 完整路径、禁止内联含 `$`/引号/正则的命令、stderr 噪音识别、LF 换行），此处只保留本仓库特化：

- 本仓库 [.gitattributes](.gitattributes) 统一规定 `* text=auto eol=lf`——文本文件在索引与工作区一律 LF（含 `.ps1` 等未单列后缀），`auto` 保留二进制嗅探；唯一例外是 `*.bat` / `*.cmd` 强制 CRLF（cmd.exe 解析器不能可靠支持 LF-only）；新建文本文件后用 `git status` / `git diff` 抽查是否整文件脏 diff
