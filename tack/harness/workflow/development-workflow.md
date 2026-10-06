---
workflow: development
short: dev
triggers: 开发工作流, 需求开发, 功能开发, development, development workflow, requirement development, feature development
summary: 从需求到合并交付的完整开发状态机——spec → plan → tech-design → code → commit → push → merge → close；testcode/test/run/code-review/release-check 为按需命令（用户需要时触发，非必经环节、不占状态、不阻塞流转）；任何环节可用 fix 修正需求或实现
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
initialized → planning → developing → reviewing → merged → completed
                    \          \           \
                     └──────── blocked（任何环节缺输入/被等待时进入，解除后回原状态）
```

| 状态 | 含义 | 进入条件 |
|------|------|----------|
| initialized | 工作区已创建，需求未录入或未确认 | `work` 完成 |
| planning | 需求分析与设计中（spec/plan/tech-design） | input.md 已有真实需求，开始 `spec` |
| developing | 编码中（code） | plan.md 已确认且 tasks 列表已生成 |
| reviewing | 代码审查与合并中 | 开发完成、已 commit/push，发起 MR/PR |
| merged | 已合并主干 | 平台或本地 merge 完成 |
| completed | 工作区收尾完成 | `close` 完成 |
| blocked | 受阻 | 缺需求/依赖/审核等待，需在 current.next 写明 |

## 各环节与命令映射

| # | 环节 | 命令 | 产物 | 完成后状态/进度 |
|---|------|------|------|----------------|
| 0 | 初始化项目空间 | `init` | AGENTS.md 项目信息、repo/ 接入 | — |
| 1 | 新建工作区 | `work` | `space/<YYYYMMDD>-<branch>/`、worktree、AGENTS.md work 条目、开场知识清单（roster） | initialized |
| 1.5 | 代码理解（可选） | `ask` | `$work/wiki/<repo>-analysis.md` 及问答文档（含基准 commit 与 git history 线索；大仓库可委派 code-explorer 并行勘探） | — / progress.ask |
| 2 | 需求规划（整体设计） | `spec` | spec.md | planning / progress.spec |
| 3 | 开发计划（方案对比 + 详细设计 + 任务拆解） | `plan` | plan.md（复杂任务多方案对比与选定、含任务清单）、status.yaml 的 tasks 列表 | planning / progress.plan |
| 4 | 技术评审文档 | `tech-design` | tech-design.md（可委派 code-architect 深化设计） | planning / progress.tech-design |
| 5 | 编码 | `code` | worktree 内代码 | developing / progress.code |
| 5.5 | 需求/实现修正（任意环节） | `fix` | 同步修正 spec/plan/tasks/代码 | 回到修正点所属环节 |
| 7 | 拉取/提交/推送 | `fetch` `commit` `push` | 提交与远端分支、mr_url | developing |
| 8 | 代码审查与合并 | `merge`（委派 code-reviewer 审查，结论三选一分流；冲突转 merge-conflict 工作流） | 审查结论与分流记录、MR/PR 合并 | reviewing → merged |
| 9 | 关闭工作区 | `close` | 交付摘要、内容提炼入 wiki 四类页面（含 decisions，用户确认）、guidance 自进化固化到 workflow/cmd/rule（check-guidance 校验落点）、worktree 移除、work 条目 completed | completed |
| — | 经验沉淀 | `record` | cmd/workflow/rule/wiki | 任意环节之后 |

### 按需命令（非主链路环节，用户需要时才触发）

以下命令**不是开发必经环节**：不在主链路状态机中占位、不阻塞 commit/push/merge/close，code 完成后可直接提交，AI 不主动询问"是否进入"、也不需要任何"跳过"标记——**用户不触发即视为本工作不需要**。用户直接表达意图（跑单测/系统测试/执行脚本）或进入 `testing` 工作流时才执行；执行期间只临时占用 `current.stage`，完成与否仅作 `progress` 事实记录。

| 命令 | 用途 | 产物 | 完成后进度记录 |
|------|------|------|----------------|
| `testcode` | 以单测为手段的需求-代码一致性审查与缺陷发现（覆盖率 90% 是准出指标之一而非唯一目的） | 测试代码、审查发现与缺陷修复、覆盖率结果 | progress.testcode |
| `test` | 系统测试：面向完整系统功能的端到端验证方案 | `$work/test.md`（可落地可执行）；需脚本时落到 `run/` | progress.test |
| `run` | 执行测试/数据脚本：无 `run/` 时初始化，有 run.md 时按清单执行；敏感数据落 `run/local/`（gitignored） | `run/run.md`、执行结果 | progress.run |
| `code-review` | 合并前独立深度审查：以 plan/tech-design 为规范、目标分支三点 diff 为事实，逐函数分析改动、正确性与危害，评估影响接口与场景 | `$work/code-review.md` | progress.review |
| `release-check` | 上线前检查清单：数据库变更（含变更语句）、配置变更（含模板）、新增接口调用（权限申请）、新增中间件（申请配置） | `$work/release-check.md` | progress.release_check |

## 各环节说明

1. **init**：提炼项目名称、关键词、描述写入 AGENTS.md 项目信息区块；本地仓库深度 ≤5 扫描后软链到 `repo/`，远端仓库克隆到 `repo/`
2. **work**：目的宽泛时先给出可能的具体意图候选请用户明确，再据此生成英文分支名，推断涉及服务由用户确认；`work.sh` 创建 `space/<YYYYMMDD>-<branch>/` 扁平骨架（status.yaml、input.md、wiki/、repo/ worktree；目录名带创建日期前缀，git 分支名不带日期）；`project.sh work-add` 登记；**登记后输出开场知识清单（roster）**——一行一项列出已有 wiki 页面、与本仓库相关的历史分析文档（含基准 commit 与新鲜度），冷仓库主动建议先跑 `ask`；只列不读，不塞全文
2.5 **ask**（可选）：分析 `$work/repo/` 下的代码，在 `$work/wiki/` 生成 `<repo>-analysis.md`（仓库概览、目录结构、模块划分、核心流程、关键技术点、外部依赖、git history 线索）；文档头部记录**基准 commit**，重跑时先比对 HEAD 提示新鲜度；分析前扫描近期 commit message（默认 50 条、只读 message）发现代码外决策线索；大仓库或可切维度时读取 `harness/agents/code-explorer.md` 委派多个 explorer 实例并行勘探，主 AI 汇总落盘；也可针对具体代码逻辑提问，问答按主题沉淀（同主题追加融合、更新基准 commit）；锚点候选与决策/约定候选交用户确认后分别走 `record` 沉淀到 code-understanding 与 decisions；可在 spec/plan 前执行以建立代码侧上下文
3. **spec**：以 input.md、`$root/wiki/`、`$work/wiki/`、代码事实为输入，先 grep 定位再加载相关内容，产出 spec.md（story、系统/模块、关系交互、边界、验收标准），只整理不篡改，人工确认
4. **plan**：以 spec/input/wiki/代码为输入（先 grep 定位），产出 plan.md；**复杂任务先过方案门禁**——委派 code-architect 并行产出 ≥2 个方案（最小改动/干净架构/务实平衡取向），输出对比表与推荐，用户选定后再拆模块；**随后拆低耦合模块、标注模块依赖图**，再逐级拆任务（deps 无环），任务同步 status.yaml 的 `tasks`；实现级「决策记录」在本环节关闭需用户决断的事项；简单任务可声明跳过多方案并记录理由
5. **tech-design**：读技术模板与 spec/plan，产出 tech-design.md；飞书等外链回填工作区 status.yaml
6. **code**：编码前先做仓库准入判定——汇总 tasks 的 repo 字段与 plan 模块划分得到涉及仓库清单，主仓库缺失转 `create-repo` 新建、worktree 缺失转 `worktree` 补建，用户拒绝致准入无法满足则 blocked；用户明确说明「只生成代码片段、不编译不运行」时进入片段模式，仅在回复交付片段（标注建议落点）、不动仓库文件。按 tasks 的 deps 拓扑调度，无依赖任务并行、有依赖串行，连续开发尽量不打扰用户；已有类似逻辑优先复用或模仿；plan 外的多方案自动按工程最优解实现并记录；仅在受阻、业务决策不明或模块里程碑时暂停。参考 reference：implement.md、codebase-design.md、research.md
6.5 **fix**：需求修正走 spec→plan→tasks→代码；代码修正走代码→再评估并反向同步文档，保持四者一致
7. **testcode / test / run（按需命令，见上节）**：均非必经环节，只在用户主动触发时执行，AI 不在 code 完成后主动引导或询问；准入准出与执行细节以各自 `harness/cmd/dev/` 命令文件为唯一权威。testcode 参考 reference：tdd.md、code-review.md；test 的敏感数据一律写 `run/local/`（.gitignore 已忽略），test.md 只标注凭据来源
8. **commit/push**：非 git 目录先 init；未关联远端先引导关联；不跳过 hooks、不 force push
9. **merge**：合并前审查必选——读取 `harness/agents/code-reviewer.md` 委派审查（小改动单实例，大改动并行三视角：规范符合度/bug 与正确性/约定与安全），方法遵循 reference `code-review.md` 双轴；审查结论由用户三选一分流：立即修复（回 fix 后复审）/ 记录后续（登记 status.yaml `follow_ups` 或 issue，允许合并）/ 维持现状（用户确认承担风险）；之后优先平台 MR/PR 合并；冲突不静默取舍，进入 solve
10. **close**：完成态直接收尾，非完成态经用户确认才可关闭；**worktree 移除前输出四段交付摘要（构建内容/关键决策/改动文件/建议后续步骤）**；提炼工作区**原始产物**中的可复用知识（事实/锚点/业务知识/**技术决策与工程约定**四类，后者含 plan 决策记录 → `wiki/decisions.md`），每条带来源、矛盾保留演变，经用户确认与人工审阅后写入 `$root/wiki/`；**自动触发一次自进化**——消费 status.yaml 的 guidance 中 raw 条目，将可复用操作习惯固化到 workflow/cmd/rule（经用户确认，能融合则融合），回写 distilled/dismissed（distilled 按 `落点: <相对 $root 路径>` 注明并经 `check-guidance.sh` 校验）；移除 worktree，`project.sh work-set ... completed`，文档按用户选择保留或清理

## 上下文加载原则（spec/plan/code/testcode 共同遵守）

- 通用加载纪律见 `harness/rule/context-loading.md`（先定位后加载，禁止整仓通读）
- 输入源统一为：`$work/input.md`、上一阶段产物、`$root/wiki/`、`$work/wiki/`、代码
- 代码是事实的唯一真源；wiki 只提供代码中拿不到的信息
- **三级降级**：知识不足时按 `$root/wiki/`（跨工作区共识）→ `$work/wiki/`（本工作区临期分析，注意基准 commit 是否过时）→ 直接读代码（永远的最终真源）顺序取用；上层缺失或存疑时不得止步，必须下沉取证，不以「wiki 没写」作为不查证的理由
- **防循环放大**：wiki 只从工作区原始产物、代码、git history、用户原始资料取证；已有的 AI 合成页面不作为另一个页面更新的事实来源（见 `harness/rule/record-wiki.md`）

## 状态回写要求

- 每个命令开始前经 `harness/script/work-status.sh` 回写 `$work/status.yaml`：`current.stage`（spec/plan/code/fix/...）、`current.task`、`current.next`（updated_at 由脚本自动刷新）
- 任务级状态通过 `tasks[].status` 流转（pending / in_progress / done / blocked），由 code/testcode/fix 维护
- **用户引导采集（自进化素材）**：每个任务/环节结束时，凡用户对 AI 的做法有过引导、纠偏、补充约定，自动向 `guidance` 列表追加一条 raw 记录（字段见 `harness/template/work-status.yaml`）；只记事实，不直接改 harness
- 命令完成并经人工确认后：置 `progress` 对应开关为 true，并按上表推进 `status`
- 受阻时置 `status: blocked`，在 `current.next` 写明阻塞原因与等待项；解除后回到受阻前状态
- `guidance` 的 raw 条目在 `close` 时自动固化（或随时手动 `evolution`/`record` 提前固化），固化后置 distilled 并按 `落点: <相对 $root 路径>` 注明落点（格式见 `harness/template/work-status.yaml`），由 `check-guidance.sh` 校验落点有效
- `close` 后工作区 status 与 AGENTS.md work 条目均为 completed
