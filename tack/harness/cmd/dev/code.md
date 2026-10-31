---
command: code
short: c
triggers: 编码, 开发, 写代码, code, coding, develop, write code
params: [任务ID（可选，默认按依赖关系连续推进全部就绪任务）]
summary: 编码前先判定涉及仓库并确保就绪（主仓库缺失转 repo、worktree 缺失转 worktree），用户明确要求时仅交付代码片段、不编译运行；按 tasks 依赖连续/并行开发，复用已有逻辑、自动按最优解，尽量不打扰用户
---

# code 编码

> development 工作流进入 developing 的命令：按 plan 确定的模块与任务依赖关系组织开发。
> **默认行为**：依赖就绪的任务连续开发、可并行的并行推进，除受阻或必须用户决断外不中断；决策已在 plan 环节前置关闭。
> **编码前先完成仓库准入判定**：明确当前需求涉及哪些仓库并确保就绪；仅当用户明确说明「不需要仓库、只生成代码片段、不需要编译和运行」时进入片段模式。

## 前置准入条件

- 已确定当前工作区 `$work`
- 待执行任务所属 story 的 plan 已确认且回执有效，`$work/status.yaml` 的 tasks 列表非空；准入按 `execution-efficiency.md` 核对
- plan.md 的「决策记录」中需用户决断的事项已关闭
- **仓库准入已判定**：已汇总本批任务涉及的仓库清单；仓库模式（默认）下各仓库在 `$root/repo/<name>` 存在且 `$work/repo/<name>` 有可用 worktree，未就绪须先转 `repo` / `worktree`（见指令内容第 1 步）；片段模式（用户明确选择）豁免本项
- 仓库模式下所有代码改动只能在 `$work/repo/<repo-name>/`（git worktree）内，禁止直接修改 `$root/repo/`；片段模式不创建、不改动任何仓库文件，仅在回复中交付代码片段

## 输入源与加载

输入源统一口径、三级降级、代码检索顺序与防循环放大遵守 `harness/workflow/development-workflow.md`「上下文加载原则」节与 `harness/rule/context-loading.md`；项目 wiki 检索按 `harness/rule/wiki-read.md`。本环节特化：上一阶段产物以任务所属 story 的 `story/<story>/plan.md` 为主（模块划分、逐环节落地、决策记录、任务清单），同 story 的 `spec.md` 取验收标准、`analysis.md` 取现有实现与兼容事实，`doc/tech-design.md` 如有再读；每个任务开工前按任务标题/模块/涉及接口提取关键词，plan/spec 按任务读相关章节而非每次全文重读；定位时**额外搜索类似实现**；`context.md` 仅在核对原始需求时 grep 定位。worktree 尚未创建时先用 `$root/repo/<repo-name>/` 只读检索，需要改动时按第 1 步创建 worktree

## 指令内容

