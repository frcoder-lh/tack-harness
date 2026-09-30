---
command: record
short: r
triggers: 记录, 记忆, 沉淀, record
params: [记录内容]
summary: 沉淀知识或扩展能力——优先融合已有条目；可落命令/工作流/规则/wiki/AGENTS.md 常驻约定，否则交互式新建（用户只需提供 command）
---

# record 记录沉淀

> 「生成指令的指令」：创建命令或工作流时**先检查是否已有相关条目**——有则融合修正；确无合适条目才新建。
> 新建时只要求用户提供 `command`（或工作流名），其余内容由 AI 根据用户要求自动生成草稿。
> 各类内容的记录规则已独立到 `harness/rule/record-*.md`，本文件只定义流程骨架。

## 前置准入条件

- 已是 tack 空间
- 记录内容必须有明确、可复用的价值；一次性过程信息不记录（判据见 `harness/rule/record-classification.md`）

## 指令内容

1. **获取记录内容（两种触发方式）**
   - 用户给了明确内容: 以参数/用户原话为准
   - 用户未给具体内容（如只说「记录一下」「把最近的引导沉淀一下」）: 读取 `$work/status.yaml` 的 `guidance` 中 `status: raw` 条目（不存在 `$work` 时扫描 `$root/space/*/status.yaml`），列出候选请用户挑选；这些条目是任务结束时自动采集的用户引导（AGENTS.md 第 11 条）

2. **判断内容类型**
   - 动作: 按 `harness/rule/record-classification.md` 的判据归入 **agents / cmd / workflow / rule / wiki**；类型存疑时按该文件的路由归类，并向用户确认

3. **先扫描，再决定融合或新建**
   - cmd：按 `harness/rule/record-cmd.md` 全量扫描命令并语义匹配
   - workflow：按 `harness/rule/record-workflow.md` 全量扫描工作流并匹配
   - agents：读取 `$root/AGENTS.md`，匹配「核心约束」编号条目与「沉淀约定」区块已有条目（规则见 `harness/rule/record-agents.md`）
   - rule / wiki：读取 `harness/rule/`、`$root/wiki/` 对应文件匹配（规则见 `harness/rule/record-rule.md`、`harness/rule/record-wiki.md`）
   - 命中相关条目：读取对应内容，与用户确认如何**融合修正**（最小化修改，不重写无关内容；同义条目只更新不重复追加）
   - 确无合适条目：进入第 4 步落盘（cmd/workflow 为新建，其余为直接落盘）

4. **落盘**
   - 按所属类型的规则文件执行：
     - agents → `harness/rule/record-agents.md`（AGENTS.md「沉淀约定」区块）
     - cmd → `harness/rule/record-cmd.md`（复制 `template/cmd.md` 到 `harness/cmd/<分组>/`）
     - workflow → `harness/rule/record-workflow.md`（复制 `template/workflow.md` 到 `harness/workflow/`）
     - rule → `harness/rule/record-rule.md`（`harness/rule/` 新建或追加）
     - wiki → `harness/rule/record-wiki.md`（`$root/wiki/` 融合或按模板创建）

5. **人工审阅**
   - 动作: 展示落盘内容与路径，用户确认后生效（AGENTS.md 沉淀约定与 wiki 内容必须经人工审阅才可作为上下文）

6. **验证生效并回写 guidance**
   - 动作:
     - cmd / workflow：执行 `sh $root/harness/script/scan-routes.sh list $root/harness`，确认新建/修改后的条目出现在路由表中
     - agents：重新读取 `$root/AGENTS.md`，确认条目位置正确、区块标记与项目信息区块完好
     - 本次内容来自 guidance 条目: 在来源 status.yaml 中将该条 `status` 置 `distilled`，并另起一行按固定格式注明落点：`落点: <相对 $root 的路径>`（多落点空格分隔，格式见 `harness/template/work-status.yaml`）；用户挑选后放弃的条目置 `dismissed`

7. **版本检查（更新提醒挂载点）**
   - 动作: 沉淀完成、下一步建议之前，执行 `sh $root/harness/script/check-update.sh $root`（Windows 经 run.ps1 启动；脚本内部双节流，无新版本时静默）
   - 输出协议: 无输出则不提及；stdout 非空时为「有新版本」提醒（首行）+ 本机版本至最新版本区间的更新内容摘要（其后各行，可能没有），原样转述并**建议先执行 `update` 再继续沉淀**（避免在旧版 harness 上落盘，改动可能与新版冲突）；脚本非零退出时忽略，不向用户报错

## 框架自动提交（无需用户操作）

- 动作: 人工审阅生效后，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): record distilled knowledge"`，把新增/融合的 cmd、workflow、rule、wiki、AGENTS.md 沉淀条目自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] 内容类型判断正确（常驻约定 agents / 编码规范 rule / 事实·锚点·业务知识·决策约定 wiki / 流程能力 cmd·workflow）；易变代码逻辑未写入 wiki
- [ ] 已优先尝试融合已有相关条目；新建是在确无合适条目后进行
- [ ] 新建 cmd 时用户只提供了 command，其余字段为 AI 自动生成并经审阅
- [ ] 文件已落盘到正确目录，文件头字段完整
- [ ] agents 条目落在「沉淀约定」区块且未触碰项目信息 YAML 区块与 harness 固定章节；scan-routes 能扫描到新 cmd/workflow 条目
- [ ] 素材来自 guidance 时，来源条目已回写 distilled（含落点）或 dismissed
- [ ] 用户已审阅确认
- [ ] 版本检查已执行；有新版本时已原样转述提醒与更新内容，并建议先执行 `update`

## 规则文件索引

| 文件 | 作用 |
|------|------|
| `harness/rule/record-classification.md` | 五类内容的分类判据、wiki 四类分工、存疑路由 |
| `harness/rule/record-agents.md` | 沉淀 AGENTS.md「沉淀约定」区块的格式、边界与模板 |
| `harness/rule/record-cmd.md` | 命令的扫描融合、新建模板字段、分组选择 |
| `harness/rule/record-workflow.md` | 工作流的扫描融合与新建 |
| `harness/rule/record-rule.md` | 编码规范/研发规则的落点与融合 |
| `harness/rule/record-wiki.md` | wiki 四类文件分工、边界、来源链、矛盾演变、落盘方式（close 提炼内容时同样适用） |

## 下一步建议

- 新命令/工作流立即用 `/tack <触发词>` 试用；wiki 内容会在 `spec`/`plan` 时被自动检索；沉淀约定随 AGENTS.md 常驻生效，下轮对话自动加载
