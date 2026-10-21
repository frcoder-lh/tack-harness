---
command: evolution
short: evo
triggers: 进化, 进化harness, harness进化, evolution, evolve, evolve harness
params: 无
summary: 进化 harness——校准 AGENTS.md 工作区登记与 space/ 实际目录；审查 cmd 下每个指令与 AGENTS.md，识别可沉淀为 rule/reference 的内容、可固化为 script 的流程、文档结构优化、过时事实与反向描述清理；核对文档中的脚本调用签名与脚本实际参数；按 coding-standards-shell.md 三平台基线审查全部 sh 脚本；sh 脚本三平台兼容不符合项当场修正；其余落盘经人工确认
---

# evolution 进化 harness

> 让 harness 随使用持续瘦身：cmd 只留**流程骨架与引用**，规则细节进 rule、复杂能力进 reference、确定性步骤进 script。
> 本命令只做**审查与提议**，落盘原则上经用户确认；**唯一例外**是 sh 脚本三平台兼容不符合项——纯机械合规修正发现即当场修复（见第 5 步）。
> 两类输入：① 主动审查全部指令文件及 `$root/AGENTS.md`；② 消费各工作区 `status.yaml` 的 `guidance`（任务结束自动采集的用户引导，AGENTS.md 第 11 条）；`close` 时会自动执行同等审查。

## 前置准入条件

- tack 空间（`$root/harness/cmd/` 存在）或源仓库（`$root/tack/harness/cmd/` 存在）

## 指令内容

1. **运行模式判定与结构自检（硬门禁）**
   - 模式判定: 若 `$root/harness/cmd` 存在，设 `HARNESS_DIR="$root/harness"`（空间模式）；否则若 `$root/tack/harness/cmd` 存在，设 `HARNESS_DIR="$root/tack/harness"`（源仓库模式）；两者均不存在时报错退出
   - 动作: 执行 `sh $HARNESS_DIR/script/lint-harness.sh $HARNESS_DIR`
   - 存在 ERROR（frontmatter 缺失/名实不符/四段缺失/路由 token 冲突）：先修复后再进入审查——这类问题属于结构损坏，不作为候选讨论；WARN（short 缺失、reference 孤儿）列入候选清单一并评估
   - 退出码 0 时直接进入下一步

2. **版本检查（更新提醒挂载点）**
   - 空间模式: 按 `$HARNESS_DIR/rule/update-check.md` 执行 `sh $HARNESS_DIR/script/check-update.sh $root`；有新版本时原样转述并**建议先执行 `update` 再进化**（避免在旧版 harness 上做审查与沉淀，改动可能与新版冲突），用户坚持继续时进入下一步、不阻塞；无输出直接进入下一步
   - 源仓库模式: 跳过本步（无 skill_version / update-state）

3. **工作区登记校准**
   - 空间模式: 执行 `sh $HARNESS_DIR/script/project.sh work-reconcile $root`，对账 AGENTS.md 项目信息区块的 work 条目与 `$root/space/` 实际目录（脚本只报告差异、零写入）；按输出类型逐类给出处理建议，经用户确认后落盘：
     - `MISSING_DIR`（条目在、目录已缺失）：移除孤儿条目——`sh $HARNESS_DIR/script/project.sh work-remove $root <work_id> --no-commit`
     - `UNREGISTERED`（目录在、无条目）：用输出的 status.yaml 概要（work_id / project / branch / services）补登记——`sh $HARNESS_DIR/script/project.sh work-add $root <project> <work_id> "" $root/space/<目录名> <branch> "<services>" --no-commit`；status.yaml 缺失、概要为 `-` 或 project 为空时报告事实，请用户确认 project/work_id/branch 后再补；description 与 trigger_words 留空，提示用户日后补充
     - `STALE_COMPLETED`（条目已 completed 但目录仍在，旧版 close 归档残留）：经用户确认后按 close 同等方式清理——确认交付内容无需保留后，执行 `sh $HARNESS_DIR/script/work.sh purge $root <目录名>`（脚本自动校验无残留 worktree）并 `project.sh work-remove --no-commit`
     - `PATH_MISMATCH`（登记 work_path 与 status.yaml 中 work_id 实际所在目录不符，重命名中断残留）：以磁盘实际目录为准校准——`sh $HARNESS_DIR/script/project.sh work-path $root <work_id> $root/space/<实际目录名> --no-commit`
   - 边界: 属于工作区数据校准、不是 harness 演进，不进第 6 步 A/B 候选表；`SUMMARY` 行 `issues=0` 时一句话说明并跳过；校准动作集中在本步完成，后续审查不再重复对账；源仓库模式跳过本步（无项目信息区块与 `space/`）

