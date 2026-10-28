---
command: ask
short: a
triggers: 问, 提问, 代码问答, 分析代码, 代码分析, ask, question, code qa, analyze code, code analysis
params: [问题，或仓库名（整体分析时可选）]
summary: 代码理解——先检索项目 wiki 与工作区归档，再做仓库结构整体分析或针对代码逻辑问答；问答记录沉淀到 $work/wiki/，同主题连续问答追加融合，关闭工作区时按归档规则转化沉淀
---

# ask 代码理解

> 两种模式，先识别用户意图：
> - **整体分析**：未提出具体问题、要求分析某仓库/代码结构时，对仓库做静态分析，产出结构与职责文档
> - **代码问答**：用户提出具体的代码逻辑问题时，先梳理代码再回答，并把问答沉淀到 `$work/wiki/`
>
> 只读代码不改代码；结论以代码为唯一真源，引用文件路径+行号，不臆测。

## 前置准入条件

- 已确定当前工作区 `$work`（`$root/space/<workspace>/`）与所属项目（`$work/status.yaml` 的 `project`）
- `$work/repo/` 下至少有一个可访问的 git worktree（`git status` 正常）
- 执行前重新读取 `$work/status.yaml`，尊重本地最新状态

## 项目知识检索（两种模式共用，每次执行）

> 分析或问答前先检索项目已有知识与工作区归档，避免重复推导，并回答「为什么这样做 / 是否设计如此」。

1. **项目 wiki**：从问题、仓库名与业务关键词提炼检索词，`grep` 定位 `$root/wiki/<project>/` 下的 `manifest.md`、`business-understanding.md`、`code-understanding.md`、`decisions.md`，只读命中小节
2. **工作区归档**：`glob` 定位 `$root/wiki/<project>/history/*/summary.md`（目录不存在视为尚无归档，不是异常）；按工作区目录名与正文关键词筛选相关需求，只读「实现的功能 / 关键讨论与决策 / 对系统的影响 / 排查索引」，用于解释需求背景与设计缘由；需要复用当时脚本时再看同目录的 `run/`
3. **取用纪律**: wiki 与归档只作导航和背景，不作为代码事实；与当前代码不一致时以代码为准，并在回答中注明「归档记录为 X，当前代码为 Y」；归档里的可行性分析、找 bug 过程与实现细节不作为结论

