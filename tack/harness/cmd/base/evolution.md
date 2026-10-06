---
command: evolution
short: evo
triggers: 进化, 进化harness, harness进化, evolution, evolve, evolve harness
params: 无
summary: 进化 harness——审查 cmd 下每个指令与 AGENTS.md，识别可沉淀为 rule/reference 的内容、可固化为 script 的流程、文档结构优化与 sh 脚本跨平台兼容性，人工确认后执行
---

# evolution 进化 harness

> 让 harness 随使用持续瘦身：cmd 只留**流程骨架与引用**，规则细节进 rule、复杂能力进 reference、确定性步骤进 script。
> 本命令只做**审查与提议**，不擅自改动；任何落盘均经用户确认。
> 两类输入：① 主动审查全部指令文件及 `$root/AGENTS.md`；② 消费各工作区 `status.yaml` 的 `guidance`（任务结束自动采集的用户引导，AGENTS.md 第 11 条）；`close` 时会自动执行同等审查。

## 前置准入条件

- 已是 tack 空间（`$root/harness/cmd/` 存在）

## 指令内容

1. **结构自检（硬门禁）**
   - 动作: 执行 `sh $root/harness/script/lint-harness.sh $root/harness`（Windows 经 run.ps1）
   - 存在 ERROR（frontmatter 缺失/名实不符/四段缺失/路由 token 冲突）：先修复后再进入审查——这类问题属于结构损坏，不作为候选讨论；WARN（short 缺失、reference 孤儿）列入候选清单一并评估
   - 退出码 0 时直接进入下一步

2. **版本检查（更新提醒挂载点）**
   - 动作: 执行 `sh $root/harness/script/check-update.sh $root`（Windows 经 run.ps1；脚本内部双节流，无新版本时静默）
   - 输出协议: 无输出则不提及、直接进入下一步；stdout 非空时为「有新版本」提醒（首行）+ 本机版本至最新版本区间的更新内容摘要（其后各行，可能没有），原样转述并**建议先执行 `update` 再进化**（避免在旧版 harness 上做审查与沉淀，改动可能与新版冲突）；用户坚持继续时进入下一步，不阻塞

3. **枚举全部指令并收集 guidance 素材**
   - 动作: 执行 `sh $root/harness/script/scan-routes.sh commands $root/harness`，取得 base/dev/git 全量命令清单与文件路径；逐个重新读取正文（不相信上下文旧内容）
   - AGENTS.md: 重新读取 `$root/AGENTS.md` 全文（核心约束编号条目、环境变量、沉淀约定等章节）；`<!-- tack:info:start/end -->` 项目信息区块由 project.sh 维护，只读不改
   - guidance: 读取当前工作区 `$work/status.yaml` 的 `guidance`（存在 `$work` 时优先），并扫描 `$root/space/*/status.yaml` 中其余 `status: raw` 条目；汇总去重（同一引导在多个工作区重复出现视为高优先级信号）
   - sh 脚本: 枚举 `$root/harness/script/` 下全部 `.sh`，逐个重新读取正文（不相信上下文旧内容）；这些脚本须在 Windows（经 `run.ps1` 调 Git for Windows bash）、macOS（BSD 工具）、Linux（GNU 工具）三平台均可运行

