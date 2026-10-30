---
workflow: development
short: dev
triggers: 开发工作流, 需求开发, 功能开发, development, development workflow, requirement development, feature development
summary: 从需求到合并交付的完整开发状态机——work 建区后先做需求分析（analyze，按 story 产出 analysis.md）→ spec → plan →（需要正式评审时）tech-design → code → commit → push → merge → close；一个工作区可承载多个研发 story；tech-design 仅在需要正式评审时生成，testcode/test/run/code-review/release-check 为按需命令（用户需要时触发，非必经环节、不占状态、不阻塞流转）；任何环节可用 fix 修正需求或实现
---

# development 开发工作流

> 需求无关的通用功能开发流程。AGENTS 识别到「新需求/做功能/迭代开发」意图时加载本工作流，
> 按状态机推进并引导命令；命令的准入准出以 `harness/cmd/` 文件为唯一权威。

## 适用场景

- 新功能、新需求、迭代开发
- 边界：纯缺陷修复走 `bugfix`；仅测试与覆盖率走 `testing`；已在合并中处理冲突走 `merge-conflict`

## 状态流转

`$work/status.yaml` 的 `status` 在本工作流下的合法取值：

```
initialized → planning → developing → reviewing → merged ──close──▶ 工作区注销（目录与 AGENTS.md 条目移除）
                    \          \           \
                     └──────── blocked（任何环节缺输入/被等待时进入，解除后回原状态）
```

| 状态 | 含义 | 进入条件 |
|------|------|----------|
| initialized | 工作区已创建，需求未录入或未确认 | `work` 完成 |
| planning | 需求分析与设计中（analyze/spec/plan，按 story 逐个推进，按需 tech-design） | context.md 已有真实需求，开始 `analyze` 或对已分析的 story 执行 `spec` |
| developing | 编码中（code） | plan.md 已确认且 tasks 列表已生成 |
| reviewing | 合并中（本地分支合并或平台 MR/PR） | 开发完成、已 commit/push，开始合并 |
| merged | 已合并主干，待 `close` 收尾 | 平台或本地 merge 完成 |
| blocked | 受阻 | 缺需求/依赖/审核等待，需在 current.next 写明 |

> `close` 完成后工作区目录与 AGENTS.md work 条目一并移除，status.yaml 随之删除，不保留终态工作区；工作区列表以 AGENTS.md 登记为准，登记与磁盘的偏差由 `evolution` 校准。

## 各环节与命令映射