## 模式一：整体分析

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage ask task 代码分析 next 生成分析文档`（自动刷新 updated_at）
   - 不改变 `status`（ask 可在任意状态下执行，不推进工作流状态机）

2. **确定分析范围与新鲜度检查**
   - 输入: 参数指定仓库名；未指定时遍历 `$work/repo/` 下全部仓库
   - 动作: 对每个目标仓库确认 `git status` 正常，记录仓库名、路径与当前 HEAD（`git rev-parse --short HEAD`）
   - 新鲜度: 查 `$work/wiki/` 是否已有该仓库的分析文档及其头部「基准 commit」——
     - 已存在且基准与当前 HEAD 一致：告知用户文档是最新的，询问是直接复用还是重新分析
     - 已存在但 HEAD 已偏离：提示「既有分析基于 <旧 commit>，当前已偏离 N 个提交（`git rev-list --count <base>..HEAD`），结论可能过时」，询问增量更新还是重新分析
     - 不存在：正常进入分析（冷仓库，work 开场通常已建议过执行本命令）

3. **分析代码并生成文档**
   - 输入: 目标仓库的代码（目录结构、入口文件、关键模块、配置文件）、近期 git history，以及「项目知识检索」命中的项目 wiki 与历史归档要点
   - 动作:
     - **扫描 git history（代码外决策的富矿，默认低成本档）**：在每个目标仓库执行
       `git log --oneline -50`（只取 commit message，**不读 diff、不翻文件**；用户要求更深时可对个别 commit 单独 `git show --stat`）。
       真实修复的「最后一公里」常取决于代码里没有的项目决策（重试白名单、舍入规则、平局策略、选型结论），
       它们往往只出现在 commit message 中。把发现的决策/约定线索逐条记下并附 `commit <short-hash>` 证据，
       供第 4 步形成 decisions 候选；**message 无法证实的只是线索，不直接当结论**
     - **仓库较大或可并行切维度时**：先读取 `$root/harness/agents/code-explorer.md`，通过 Task 子代理并行委派 2-3 个 explorer 实例（建议维度：入口与调用链 / 数据模型与数据流 / 架构模式与外部依赖），委派 query 须包含仓库路径、范围、具体问题清单与只读约束；主 AI 收集各实例结论（含路径:行号证据）后汇总
     - 小仓库或范围明确时主 AI 可直接分析，仍遵守同样的只读与证据纪律
     - 对每个仓库生成一份分析文档，写入 `$work/wiki/`（目录不存在时先 `mkdir -p`）：
       - 文件名: `<repo-name>-analysis.md`（多仓库时各自一份；单仓库可直接用 `code-analysis.md`）
       - 文档头部固定记录基准，供后续新鲜度判断：
         `> 基准 commit: <short-hash>（<提交日期>）　生成时间: <日期>　仓库: <repo-name>`
       - 章节结构（按需裁剪，无内容的小节标注「待补充」或省略）：
         1. **仓库概览**：主要语言、框架、构建工具、入口文件
         2. **目录结构**：顶层目录树 + 各目录职责说明
         3. **模块划分**：模块 | 职责 | 关键类/文件 | 说明
         4. **核心流程**：主要业务/请求的调用链路（从入口到落库/出参）
         5. **关键技术点**：设计模式、中间件使用、配置机制等
         6. **外部依赖**：依赖的服务、中间件、第三方库（含版本）
         7. **git history 线索**：近期 commit message 中出现的决策/约定线索（附 commit hash，标注「待确认」）
         8. **待确认问题**：分析中发现的不清晰之处
   - 纪律: 结论必须有代码依据（引用文件路径+行号或代码片段）；不臆测未读代码的行为；大文件只摘录关键片段
   - 边界: 本文档是绑定当前分支的**临期快照**，可以记录调用链、模块职责等实现细节；
     这些易变内容只留在 `$work/wiki/`，**不回写项目 wiki**——项目 wiki 只接受稳定导航锚点与决策约定（见第 4 步）
   - 按需参考 reference（须经本命令引用方可加载）: `codebase-design.md`、`domain-modeling.md`

4. **汇总与审阅**
   - 动作: 列出生成的文档路径与各文档摘要，提示用户审阅
   - 用户可直接修改文档；发现分析有误时告知 AI 重新分析对应部分
   - 分析文档只留在 `$work/wiki/`，默认不登记长期索引、不复制全文入项目 wiki；确需长期保留全文时，经用户确认迁移到 `$root/wiki/<project>/analysis/` 后再建立索引
   - 关闭工作区时由 `close` 按 `harness/rule/archive-ask.md` 把稳定结论转化归档——业务名词进 `business-understanding.md`、代码名词/导航进 `code-understanding.md`、需求特定的「为什么」进 `history/<workspace>/summary.md`；只归档结论，不归档分析过程
   - **提炼稳定锚点候选（不直接写项目 wiki）**：从本次分析中挑出重构频率低、可用于导航的事实——
     「业务术语 ↔ 检索关键词/代码入口」「接口标识 ↔ 业务场景 ↔ 代码入口」，整理成候选清单交用户审阅；
     用户确认保留的条目，按 `record` 命令沉淀到 `$root/wiki/<project>/code-understanding.md` 的两张映射表
     （人工审阅后生效；已存在的同义条目就地融合更新）。实现细节与调用链只留在工作区分析文档，不上沉
   - **提炼决策/约定候选（不直接写项目 wiki）**：把第 3 步 git history 线索中、能被 commit message 明确证实
     且代码本身看不出的项目决策/工程约定，整理成第二份候选清单（条目 | 类型（决策/约定）| 来源 commit hash）；
     用户确认后按 `record` 沉淀到 `$root/wiki/<project>/decisions.md`（人工审阅后生效）；无法证实的线索保留在分析文档
     「git history 线索」小节标「待确认」，不上沉

5. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.ask true next "继续下一步（如 spec / plan / code）"`