3. **逐个审查每个指令文件及 `$root/AGENTS.md`**，按以下机会识别候选：
   - **rule 候选**（规则沉淀）
     - 判据: 同一规则/判据/格式/边界在多个命令中重复出现，或某命令正文内嵌了大段可独立复用的规则细节（典型模式：record.md → rule/record-*.md）
     - 要求: 沉淀后 cmd 中对应段落替换为一行引用；rule 文件不参与路由、按需加载，避免常驻上下文膨胀
   - **reference 候选**（复杂独立能力）
     - 判据: 命令引用了篇幅大、非每次执行都需要的方法论或独立操作指南（典型模式：implement.md、tdd.md、grill-with-docs.md）
     - 要求: 独立成文件，cmd 中以「参考 reference：xxx.md」引用，被引用后才加载
   - **script 候选**（流程固化）
     - 判据: 确定性、机械性步骤——文件/骨架生成、字符串拼接、格式与列对齐校验、枚举/ID 合法性检查、状态字段回写等；这类步骤靠口头提示易被模型忽略或做错
     - 要求: 固化为 POSIX sh（Windows 经 `run.ps1` 调用），用**退出码做硬门禁**（不可交付即非 0 阻断）；AI 只保留语义判断与文档撰写职责。脚本必须给出明确的输入参数、退出码语义与最小用例
   - **structure 候选**（文档组织优化）
     - 判据: 按 `harness/rule/doc-structure.md` 审视文件结构——变量/术语定义滞后于首次使用、同一主题/生命周期条目被无关内容打散、有流程关系的条目未按时间序排列、编号重排后存在悬空的"第 N 条"引用
     - 要求: 仅重排章节/条目顺序并同步引用，**不改动条目语义**；落盘后按该 rule「验证」`grep` 文件内编号引用确认无悬空；这类优化不瘦身内容、默认优先级低，但发现悬空引用等高风险问题时升为高
   - **AGENTS.md 专属审查**（与指令文件同等覆盖，候选记入 A 组、来源文件填 `$root/AGENTS.md`）:
     - 常驻精简: 核心约束是否堆叠了可下沉 rule 的细节——常驻上下文只留高频、跨命令的行为边界；细则下沉 rule 后原处保留一行引用。反向检查 rule 中被每次会话依赖的约定是否应上提为核心约束
     - 结构: 按 `harness/rule/doc-structure.md` 审视章节顺序与核心约束编号条目（定义前置、同类聚拢、时间序、悬空的"第 N 条"引用）
     - 区块边界: `<!-- tack:info:start/end -->` 项目信息区块由 project.sh 维护、「沉淀约定」区块由 record 维护，evolution **只读不直接改**这两个区块
     - 候选类型: AGENTS.md 只产出 structure 候选与 rule 候选（细则下沉），不产出 reference/script 候选
   - **sh 脚本跨平台兼容性审查**（第 2 步枚举的每个 `.sh`，候选记入 A 组、来源文件填脚本路径）:
     - 判据: 逐个脚本核对 POSIX 兼容性——① 不依赖 `sed -i`（GNU/BSD 语义不同，就地修改应「写临时文件 + `mv`」）② 不引入 bashism（只用 `set -eu`、`[ ]`、`case` 等 POSIX 特性，不依赖 bash 数组/`[[`/进程替换）③ `sh -n` 语法检查通过 ④ 路径用正斜杠、不硬编码平台特定路径 ⑤ 不依赖单一平台才有的工具或版本（如 GNU 特有选项）
     - 要求: 发现问题归入 script 候选（修复使其跨平台），候选类型仍为 script；修复后必跑 `sh -n` 验证语法，并在三平台语义上核对（实际执行环境至少覆盖当前平台，其余平台按判据静态核对）；Windows 上跑 `sh -n` 见 `harness/rule/windows-env.md`「Shell 调用」——禁用 PATH 里的 `bash`（可能命中 WSL），须用 Git for Windows `sh.exe`
     - 优先级: 兼容性缺陷会直接导致跨平台运行失败，默认高优先级
   - 无机会的命令明确标注「无」，不得为凑数制造候选
   - **guidance 候选**（实战引导固化）: 对第 2 步收集的 raw 条目，按 `harness/rule/record-classification.md` 判据评估——跨工作区可复用的操作习惯/流程修正才入候选，一次性过程信息排除；条目自带的 `candidate`（建议固化点）作为初判，仍需核对目标文件现状决定融合或新建

4. **输出候选清单**
   - 动作: 分两组给出表格——
     - A 组·指令审查：来源文件 | 候选类型（rule/reference/script/structure）| 建议落点/脚本名 | 待沉淀内容摘要 | 理由 | 优先级（高=重复出现或易错，中=可复用，低=锦上添花）
     - B 组·guidance 实战：来源工作区/条目 id | 场景与用户引导 | 建议落点（workflow/cmd/rule）| 融合或新建 | 理由 | 出现次数/优先级
   - 依赖标注: 每个候选标明与其他候选的依赖关系——「无依赖（可并行）」或「依赖候选 X（X 落盘后本候选才可执行）」；典型依赖：script 候选需等待其被引用的 rule/reference 文件落盘
   - 边界: 一次审查只提议，**不直接修改任何文件、不新建脚本**