| # | 环节 | 命令 | 产物 | 完成后状态/进度 |
|---|------|------|------|----------------|
| 1 | 初始化项目上下文 | `init` | AGENTS.md 项目条目、`wiki/<project>/`、repo/ 接入 | — |
| 2 | 新建工作区 | `work` | `space/<YYYYMMDD>-<branch>/` 目录与 `status.yaml`（含 project）、`context.md`；story/doc/repo 等目录按需创建、worktree 懒加载；AGENTS.md work 条目、开场知识清单（roster） | initialized |
| 2.5 | 代码理解（可选，需求明确前） | `ask` | `$work/doc/analysis/` 下的 `<repo>-analysis.md` 与主题问答文档（按索引并发检索 `$root/wiki/<project>/` 与工作区已有分析，按需用 `$work/repo/` 或 `$root/repo/` 代码核实；含基准 commit 与 git history 线索；大仓库可委派 code-explorer 并行勘探） | — / progress.ask |
| 2.6 | 需求分析（建区后必经） | `analyze` | `$work/story/<story>/analysis.md`（现有实现、可行性、兼容性、待确认问题与讨论记录）；需求可一次多条或分批追加，按完整闭环功能拆 story | planning / progress.analyze |
| 3 | 需求规划（顶层设计 + 公共契约，按 story） | `spec` | `story/<story>/spec.md`（调研与可行性、功能场景、边界、验收、测试要点、开发估时） | planning / progress.spec |
| 4 | 开发计划（方案对比 + 详细设计 + 上线流程 + 任务拆解，按 story） | `plan` | `story/<story>/plan.md`（代码/接口/SQL 细节、上线流程、任务清单）、status.yaml 的 tasks 列表（全工作区汇总） | planning / progress.plan |
| 5 | 技术评审文档（按需，仅需要正式评审时） | `tech-design` | `doc/tech-design.md`（由目标 story 的 spec/plan 重组；多 story 分别评审时 `doc/tech-design-<story>.md`） | planning / progress.tech-design |
| 6 | 编码 | `code` | worktree 内代码 | developing / progress.code |
| 6.5 | 需求/实现修正（任意环节） | `fix` | 同步修正 spec/plan/tasks/代码 | 回到修正点所属环节 |
| 7 | 按需命令（非主链路，见下表） | `testcode` `test` `run` `code-review` `release-check` | 各命令产物（见下表） | 仅 `progress` 事实记录 |
| 8 | 拉取/提交/推送 | `fetch` `commit` `push` | 提交与远端分支、mr_url | developing |
| 9 | 合并 | `merge`（纯分支操作：fetch、合并、solve、提交、push；当前工作区为源分支时新建关联工作区；冲突转 merge-conflict / branch-op 工作流） | 合并提交与推送结果、MR/PR 合并 | reviewing → merged |
| 10 | 关闭工作区 | `close` | 关联工作区同步关闭、交付摘要、工作区归档入 `wiki/<project>/history/<workspace>/summary.md` 并登记 `history/index.md`、移入 `run/`（自动判定；标准产物外的文件逐个询问是否移入）、ask 记录转化归档、内容按分类与索引提炼入 wiki（含 `rule/decisions.md`、`rule/conventions.md`，用户确认）、guidance 自进化固化到 workflow/cmd/rule（回写时校验落点）、worktree 移除、工作区目录删除、AGENTS.md work 条目移除 | 工作区关闭（目录与条目均移除） |
| — | 经验沉淀 | `record` | cmd/workflow/rule/wiki | 任意环节之后 |

> 需要从当前环节连续执行到终态时使用 `auto`：开始前一次性补齐缺失信息并确认全流程，确认后按上表连续推进，不逐环节等待审阅；各环节准入准出仍以对应 cmd 文件为准。

### 按需命令（非主链路环节，用户需要时才触发）

以下命令**不是开发必经环节**：不在主链路状态机中占位、不阻塞 commit/push/merge/close，code 完成后可直接提交，AI 不主动询问"是否进入"——**用户不触发即视为本工作不需要**。用户直接表达意图（跑单测/系统测试/执行脚本）或进入 `testing` 工作流时才执行；执行期间只临时占用 `current.stage`，完成与否仅作 `progress` 事实记录。

| 命令 | 用途 | 产物 | 完成后进度记录 |
|------|------|------|----------------|
| `testcode` | 以单测为手段的需求-代码一致性审查与缺陷发现（覆盖率 90% 是准出指标之一而非唯一目的） | 测试代码、审查发现与缺陷修复、覆盖率结果 | progress.testcode |
| `test` | 系统测试：面向完整系统功能的端到端验证方案 | `$work/doc/test.md`（可落地可执行）；需脚本时落到 `run/<指令>/` | progress.test |
| `run` | run 指令管理：`run/run.md` 只做识别、索引与编排，新增指令落 `run/<指令>/`（脚本+数据+local/），执行时校验并编排；敏感数据落各指令的 `local/`（gitignored） | `run/run.md`、`run/<指令>/`、执行结果 | progress.run |
| `code-review` | 合并前独立深度审查：以 story plan/tech-design 为规范、目标分支三点 diff 为事实，逐函数分析改动、正确性与危害，评估影响接口与场景 | `$work/doc/code-review.md` | progress.review |
| `release-check` | 上线前检查清单：数据库变更（含变更语句）、配置变更（含模板）、新增接口调用（权限申请）、新增中间件（申请配置） | `$work/doc/release-check.md` | progress.release_check |