1. **仓库准入判定（编码前必须先完成）**
   - 判定涉及仓库: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml tasks repos` 取得 status.yaml 中的仓库集合，并与 `story/*/plan.md` 模块划分表「所属仓库」列合并去重，向用户一句话说明
   - 识别交付模式:
     - **仓库模式（默认）**：用户未作其他说明时采用；代码落入 worktree，任务 done 以本地构建/相关测试通过为准
     - **片段模式（例外）**：仅当用户在指令中明确说明「不需要仓库、只生成代码片段、不需要编译和运行」时进入；代码片段直接在回复中交付，逐片段标注所属仓库与建议落点路径；不创建/改动仓库文件，不执行构建、运行与测试；在 `$work/status.yaml` 的 `current.next` 注明「片段模式：仅交付代码片段，未编译运行」
   - 仓库模式就绪检查（以磁盘事实为准，重新核验不信上下文）:
     - 任务未标注 repo、清单为空：先与用户确认承载仓库后再继续
     - `$root/repo/<name>` 不存在：**暂停 code**，转 `repo` 新建仓库，建完回到本命令继续；不得在仓库缺失时直接编码
     - 仓库存在但 `$work/repo/<name>` 无可用 worktree：转 `worktree` 为当前工作区补建后继续
     - 用户拒绝新建或补建、准入无法满足：相关任务置 `blocked` 并在 `current.next` 写明原因；不得降级为直接修改 `$root/repo/`

2. **制定本批执行顺序并回写状态**
   - 动作: 先从最新任务快照与 `current.task` 判定续跑对象，结合会话交接和执行记录核对执行者及断点；归属不明或仍由其他执行者处理时先澄清。
     - 参数指定任务 ID：in_progress 且确认由本次负责时直接恢复；pending 时执行 `sh $root/harness/script/work-status.sh $work/status.yaml tasks claim <任务ID>` 检查依赖并领取；done / blocked 先明确是否重开及阻塞处理。
     - 未指定：优先恢复本次负责的 in_progress 任务；无可恢复任务时执行 `sh $root/harness/script/work-status.sh $work/status.yaml tasks claim`，输出 `CLAIMED` 与任务快照；后续使用 `complete-next` 返回的下一项。
   - 无依赖关系的任务可并行（不同模块/仓库优先）；有依赖的严格按顺序
   - 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set status developing stage code task "<本次任务ID>" next "<本批目标>"`

3. **加载规则**
   - 动作: 按任务涉及的代码类型（后端/前端/配置/SQL/脚本等）加载 `$root/harness/rule/` 匹配规则：加载 `coding-standards.md` 中**已有实质条目的小节**（空小节不构成约束，无内容可加载时直接跳过，以模仿仓库既有代码模式为默认基线）；任务涉及某语言时，若存在对应语言规则文件 `coding-standards-<语言>.md`（如 `coding-standards-python.md`）则一并加载——这些文件按需新建，不存在即该语言无项目级约束；再加载类型专属规则（项目可自行扩展）
   - 涉及外部输入、命令/进程执行、数据库查询、Web 输出、文件路径、鉴权、凭据与加密、新依赖时，**必须加载 `security.md`**，命中清单模式即按其正确做法实现
   - **项目规则与决策**: 按 `harness/rule/wiki-read.md` 读 `$root/wiki/<project>/rule/index.md`，按任务关键词加载 `rule/decisions.md`、`rule/conventions.md` 中命中的条目作为约束；缺失视为该项目暂无沉淀，不是异常
   - **命名**: 新建目录、文件、函数、变量时遵守 `harness/rule/naming.md`，并优先沿用仓库既有命名与术语
   - 按需参考 reference: `implement.md`、`codebase-design.md`、`research.md`

4. **逐任务实现（连续开发，尽量不打扰用户）**
   - 对每个任务：
     1. 向用户**简述**本任务目标与涉及仓库（一句话，不等待确认，直接开始）
     2. grep 定位改动点与可复用资产；**代码中已有类似逻辑时，优先复用或严格模仿其模式**（命名、分层、异常处理、日志、配置方式），不另造风格
     3. 严格按所属 story 的 `plan.md` 落地方案、决策记录与任务验收标准编码：仓库模式涉及多仓库时按依赖顺序改动；片段模式按依赖顺序组织片段，逐段标注所属仓库与建议落点路径
     4. 仓库模式通过本地构建/相关测试、片段模式完成约定交付后，连续执行范围内调用 `sh $root/harness/script/work-status.sh $work/status.yaml tasks complete-next <任务ID>`，一次完成当前任务并领取下一项；用户限定单任务或本批结束时使用 `tasks set <任务ID> done`。并行任务由各执行者分别 claim，禁止领取后交给无人负责的流程
   - 纪律:
     - 不修改 spec/plan 等规划文档（发现需求问题应走 `fix` 命令，不擅自改需求）
     - Git 安全禁令（force push、`reset --hard`、`--no-verify`）见 `harness/rule/git-boundary.md`
   - **多方案处理**：plan「决策记录」之外若出现方案选择，自动按工程最优解实现（与现有代码一致性、可维护性、风险最小优先），并在最终汇总与 commit 说明中记录选择与理由

5. **暂停时机（只在必要时打扰用户）**
   - 仅以下情况中断并询问：
     - 任务 `status` 需置 `blocked`：执行 `sh $root/harness/script/work-status.sh $work/status.yaml tasks set <任务ID> blocked`，原因写入 `current.next`
     - 出现 plan 未覆盖且无法用工程常识判定的**业务/产品**决策
     - 用户预先指定的审阅点已到达
   - 模块完成时简述改动与验证结果，继续已授权范围；其余情况连续完成本批任务

6. **批次收尾与回写**
   - 动作: 本批任务全部完成后：
     - 更新 status.yaml：执行 `tasks list` 汇总 done 任务并确认状态一致；执行 `sh $root/harness/script/work-status.sh $work/status.yaml set next "<仓库模式：下一模块 / commit；片段模式：落库后 commit。需要单测/系统测试/执行脚本时由用户随时触发 testcode/test/run，非必经环节>"`；全部任务 done 时加 `progress.code true`
     - 输出交付摘要：按模块列出任务、改动文件或交付片段（含所属仓库与建议落点）、关键设计选择（含自动决策记录）

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): workspace state <branch>" "$work/status.yaml"`，把本命令对 status.yaml（任务状态）的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] 仓库准入判定已完成：涉及仓库清单明确；仓库模式下各仓库均已就绪，或片段模式由用户明确选择并已在 current.next 注明
- [ ] 本批任务验收标准逐条满足：仓库模式构建与现有测试通过；片段模式片段已交付、逐段标注建议落点且未编译运行
- [ ] 仓库模式改动全部位于 `$work/repo/` 内；片段模式未创建或改动任何仓库文件
- [ ] status.yaml 的 tasks 状态与实际一致（done / in_progress / blocked），`tasks validate` 无错误（退出码 0）
- [ ] 复用了已有类似逻辑或明确记录了无法复用的原因

## 下一步建议

- 继续执行 `code` 推进剩余任务；全部任务完成后直接执行 `commit`——**无需经过任何测试环节**
- `testcode` / `test` / `run` 是按需命令，仅在用户主动要求时触发（如"补单测/做系统测试/跑脚本"），AI 不主动询问或引导；需求/实现需要修正时执行 `fix`
- 片段模式交付的片段由用户落库后，再执行 `commit`
