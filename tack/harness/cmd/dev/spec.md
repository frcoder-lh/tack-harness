---
command: spec
short: sp
triggers: 需求规划, 整体设计, spec, requirement planning, overall design
params: [story 目录名（可选，默认唯一 story 或由用户选择）]
summary: 按 story 做需求规划——读 context.md、story/<story>/analysis.md、项目 wiki 与代码事实，产出 story/<story>/spec.md 顶层设计与公共契约（需求理解与调研、可行性、候选实现路线、需提前决策事项、功能场景、系统边界、验收标准、测试要点与开发估时）；产品/测试相关决策在本环节关闭
---

# spec 需求规划（顶层设计 + 公共契约）

> development 工作流进入 planning 的第一个环节，**按 story 逐个执行**。只做规划，不改任何代码。
> 定位：研发、产品、测试都能读懂的公共契约——回答做什么、为什么做、边界在哪、如何验收；完成需求理解、调研与拆分。
> 本环节结束，产品与测试退场：需要他们决策的事项必须在此阶段全部关闭。

## 前置准入条件

- 已确定当前工作区 `$work`（`$root/space/<workspace>/`），且 `$work/status.yaml` 存在
- 已确定目标 story：参数指定 `story/<story>`，未指定时若 `story/` 下只有一个 story 直接使用，多个时列出清单由用户选择
- `$work/context.md` 中已有真实的原始需求；`$work/story/<story>/analysis.md` 已生成并经用户确认（缺失时先执行 `analyze <需求描述>`，不凭空编造需求）
- 执行前重新读取 `$work/status.yaml`、`context.md` 与目标 story 的 analysis.md，尊重本地最新状态

## 输入源与加载

- 输入源统一口径、三级降级、代码检索顺序与防循环放大遵守 `harness/workflow/development-workflow.md`「上下文加载原则」节与 `harness/rule/context-loading.md`，项目 wiki 检索按 `harness/rule/wiki-read.md`（先读索引再读命中文件，禁止整仓通读）。本环节特化：`context.md` 中本 story 对应的需求原文与 `story/<story>/analysis.md` 全文读取；`doc/analysis/` 与项目 wiki 只加载命中内容（缺失视为该领域暂无沉淀，不是异常）；检索关键词从需求与 analysis 中提炼（业务名词、服务名、接口名、模块名）

## 指令内容

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set status planning stage spec next "生成并确认 story/<story>/spec.md"`（自动刷新 updated_at）

2. **检索、调研与可行性评估**
   - 输入: 本 story 需求与分析中的关键词
   - 动作: 以 `story/<story>/analysis.md` 的现有实现与可行性结论为起点，按「输入源与加载策略」grep 定位项目 wiki、`doc/analysis/` 与代码中的补充内容，列出命中要点（带来源路径）；analysis 未覆盖或已过时的部分回查代码（只读）
   - 输出: 调研要点 + 可行性结论（可实现 / 需改造 / 不可行）+ 候选实现方式（路线级，标注取舍）+ 需提前决策事项（明确决策人）
   - 按需参考 reference（须经本命令引用方可加载）: `grill-with-docs.md`、`grilling.md`、`domain-modeling.md`、`to-spec.md`

3. **生成 spec.md**
   - 输入: `context.md` 中本 story 的需求原文 + `story/<story>/analysis.md` + `$root/wiki/<project>/` 与 `doc/analysis/` 命中要点 + 代码事实 + `$root/harness/template/spec.md`
   - 动作: 按模板章节在 `$work/story/<story>/spec.md` 输出：背景目标与范围、需求调研与可行性（含候选实现方式、需提前决策事项）、功能场景拆分、系统与模块影响面、模块关系与交互、边界约定、验收标准（合同）、测试要点、开发估时、风险与待澄清
   - 纪律: 对原始需求只做格式整理与梳理，不篡改原始含义；候选实现方式只到路线级，不写数据结构、接口签名、编码步骤等实现细节（属于 plan.md）

4. **澄清与确认（人类审阅关口）**
   - 动作: 逐条提出待澄清问题并回写答案；与研发、产品、测试共同确认边界、验收标准、测试要点与估时，产品/测试相关决策在本环节全部关闭；spec.md 必须经用户明确确认
   - 边界: 本环节之后产品与测试退场，后续环节新出现的业务决策走 `fix` 回到本环节，不在 plan 中自行决定；澄清中发现的代码事实补回 `story/<story>/analysis.md` 的待确认问题区

5. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.spec true stage spec next "对同一 story 执行 plan，或切换到下一个 story"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): spec <branch>"`，把 `story/<story>/spec.md` 与 status.yaml 的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] `$work/story/<story>/spec.md` 存在，需求调研、可行性判断、候选实现方式、功能场景、边界、交互、验收标准、测试要点、开发估时完整
- [ ] 候选实现方式只到路线级，未写入数据结构、接口签名与编码步骤
- [ ] 需提前决策的事项已明确决策人，产品/测试相关决策已全部关闭
- [ ] 待澄清问题均有关闭或后续结论；新增代码事实已回写 analysis.md 的待确认问题区
- [ ] 用户已审阅确认；本环节未修改任何代码文件
- [ ] `$work/status.yaml` 已同步（planning / progress.spec=true）

## 下一步建议

- 执行 `plan <story>`，基于确认的 spec 产出详细设计、上线流程与任务拆解
- 工作区还有未分析的 story 时，先执行 `analyze` 补齐其 analysis.md
