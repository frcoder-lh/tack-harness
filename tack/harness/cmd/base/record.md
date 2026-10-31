---
command: record
short: r
triggers: 记录, 记忆, 沉淀, record, remember, distill
params: [记录内容]
summary: 沉淀知识或扩展能力——先确定工作区与项目；能力落 harness，项目级参数落项目 wiki，工作区级参数落 status.yaml；优先融合已有条目，确无条目才新建（用户只需提供 command）
---

# record 记录沉淀

> 「生成指令的指令」：创建命令或工作流时**先检查是否已有相关条目**——有则融合修正；确无合适条目才新建。
> 新建时只要求用户提供 `command`（或工作流名），其余内容由 AI 根据用户要求自动生成草稿；新建文件、目录、命令与工作流的命名遵守 `harness/rule/naming.md`。
> 各类内容的记录规则已独立到 `harness/rule/record-*.md`，本文件只定义流程骨架。

## 前置准入条件

- 已是 tack 空间
- 记录内容必须有明确、可复用的价值；一次性过程信息不记录（判据见 `harness/rule/record-classification.md`）

## 指令内容

0. **确定工作区与项目（落盘前必做）**
   - 有 `$work` 时：读取 `$work/status.yaml` 的 `project`，并用 `sh $root/harness/script/project.sh project-get $root <project>` 核对 `tack.yaml` 中存在同名项目；不一致或为空时向用户确认
   - 无 `$work` 时：先执行 `sh $root/harness/script/project.sh ensure $root`（幂等），再执行 `project-list $root`——只有一个项目直接使用；多个项目请用户选择；没有项目且本次要落项目知识时，经用户确认后执行 `project.sh project-add` 新建
   - 边界: 项目知识的读写一律限定当前项目目录 `$root/wiki/<project>/`，不跨项目取用；工作区级参数落 `$work/status.yaml`，无 `$work` 时先请用户指定目标工作区

1. **获取记录内容（两种触发方式）**
   - 用户给了明确内容: 以参数/用户原话为准
   - 用户未给具体内容（如只说「记录一下」「把最近的引导沉淀一下」）: 有 `$work` 时执行 `sh $root/harness/script/work-status.sh $work/status.yaml guidance list pending`，无 `$work` 时执行 `sh $root/harness/script/work-status.sh $root guidance all pending`，列出候选请用户挑选；这些条目是任务结束时自动采集的用户引导（见 `harness/rule/record-lifecycle.md`）

2. **判断内容类型与落点**
   - 动作: 按 `harness/rule/record-classification.md` 的判据归入 **agents / cmd / workflow / rule / wiki**；并区分「能力」与「参数」——
     - 能力（命令、工作流、规则、脚本、模板）→ `harness/` 对应目录
     - 项目级参数与代码外事实（各环境网关地址、租户、账号、平台入口等）→ `$root/wiki/<project>/`（按 `harness/rule/wiki-write.md` 归入 `config/` 等分类）
     - 工作区级参数（MR 地址、泳道、构建版本、需求链接等）→ `$work/status.yaml` 的 `mr_url` / `meego` / `tech_doc_url` 用 `work-status.sh <status.yaml> set <字段> <值>` 写入，`deploy` 用 `deploy upsert` / `deploy mark` 写入
   - 类型存疑时按该文件的路由归类，并向用户确认；不得把工作区级参数写进 harness 或项目 wiki

3. **先扫描，再决定融合或新建**
   - cmd：按 `harness/rule/record-cmd.md` 全量扫描命令并语义匹配
   - workflow：按 `harness/rule/record-workflow.md` 全量扫描工作流并匹配
   - agents：读取 `$root/AGENTS.md`，按名称匹配 AGENT 核心约束与 tack harness 核心约束（规则见 `harness/rule/record-agents.md`）
   - rule / wiki：读取 `harness/rule/`、`$root/wiki/<project>/` 对应索引与文件匹配（规则见 `harness/rule/record-rule.md`、`harness/rule/wiki-write.md`、`harness/rule/wiki-read.md`）
   - 命中相关条目：读取对应内容，与用户确认如何**融合修正**（最小化修改，不重写无关内容；同义条目只更新不重复追加）
   - 确无合适条目：进入第 4 步落盘（cmd/workflow 为新建，其余为直接落盘）