4. **枚举全部指令并收集 guidance 素材**
   - 动作: 执行 `sh $HARNESS_DIR/script/scan-routes.sh commands $HARNESS_DIR`，取得 base/dev/git 全量命令清单与文件路径；逐个重新读取正文（不相信上下文旧内容）
   - AGENTS.md: 重新读取 `$root/AGENTS.md` 全文（核心约束编号条目、环境变量、项目信息等章节）；`<!-- tack:info:start/end -->` 项目信息区块由 project.sh 维护，只读不改（第 3 步校准除外）；源仓库模式无项目信息区块，跳过该区块说明
   - guidance: 读取当前工作区 `$work/status.yaml` 的 `guidance`（存在 `$work` 时优先），并扫描 `$root/space/*/status.yaml` 中其余 `status: raw` 条目；汇总去重（同一引导在多个工作区重复出现视为高优先级信号）；源仓库模式无 `space/`，跳过
   - sh 脚本: 枚举 `$HARNESS_DIR/script/` 下全部 `.sh`，逐个重新读取正文（不相信上下文旧内容）；这些脚本须在 Windows（Git for Windows）、macOS（BSD 工具）、Linux（GNU 工具）三平台均可运行

5. **逐个审查每个指令文件及 `$root/AGENTS.md`**，按以下机会识别候选：
   - **rule 候选**（规则沉淀）
     - 判据: 同一规则/判据/格式/边界在多个命令中重复出现，或某命令正文内嵌了大段可独立复用的规则细节（典型模式：record.md → rule/record-*.md）
     - 要求: 沉淀后 cmd 中对应段落替换为一行引用；rule 文件不参与路由、按需加载，避免常驻上下文膨胀
   - **reference 候选**（复杂独立能力）
     - 判据: 命令引用了篇幅大、非每次执行都需要的方法论或独立操作指南（典型模式：implement.md、tdd.md、grill-with-docs.md）
     - 要求: 独立成文件，cmd 中以「参考 reference：xxx.md」引用，被引用后才加载
   - **script 候选**（流程固化）
     - 判据: 确定性、机械性步骤——文件/骨架生成、字符串拼接、格式与列对齐校验、枚举/ID 合法性检查、状态字段回写等；这类步骤靠口头提示易被模型忽略或做错
     - 要求: 固化为 POSIX sh，用**退出码做硬门禁**（不可交付即非 0 阻断）；AI 只保留语义判断与文档撰写职责。脚本必须给出明确的输入参数、退出码语义与最小用例
   - **interface 候选**（文档-脚本调用签名一致性，硬检查）
     - 判据: 对本次覆盖的 cmd/workflow/rule 文件及 `$root/AGENTS.md` 中出现的 `sh $root/harness/script/<name>.sh <args...>` 调用（脚本实现位于 `$HARNESS_DIR/script/`），提取脚本名与实参占位序列，与脚本头部 Usage 注释及参数解析（`$1`/`$2`…、`case` 分支）逐项比对——参数顺序、必填/可选、占位名任一不一致即候选；典型：文档写 `create <root> <workspace> <repo-name> <branch>`，脚本实际为 `<root> <workspace> <branch> <repo-name>`，照文档执行报 `Repo not found`
     - 要求: 以脚本为事实源修正文档调用（顺序/占位名/必填项），同一脚本的全部调用点一并核对；脚本自身 Usage 注释与参数解析不一致时按 script 候选处理
     - 为什么需要: 结构自检只覆盖 frontmatter/路由/四段，cleanup 只删无事实支撑的描述，均不核对「文档写的参数顺序」与「脚本实际解析」是否一致
   - **structure 候选**（文档组织优化）
     - 判据: 按 `$HARNESS_DIR/rule/doc-structure.md` 审视文件结构——变量/术语定义滞后于首次使用、同一主题/生命周期条目被无关内容打散、有流程关系的条目未按时间序排列、编号重排后存在悬空的"第 N 条"引用
     - 要求: 仅重排章节/条目顺序并同步引用，**不改动条目语义**；落盘后按该 rule「验证」`grep` 文件内编号引用确认无悬空；这类优化不瘦身内容、默认优先级低，但发现悬空引用等高风险问题时升为高
   - **cleanup 候选**（过时事实与非必要反向描述清理）
     - 判据: 按 `$root/AGENTS.md` 核心约束第 13 条「非必要的反向描述不保留」（硬约束，规则细节不在此重复），审查本次覆盖的每个文件（cmd、AGENTS.md，以及候选落盘涉及的 workflow/rule/reference）中所述事实是否仍然成立——命令/工作流/字段/脚本/流程一旦被取消或移除，相关描述即失去事实支撑，应**整段删除**，不留反向描述、不追加否定补丁；同时顺带审查 `$HARNESS_DIR/script/` 下脚本注释中同类表述
     - 方法: 删除前先全仓 grep 建立该事实的引用图谱（写入者/读取者/脚本/文档交叉引用），确认无真实消费者后再删；删除后按 `$HARNESS_DIR/rule/doc-structure.md` 验证无悬空编号与交叉引用。是否仍有消费者判断不准时，不擅自删，降级为候选交用户确认
     - 与 structure 区别: structure 只重排顺序、不改语义；cleanup 直接移除无事实支撑的内容
     - 要求: 落盘为纯删除（连带失效的编号、交叉引用一并同步），不借删除之名改写其余条目语义
   - **AGENTS.md 专属审查**（与指令文件同等覆盖，候选记入 A 组、来源文件填 `$root/AGENTS.md`）:
     - 常驻精简: 核心约束是否堆叠了可下沉 rule 的细节——常驻上下文只留高频、跨命令的行为边界；细则下沉 rule 后原处保留一行引用。反向检查 rule 中被每次会话依赖的约定是否应上提为核心约束
     - 结构: 按 `$HARNESS_DIR/rule/doc-structure.md` 审视章节顺序与核心约束编号条目（定义前置、同类聚拢、时间序、悬空的"第 N 条"引用）
     - 区块边界: `<!-- tack:info:start/end -->` 项目信息区块由 project.sh 维护（本命令仅在第 3 步经用户确认后以 project.sh 校准，审查阶段只读），evolution 不直接手改该区块
     - 候选类型: AGENTS.md 产出 structure、rule（细则下沉）、interface（文档-脚本签名一致性）与 cleanup（过时事实/反向描述）候选，不产出 reference/script 候选
   - **sh 脚本三平台兼容审查（不符合即修，不走候选确认）**（第 4 步枚举的每个 `.sh` 逐个执行）:
     - 机检: 先执行 `sh $HARNESS_DIR/script/lint-shell-portability.sh $HARNESS_DIR`；任何 ERROR 按下列即修边界当场修正并重跑至退出码 0，lint 未覆盖的语义项继续人工核对
     - 判据: 严格按 `$HARNESS_DIR/rule/coding-standards-shell.md` 的三平台基线逐条核对——变量引用、bashism 禁用、外部命令共有选项与 `mktemp` 模板、sed 方言、路径规范等细则均以该文件为准；`sh -n` 语法检查须通过
     - 即修边界: 不符合项**发现后当场原地修正**，不列入候选、不等用户确认——这些是纯机械的合规修正，修正时必须保持脚本行为、参数与退出码语义不变，同一脚本内的存量不符合项一次性全量修正（不限于本次改动附近）；每修一个脚本必跑 `sh -n`，全部修正后在汇报中逐脚本列出修正项。若某问题的修法涉及行为或逻辑选择（非纯合规），立即停止直接修改、降级为 script 候选交用户确认
     - 平台核对: 实际执行环境至少覆盖当前平台，其余平台按 `coding-standards-shell.md` 静态核对——Linux（GNU 工具）/ macOS（BSD 工具）/ Windows（Git for Windows GNU 工具）三平台均须可运行；`sh -n` 只校验 shell 语法，不校验外部命令选项与 sed 表达式，其余细则按该 rule 逐条核对；Windows 上跑 `sh -n` 见 `$HARNESS_DIR/rule/windows-env.md`「Shell 调用」——禁用 PATH 里的 `bash`（可能命中 WSL），须用 Git for Windows `sh.exe`
   - 无机会的命令明确标注「无」，不得为凑数制造候选
   - **guidance 候选**（实战引导固化）: 对第 4 步收集的 raw 条目，按 `$HARNESS_DIR/rule/record-classification.md` 判据评估——跨工作区可复用的操作习惯/流程修正才入候选，一次性过程信息排除；条目自带的 `candidate`（建议固化点）作为初判，仍需核对目标文件现状决定融合或新建

