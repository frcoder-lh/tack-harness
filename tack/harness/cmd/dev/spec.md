---
command: spec
short: sp
triggers: 需求规划, 整体设计, spec, requirement planning, overall design
params: 无
summary: 读 input.md、wiki（root/work）与代码事实，按 harness/template/spec.md 产出顶层设计与公共契约 spec.md——需求理解与调研、可行性判断、候选实现路线、需提前决策事项、story 拆分、系统边界、验收标准、测试要点与开发估时；产品/测试相关决策在本环节关闭
---

# spec 需求规划（顶层设计 + 公共契约）

> development 工作流进入 planning 的第一个环节。只做规划，不改任何代码。
> 定位：研发、产品、测试都能读懂的公共契约——回答做什么、为什么做、边界在哪、如何验收；完成需求理解、调研与拆分。
> 本环节结束，产品与测试退场：需要他们决策的事项必须在此阶段全部关闭。

## 前置准入条件

- 已确定当前工作区 `$work`（`$root/space/<workspace>/`），且 `$work/status.yaml` 存在
- `$work/input.md` 中已有真实的原始需求；为空时先引导用户补充，不凭空编造需求
- 执行前重新读取 `$work/status.yaml`，尊重本地最新状态

## 输入源与加载

输入源统一口径、三级降级与防循环放大遵守 `harness/workflow/development-workflow.md`「上下文加载原则」节与 `harness/rule/context-loading.md`（先 grep/glob 定位再只读命中片段，禁止整仓通读）。本环节为首环节：`$work/input.md` 全文读取；wiki 只加载实际存在的文件（缺失视为该领域暂无沉淀，不是异常）；检索关键词从 input.md 提炼（业务名词、服务名、接口名、模块名）

## 指令内容

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set status planning stage spec next "生成并确认 spec.md"`（自动刷新 updated_at）

2. **检索、调研与可行性评估**
   - 输入: input.md 中的需求关键词
   - 动作: 按「输入源与加载策略」grep 定位 wiki 与代码中的相关内容，列出命中要点（带来源路径）；阅读涉及模块的入口与关键实现（只读），基于代码事实判断可行性
   - 输出: 调研要点 + 可行性结论（可实现 / 需改造 / 不可行）+ 候选实现方式（路线级，标注取舍）+ 需提前决策事项（明确决策人）
   - 按需参考 reference（须经本命令引用方可加载）: `grill-with-docs.md`、`grilling.md`、`domain-modeling.md`、`to-spec.md`

3. **生成 spec.md**
   - 输入: `$work/input.md` 原文 + `$root/wiki/<project>/` 与 `$work/wiki/` 命中要点 + 代码事实 + `$root/harness/template/spec.md`
   - 动作: 按模板章节在 `$work/spec.md` 输出：背景目标与范围、需求调研与可行性（含候选实现方式、需提前决策事项）、Story 拆分、系统与模块影响面、模块关系与交互、边界约定、验收标准（合同）、测试要点、开发估时、风险与待澄清
   - 纪律: 对原始需求只做格式整理与梳理，不篡改原始含义；候选实现方式只到路线级，不写数据结构、接口签名、编码步骤等实现细节（属于 plan.md）

4. **澄清与确认（人类审阅关口）**
   - 动作: 逐条提出待澄清问题并回写答案；与研发、产品、测试共同确认边界、验收标准、测试要点与估时，产品/测试相关决策在本环节全部关闭；spec.md 必须经用户明确确认
   - 边界: 本环节之后产品与测试退场，后续环节新出现的业务决策走 `fix` 回到本环节，不在 plan 中自行决定

5. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.spec true stage spec next "执行 plan 生成详细设计与上线流程"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): spec <branch>"`，把 spec.md 与 status.yaml 的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] `$work/spec.md` 存在，需求调研、可行性判断、候选实现方式、Story、边界、交互、验收标准、测试要点、开发估时完整
- [ ] 候选实现方式只到路线级，未写入数据结构、接口签名与编码步骤
- [ ] 需提前决策的事项已明确决策人，产品/测试相关决策已全部关闭
- [ ] 待澄清问题均有关闭或后续结论
- [ ] 用户已审阅确认；本环节未修改任何代码文件
- [ ] `$work/status.yaml` 已同步（planning / progress.spec=true）

## 下一步建议

- 执行 `plan`，基于确认的 spec 产出详细设计、上线流程与任务拆解