4. **落盘**
   - 按所属类型的规则文件执行：
     - agents → `harness/rule/record-agents.md`（AGENTS.md 的 AGENT / tack harness 核心约束；仅限对本空间所有项目成立的常驻约束）
     - cmd → `harness/rule/record-cmd.md`（复制 `template/cmd.md` 到 `harness/cmd/<分组>/`）
     - workflow → `harness/rule/record-workflow.md`（复制 `template/workflow.md` 到 `harness/workflow/`）
     - rule → `harness/rule/record-rule.md`（`harness/rule/` 新建或追加）
     - wiki → `harness/rule/wiki-write.md`（按分类与索引写入 `$root/wiki/<project>/`，融合或按模板创建）

5. **人工审阅**
   - 动作: 展示落盘内容与路径，用户确认后生效（AGENTS.md 核心约束与项目 wiki 内容必须经人工审阅才可作为上下文）

6. **验证生效并回写 guidance**
   - 动作:
     - cmd / workflow：执行 `sh $root/harness/script/scan-routes.sh list $root/harness`，确认新建/修改后的条目出现在路由表中
     - agents：重新读取 `$root/AGENTS.md`，确认条目落在对应约束分组、位置正确，且未改动命令路由、数据来源与目录概览等固定章节
     - 本次内容来自 guidance 条目: 执行 `sh $root/harness/script/work-status.sh <来源 status.yaml> guidance <id> applied <落点路径...>`（多落点空格分隔，脚本校验落点文件存在后只置 `status: applied`）；用户挑选后放弃的条目执行 `sh $root/harness/script/work-status.sh <来源 status.yaml> guidance <id> rejected`

7. **版本检查（更新提醒挂载点）**
   - 动作: 按 `harness/rule/update-check.md` 执行 `sh $root/harness/script/check-update.sh $root`；有新版本时原样转述并**建议先执行 `update` 再继续沉淀**（避免在旧版 harness 上落盘，改动可能与新版冲突）

## 框架自动提交（无需用户操作）

- 动作: 人工审阅生效后，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): record distilled knowledge"`，把新增/融合的 cmd、workflow、rule、wiki、AGENTS.md 沉淀条目自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] 已确定工作区与项目；项目知识与工作区参数分别落到 `wiki/<project>/` 与 `$work/status.yaml`，未混写
- [ ] 能力与参数落点正确（能力 harness / 项目级参数项目 wiki / 工作区级参数 status.yaml）；易变代码逻辑未写入 wiki
- [ ] 已优先尝试融合已有相关条目；新建是在确无合适条目后进行
- [ ] 新建 cmd 时用户只提供了 command，其余字段为 AI 自动生成并经审阅
- [ ] 文件已落盘到正确目录，文件头字段完整
- [ ] agents 条目落在 AGENTS.md 对应核心约束分组且仅限全空间约束，未改动固定章节；scan-routes 能扫描到新 cmd/workflow 条目
- [ ] 素材来自 guidance 时，来源条目已回写 applied 或 rejected
- [ ] 用户已审阅确认
- [ ] 版本检查已执行；有新版本时已原样转述提醒与更新内容，并建议先执行 `update`

## 规则文件索引

| 文件 | 作用 |
|------|------|
| `harness/rule/record-classification.md` | 五类内容的分类判据、能力/参数落点、wiki 文件分工、存疑路由 |
| `harness/rule/record-lifecycle.md` | guidance 的触发条件、原始记录与固化入口（采集/固化细则） |
| `harness/rule/record-agents.md` | 沉淀 AGENTS.md 两个约束分组的格式、适用范围与边界 |
| `harness/rule/record-cmd.md` | 命令的扫描融合、新建模板字段、分组选择 |
| `harness/rule/record-workflow.md` | 工作流的扫描融合与新建 |
| `harness/rule/record-rule.md` | 编码规范/研发规则的落点与融合 |
| `harness/rule/wiki-write.md` | 项目 wiki 的分类、组织、写入、来源链、矛盾演变与索引更新（`close` 提炼内容时同样适用） |
| `harness/rule/wiki-read.md` | 项目 wiki 的索引导航、检索顺序、代码核实与取用纪律 |

## 下一步建议

- 新命令/工作流立即用 `/tack <触发词>` 试用；项目 wiki 内容会在 `spec`/`plan` 时被自动检索；核心约束随 AGENTS.md 常驻生效，下轮对话自动加载