## 各环节说明

1. **init**：先确定目标项目，提炼项目名称、关键词、描述写入 AGENTS.md 当前项目条目；本地仓库深度 ≤5 扫描后软链到 `repo/`，远端仓库克隆到 `repo/`
2. **work**：先确定所属项目；目的宽泛时先给出可能的具体意图候选请用户明确，再据此生成英文分支名，推断涉及服务由用户确认；`work.sh` 以 `--no-worktree` 只创建 `space/<YYYYMMDD>-<branch>/` 目录、`status.yaml`（含 project）与 `context.md`（目录名带创建日期前缀，git 分支名不带日期），`story/`、`doc/`、`run/`、`repo/` 等目录与 worktree 均按需创建；`project.sh work-add` 登记；**登记后输出开场知识清单（roster）**——按 `$root/wiki/<project>/index.md` 一行一项列出分类与已存在文件、列出工作区已有 story 与 `doc/analysis/` 文档，冷仓库主动建议先跑 `ask`；只列不读，不塞全文
2.5 **ask**（可选，需求明确前）：按 `harness/rule/wiki-read.md` 并发检索 `$root/wiki/<project>/`（含 `history/` 归档）与 `$work/doc/analysis/`，再按需检索代码核实——代码检索顺序优先 `$work/repo/`，没有所需仓库时用 `$root/repo/`；在 `$work/doc/analysis/` 生成 `<repo>-analysis.md`（仓库概览、目录结构、模块划分、核心流程、关键技术点、外部依赖、git history 线索）或按主题生成问答文档；文档头部记录**基准 commit**，重跑时先比对 HEAD 提示新鲜度；分析前扫描近期 commit message（默认 50 条、只读 message）发现代码外决策线索；大仓库或可切维度时读取 `harness/agents/code-explorer.md` 委派多个 explorer 实例并行勘探，主 AI 汇总落盘；同主题追加融合、不同主题分文件；锚点候选与决策/约定候选交用户确认后分别走 `record` 沉淀到 `code/anchors.md`、`code/interfaces.md` 与 `rule/decisions.md`
2.6 **analyze**（建区后必经，前置为用户已提供需求内容或需求文档）：先读需求内容（`context.md` 与本次提供的需求文档），再检索 `$work/doc/analysis/` 与 `$root/wiki/<project>/`，最后才检索代码；把需求按「完整闭环功能」拆成研发 story（与产品 story 不要求一一对应），逐 story 生成 `story/<story>/analysis.md`——现有实现（含 `文件路径:行号`）、可行性、与现有实现的兼容性、实现建议与待确认问题；需求可一次提供多条或分先后追加，多轮追问在同一 `analysis.md` 中追加融合；需求明确前的泛代码问答走 `ask`，不与本命令混放
3. **spec**（按 story）：以 `context.md` 中本 story 需求、`story/<story>/analysis.md`、`$root/wiki/<project>/`、`doc/analysis/`、代码事实为输入，先 grep 定位再加载相关内容，产出 `story/<story>/spec.md`（需求调研与可行性、候选实现路线、需提前决策事项、功能场景拆分、系统/模块、关系交互、边界、验收标准、测试要点、开发估时），只整理不篡改，人工确认；本环节关闭所有需要产品/测试决策的事项，确认后产品与测试退场
4. **plan**（按 story）：以同 story 的 spec、analysis、context、项目 wiki 与代码为输入（先 grep 定位），产出 `story/<story>/plan.md`；**复杂任务先过方案门禁**——委派 code-architect 并行产出 ≥2 个方案（最小改动/干净架构/务实平衡取向），输出对比表与推荐，用户选定后再拆模块；**随后拆低耦合模块、标注模块依赖图**，再逐级拆任务（deps 无环、含验证方式）；任务汇总到 status.yaml 的 `tasks`（全工作区、ID 全局唯一）；详细设计落到代码/接口/SQL 细节并给出上线流程（发布顺序、数据与配置变更顺序、灰度与回滚）；实现级「决策记录」在本环节关闭需用户决断的事项；简单任务可声明跳过多方案并记录理由
5. **tech-design**（按需）：仅在需要正式评审时，读技术模板与目标 story 已确认的 spec/plan，重组为 `doc/tech-design.md`（不新增设计决策；多 story 分别评审时按 story 命名）；飞书等外链回填工作区 status.yaml
6. **code**：编码前先做仓库准入判定——汇总 tasks 的 repo 字段与 `story/*/plan.md` 模块划分得到涉及仓库清单，主仓库缺失转 `create-repo` 新建、worktree 缺失转 `worktree` 按需创建，用户拒绝致准入无法满足则 blocked；用户明确说明「只生成代码片段、不编译不运行」时进入片段模式，仅在回复交付片段（标注建议落点）、不动仓库文件。按 tasks 的 deps 拓扑调度，无依赖任务并行、有依赖串行，连续开发尽量不打扰用户；已有类似逻辑优先复用或模仿；新建目录/文件/函数/变量遵守 `harness/rule/naming.md`；plan 外的多方案自动按工程最优解实现并记录；仅在受阻、业务决策不明或模块里程碑时暂停。参考 reference：implement.md、codebase-design.md、research.md
6.5 **fix**：需求修正走 spec→plan→tasks→代码；代码修正走代码→再评估并反向同步文档，保持四者一致
7. **testcode / test / run（按需命令，见上节）**：均非必经环节，只在用户主动触发时执行，AI 不在 code 完成后主动引导或询问；准入准出与执行细节以各自 `harness/cmd/dev/` 命令文件为唯一权威。testcode 参考 reference：tdd.md、code-review.md；测试凭据落位遵守 `harness/rule/security.md`（入库文档只标来源）
8. **commit/push**：非 git 目录先 init；未关联远端先引导关联；Git 安全禁令见 `harness/rule/git-boundary.md`
9. **merge**：只做分支操作——fetch 最新，确认源分支引用（本地分支含未推送提交 / 远程分支仅已推送提交）与目标分支；当前工作区为目标分支时就地合并，当前工作区为源分支时按 `work` 分支操作流程新建关联工作区（`parent_workspace` 指向当前工作区）执行；冲突不静默取舍，进入 `solve`；合并提交后普通推送，保护分支按平台 MR/PR 流程
10. **close**：完成态直接收尾，非完成态经用户确认才可关闭；先同步关闭 `parent_workspace` 指向本工作区的关联工作区；**worktree 移除前输出四段交付摘要（构建内容/关键决策/改动文件/建议后续步骤）**；按 `harness/rule/archive-requirement.md` 自动判定归档价值，应归档的写入 `wiki/<project>/history/<workspace>/summary.md`（原始资料、实现功能、关键讨论与决策、系统影响、排查索引，不保留实现过程，简单分支操作不归档），在 `history/index.md` 登记该工作区目录，`$work/run/` 存在时整体移入同目录的 `run/`，标准产物以外的文件逐个询问用户是否移入；提炼工作区**原始产物**中的可复用知识（业务背景/代码锚点/**项目规则/项目配置**四类，其中技术决策与工程约定 → `wiki/<project>/rule/decisions.md`、`rule/conventions.md`），`$work/doc/analysis/` 的 ask 记录按 `harness/rule/archive-ask.md` 转化归档（业务名词进 `biz/glossary.md`、代码名词/导航进 `code/anchors.md` 与 `code/interfaces.md`），每条带来源、矛盾保留演变，经用户确认与人工审阅后按 `harness/rule/wiki-write.md` 写入 `$root/wiki/<project>/` 并登记索引；工作区级参数留在 `$work/status.yaml`；**自动触发一次自进化**——消费 status.yaml 的 guidance 中 pending 条目，将可复用操作习惯固化到 workflow/cmd/rule（经用户确认，能融合则融合），回写 applied/rejected（applied 回写时校验落点文件存在）；移除 worktree 后执行 `work.sh purge` 删除工作区目录、`project.sh work-remove` 移除 AGENTS.md work 条目（过程文档不保留，跨工作区知识已先行入 wiki/harness）

## 上下文加载原则（spec/plan/code/testcode 共同遵守）

- 通用加载纪律见 `harness/rule/context-loading.md`（先定位后加载，禁止整仓通读）；**每个命令执行前先读 `$work/context.md`**；项目 wiki 检索按 `harness/rule/wiki-read.md` 走索引选分类与文件
- 输入源统一为：`$work/context.md`、`story/<story>/analysis.md`、上一阶段产物、`$root/wiki/<project>/`（含 `history/` 工作区归档）、`$work/doc/analysis/`、代码
- **代码检索顺序**：优先 `$work/repo/<repo-name>/`（已有 worktree，当前分支）；没有所需仓库时用 `$root/repo/<repo-name>/`（主仓库，只读）；需要修改代码时才创建 worktree
- 代码是事实的唯一真源；wiki 只提供代码中拿不到的信息
- **工作区归档的用法**：`$root/wiki/<project>/history/<workspace>/` 用于回答「为什么这样做 / 是否设计如此」，需要复用时取同目录 `run/`；与当前代码不一致时以代码为准，并在结论中注明差异
- **三级降级**：知识不足时按 `$root/wiki/<project>/`（跨工作区共识）→ `$work/story/*/analysis.md` 与 `$work/doc/analysis/`（本工作区临期分析，注意基准 commit 是否过时）→ 直接读代码（永远的最终真源）顺序取用；上层缺失或存疑时不得止步，必须下沉取证，不以「wiki 没写」作为不查证的理由
- **防循环放大**：wiki 只从工作区原始产物、代码、git history、用户原始资料取证；已有的 AI 合成页面不作为另一个页面更新的事实来源（见 `harness/rule/wiki-write.md`）

## 状态回写要求

- 每个命令开始前经 `harness/script/work-status.sh` 回写 `$work/status.yaml`：`current.stage`（analyze/spec/plan/code/fix/...）、`current.task`、`current.next`（updated_at 由脚本自动刷新）
- 任务级状态通过 `work-status.sh <status.yaml> tasks set <任务ID> <状态>` 流转（pending / in_progress / done / blocked），由 code/testcode/fix 维护；`tasks replace` 用于整表同步，`tasks validate` 阻断悬空/自依赖/循环依赖与非法状态
- **用户引导采集（自进化素材）**：每个任务/环节结束时，凡用户对 AI 的做法有过引导、纠偏、补充约定，自动向 `guidance` 列表追加一条 pending 记录（字段见 `harness/template/work-status.yaml`）；只记事实，不直接改 harness
- 命令完成并经人工确认后：置 `progress` 对应开关为 true（analyze/ask/spec/plan/...），并按上表推进 `status`；多 story 时 spec/plan 的完成以 `story/<story>/` 下文件为准
- 受阻时执行 `work-status.sh <status.yaml> tasks set <任务ID> blocked`，在 `current.next` 写明阻塞原因与等待项；解除后用 `tasks set <任务ID> pending|in_progress` 回到受阻前状态
- `guidance` 的 pending 条目在 `close` 时自动固化（或随时手动 `evolution`/`record` 提前固化），固化后置 applied 并由回写脚本校验落点文件存在（格式见 `harness/template/work-status.yaml`）
- `close` 后工作区目录与 AGENTS.md work 条目均已移除（工作区列表只以 AGENTS.md 登记为准）