5. **用户确认后执行**
   - 输入: 用户挑选要执行的候选（可只选部分），不选则结束
   - 执行顺序: 按第 4 步的依赖标注分组——无依赖的候选**同一轮并行落盘**（多个文件的新建/修改在同一批工具调用中发出）；有依赖的候选按依赖顺序串行，前序落盘后再执行
   - rule / reference 候选: 按 `harness/rule/record-classification.md` 归类，走 `record` 流程——先扫描已有文件，**能融合则融合**，确无合适条目才新建
   - workflow / cmd / AGENTS.md 候选（guidance 组主要落点）: 直接最小化修改对应文件——只融入该引导要求的流程/判据或仅重排顺序，不重写无关段落；属于新命令/新工作流的按 record 流程新建；AGENTS.md 的项目信息与沉淀约定区块不直接改
   - script 候选: 实现前向用户说明「新增文件、必要性、为何 AI 直接执行不可靠」，经确认后按最小集合逐个实现；脚本须与 `harness/script/` 现有风格一致；跨平台修复候选（第 3 步 sh 审查）直接改既有脚本，改完必跑 `sh -n`
   - 同步: 从对应 cmd 中删除已沉淀内容、替换为引用或脚本调用；保持最小化修改，不重写无关段落
   - guidance 回写: 每完成一个 B 组候选，将其来源条目的 `status` 置 `distilled`，并另起一行按固定格式注明落点：`落点: <相对 $root 的路径>`（多落点空格分隔，格式见 `harness/template/work-status.yaml`；跨工作区重复条目一并回写）；用户放弃的置 `dismissed`，未选中的保留 `raw`

6. **验证**
   - 动作: 执行 `sh $root/harness/script/lint-harness.sh $root/harness` 确认结构自检 0 ERROR（退出码 0），再执行 `sh $root/harness/script/scan-routes.sh list $root/harness` 确认全部命令与角色正常注册；新增 script 实跑一次最小用例验证退出码；执行 `sh $root/harness/script/check-guidance.sh $root` 全局核对各工作区 distilled 条目的落点（BROKEN 项修复后再结束，OLDFMT/NOLAND 项提示补正）；人工审阅全部改动后生效

## 框架自动提交（无需用户操作）

- 动作: 仅审查、未落盘时无需提交；用户确认执行并产生 rule/reference/script/cmd 改动后，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): harness evolution"` 自动提交（无变更自动跳过）
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] 第 1 步 lint-harness 自检已跑，ERROR 已先行修复（WARN 已纳入评估）
- [ ] cmd 下每个指令文件均已审查，候选或「无」结论覆盖无遗漏
- [ ] `$root/AGENTS.md` 已审查（常驻精简性、章节/编号结构、与 rule 重复），项目信息与沉淀约定区块未被手改
- [ ] 各工作区 status.yaml 的 raw guidance 已收集评估，B 组候选或排除结论覆盖无遗漏
- [ ] 候选清单含类型、落点、内容摘要、理由与优先级；未在确认前改动文件
- [ ] 已落盘的 rule/reference 优先融合了已有条目；script 有明确参数与退出码语义且最小用例通过
- [ ] structure 候选仅重排未改语义，重排后按 `doc-structure.md` 验证无悬空编号引用
- [ ] `harness/script/` 下每个 `.sh` 已审查跨平台兼容性（POSIX 兼容、无 `sed -i`、无 bashism、`sh -n` 通过），缺陷已修复或列入候选
- [ ] 沉淀后的 cmd 只留流程骨架与正确引用，无残留的规则细节重复
- [ ] 已处理的 guidance 条目回写为 distilled（按 `落点: <相对 $root 路径>` 注明）或 dismissed，未选中保留 raw
- [ ] 收尾 lint-harness 退出码 0、scan-routes 路由表完整、check-guidance 无 BROKEN 项；全部改动经人工审阅确认

## 下一步建议

- 用 `help` 复查路由表；新固化的脚本在下一次执行对应命令时自动生效