6. **输出候选清单**
   - 动作: 分两组给出表格——
     - A 组·指令审查：来源文件 | 候选类型（rule/reference/script/interface/structure/cleanup）| 建议落点/脚本名 | 待沉淀内容摘要 | 理由 | 优先级（高=重复出现或易错，中=可复用，低=锦上添花）
     - B 组·guidance 实战：来源工作区/条目 id | 场景与用户引导 | 建议落点（workflow/cmd/rule）| 融合或新建 | 理由 | 出现次数/优先级；源仓库模式无工作区，B 组为空
   - 即修项单列: 第 5 步 sh 脚本三平台兼容审查当场修正的内容不进候选表，另以「脚本 | 修正项 | sh -n 结果」清单随候选表一并汇报
   - 依赖标注: 每个候选标明与其他候选的依赖关系——「无依赖（可并行）」或「依赖候选 X（X 落盘后本候选才可执行）」；典型依赖：script 候选需等待其被引用的 rule/reference 文件落盘
   - 边界: 一次审查只提议，**不直接修改任何文件、不新建脚本**；唯一例外是第 5 步 sh 脚本三平台兼容审查的当场合规修正（不改变脚本行为）；第 3 步工作区校准已经用户确认单独落盘，不在本表

7. **用户确认后执行**
   - 输入: 用户挑选要执行的候选（可只选部分），不选则结束
   - 执行顺序: 按第 6 步的依赖标注分组——无依赖的候选**同一轮并行落盘**（多个文件的新建/修改在同一批工具调用中发出）；有依赖的候选按依赖顺序串行，前序落盘后再执行
   - rule / reference 候选: 按 `$HARNESS_DIR/rule/record-classification.md` 归类，走 `record` 流程——先扫描已有文件，**能融合则融合**，确无合适条目才新建
   - workflow / cmd / AGENTS.md 候选（guidance 组主要落点）: 直接最小化修改对应文件——只融入该引导要求的流程/判据或仅重排顺序，不重写无关段落；属于新命令/新工作流的按 record 流程新建；项目信息区块的改动只走第 3 步 project.sh 校准
   - script 候选: 实现前向用户说明「新增文件、必要性、为何 AI 直接执行不可靠」，经确认后按最小集合逐个实现；脚本须与 `$HARNESS_DIR/script/` 现有风格一致；第 5 步 sh 脚本三平台兼容审查不符合项已在审查阶段当场修正（不占候选），涉及行为/逻辑选择的 script 候选仍在本步确认后实施
   - 同步: 从对应 cmd 中删除已沉淀内容、替换为引用或脚本调用；保持最小化修改，不重写无关段落
   - guidance 回写: 每完成一个 B 组候选，执行 `sh $HARNESS_DIR/script/work-status.sh <来源工作区>/status.yaml guidance <id> distilled <落点路径...>`（多落点空格分隔，脚本同步写 `status` 与 `落点:` 行，格式见 `$HARNESS_DIR/template/work-status.yaml`；跨工作区重复条目逐个回写）；用户放弃的执行 `sh $HARNESS_DIR/script/work-status.sh <来源工作区>/status.yaml guidance <id> dismissed`，未选中的保留 `raw`