## 模式二：代码问答

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage ask task "<问题摘要>"`（自动刷新 updated_at）
   - 不改变 `status`

2. **接收并明确问题**
   - 输入: 用户关于代码逻辑的具体问题；问题过宽（如「讲讲这个项目」）时先追问聚焦到具体逻辑点，或转入模式一
   - 动作: 先按「项目知识检索」查项目 wiki 与 `history/` 中的相关背景，再 grep/glob 定位代码命中文件与行号，只读相关片段，禁止整仓通读

3. **定位主题文档**
   - 动作: 扫描 `$work/wiki/*.md`，读取各文档头部的「主题」行与标题，判断问题是否属于已有文档
   - **命中同一主题**：在该文档中追加（见第 5 步）；存在多个相近文档无法确定时，列出候选请用户选择
   - **无匹配**：新建文档：
     - 文件名: 根据问题提炼英文 kebab-case 主题词（如 `order-timeout-flow.md`），写入 `$work/wiki/`（必要时先 `mkdir -p`）；用户可改名
     - 初始结构:

       ```markdown
       # <中文主题>

       > 主题: <主题关键词>
       > 涉及仓库: <repo1, repo2>
       > 基准 commit: <short-hash>
       > 最近更新: <日期>

       ## 梳理结论

       （问答中持续融合更新的结论区）

       ## 问答记录
       ```

4. **梳理代码并回答**
   - 动作: 沿调用链阅读相关代码，形成结论；当场向用户输出回答，关键结论附 `文件路径:行号` 依据
   - 纪律: 代码为唯一真源，读不到依据的部分明确说「待确认」，不臆测

5. **追加融合到主题文档**
   - 动作:
     - 在「问答记录」下追加：`### Q<n>: <问题>（<日期>）` + 回答（含依据链接）
     - 同步更新「梳理结论」区：把新结论**融合**进已有表述——重复内容合并、结论变化时就地更新，不堆叠矛盾说法；更新头部「最近更新」与「涉及仓库」
     - 取当前 HEAD 更新头部「基准 commit」；若问答前发现 HEAD 已偏离文档基准，先提示用户早期结论可能基于旧代码，再据实更新
   - 边界: 主题文档留在 `$work/wiki/`，不登记长期索引；不把问答中的易变实现细节提炼成锚点——用户确认有稳定导航价值时，走 `record` 沉淀；关闭工作区时由 `close` 按 `harness/rule/archive-ask.md` 转化归档业务/代码名词解释与需求特定的「为什么」

6. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.ask true next "等待用户继续提问或进入下一环节"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): code analysis <branch>"`，把 `$work/wiki/` 分析文档与 status.yaml 的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`（空间提交含工作区文档，不含 worktree 代码）

## 后置完成检验

- [ ] 已正确识别两种模式；问答模式未对宽泛问题强行作答
- [ ] 已检索 `$root/wiki/<project>/` 项目 wiki 与 `history/` 工作区归档；归档与当前代码冲突时以代码为准并在回答中注明
- [ ] 已做新鲜度检查：既有分析文档的基准 commit 与当前 HEAD 一致或已就偏离提示用户
- [ ] 模式一：`$work/wiki/<repo>-analysis.md` 已生成（头部含基准 commit），核心章节完整（含 git history 线索小节），已呈现稳定锚点候选与决策/约定候选
- [ ] 模式二：问答已当场回答用户；同主题连续问答落在**同一文档**（追加 Q 条目 + 融合结论区、更新基准 commit），新主题才新建文档
- [ ] 全部结论有代码依据（路径+行号）或 commit hash 依据，未臆测；易变实现细节未直写项目 wiki；无法证实的 history 线索只标「待确认」
- [ ] `$work/status.yaml` 已同步（progress.ask=true）；本命令未修改任何代码文件

## 下一步建议

- 继续围绕同一主题提问，结论会持续融合；执行 `spec` / `plan` 时引用 `$work/wiki/` 产物作为代码侧上下文
- 发现的待确认问题可向项目成员澄清后回写文档