8. **验证**
   - 动作: 执行 `sh $HARNESS_DIR/script/lint-harness.sh $HARNESS_DIR` 确认结构自检 0 ERROR（退出码 0），再执行 `sh $HARNESS_DIR/script/lint-shell-portability.sh $HARNESS_DIR` 确认三平台可移植性 0 ERROR，再执行 `sh $HARNESS_DIR/script/scan-routes.sh list $HARNESS_DIR` 确认全部命令与角色正常注册；新增 script 实跑一次最小用例验证退出码；空间模式再执行 `sh $HARNESS_DIR/script/check-guidance.sh $root` 全局核对各工作区 distilled 条目的落点（BROKEN 项修复后再结束，OLDFMT/NOLAND 项提示补正），源仓库模式跳过 check-guidance；人工审阅全部改动后生效

## 框架自动提交（无需用户操作）

- 动作: 仅审查、未落盘时无需提交；空间模式下产生 rule/reference/script/cmd 改动（含第 5 步 sh 三平台即修项，即使用户最终未选任何候选），或第 3 步工作区校准产生 AGENTS.md 条目变更/工作区目录删除后，执行 `sh $HARNESS_DIR/script/space.sh commit $root "chore(tack): harness evolution"` 自动提交（无变更自动跳过；第 3 步校准动作均以 `--no-commit` 调用，统一在本步提交）；源仓库模式不执行框架自动提交，按源仓库自身提交约定处理
- 边界: 遵守 `$HARNESS_DIR/rule/git-boundary.md`

## 后置完成检验

- [ ] 第 1 步 lint-harness 自检已跑，ERROR 已先行修复（WARN 已纳入评估）
- [ ] 空间模式第 3 步工作区登记校准已执行：MISSING_DIR / UNREGISTERED / STALE_COMPLETED / PATH_MISMATCH 四类差异均经用户确认处理（移除条目/补登记/purge+移除/校准路径），无差异时已明确说明；校准只经 project.sh / work.sh 落盘，未手改项目信息区块；源仓库模式已明确说明跳过
- [ ] cmd 下每个指令文件均已审查，候选或「无」结论覆盖无遗漏
- [ ] `$root/AGENTS.md` 已审查（常驻精简性、章节/编号结构、与 rule 重复），项目信息区块未被手改
- [ ] 各工作区 status.yaml 的 raw guidance 已收集评估，B 组候选或排除结论覆盖无遗漏
- [ ] 候选清单含类型、落点、内容摘要、理由与优先级；未在确认前改动文件
- [ ] 已落盘的 rule/reference 优先融合了已有条目；script 有明确参数与退出码语义且最小用例通过
- [ ] structure 候选仅重排未改语义，重排后按 `doc-structure.md` 验证无悬空编号引用
- [ ] 被审查文件中的过时事实与反向描述已识别：无事实支撑且非真实禁令的描述已列为 cleanup 候选（删除前确认无真实消费者、删除后无悬空引用）
- [ ] `$HARNESS_DIR/script/` 下每个 `.sh` 已按 `coding-standards-shell.md` 三平台基线逐条审查，`lint-shell-portability.sh` 退出码 0；不符合项已当场修正（行为/退出码语义不变）且 `sh -n` 通过；涉及逻辑选择的已降级为 script 候选，修正项已逐条汇报
- [ ] 文档中全部脚本调用已与脚本 Usage 及参数解析逐个核对：参数顺序、必填项、占位名一致；不一致项已按 interface 候选修正
- [ ] 沉淀后的 cmd 只留流程骨架与正确引用，无残留的规则细节重复
- [ ] 已处理的 guidance 条目回写为 distilled（按 `落点: <相对 $root 路径>` 注明）或 dismissed，未选中保留 raw
- [ ] 收尾 lint-harness 退出码 0、scan-routes 路由表完整；空间模式 check-guidance 无 BROKEN 项；全部改动经人工审阅确认

## 下一步建议

- 用 `help` 复查路由表；新固化的脚本在下一次执行对应命令时自动生效
