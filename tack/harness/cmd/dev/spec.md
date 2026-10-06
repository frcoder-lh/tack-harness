---
command: spec
short: sp
triggers: 需求规划, 整体设计, spec, requirement planning, overall design
params: 无
summary: 读 input.md、wiki（root/work）与代码事实，按 harness/template/spec.md 产出需求规划文档 spec.md（story 拆分、模块边界、验收标准）
---

# spec 需求规划（整体设计）

> development 工作流进入 planning 的第一个环节。只做规划，不改任何代码。
> 定位：开发施工图 + 验收合同——划清系统/模块边界与交互，不写实现细节。

## 前置准入条件

- 已确定当前工作区 `$work`（`$root/space/<workspace>/`），且 `$work/status.yaml` 存在
- `$work/input.md` 中已有真实的原始需求；为空时先引导用户补充，不凭空编造需求
- 执行前重新读取 `$work/status.yaml`，尊重本地最新状态

## 输入源与加载策略（节约 token）

本环节可参考的输入（按优先级）：

1. **`$work/input.md`**：原始需求（全文读取，篇幅不大时）
2. **`$root/wiki/`**：项目公共知识（business-understanding.md、code-understanding.md、manifest.md、decisions.md 等）；wiki 文件由 init/record/close 按需物化，**只加载实际存在的文件，缺失文件视为该领域暂无沉淀，不是异常**
3. **`$work/wiki/`**：工作区级代码理解产物（如 ask 生成的 `<repo>-analysis.md` 及问答文档）
4. **代码事实**：`$work/repo/<repo-name>/` 中的现有代码（只读）
5. **上一阶段产物**：本环节为首环节，无

**加载纪律**：遵守 `harness/rule/context-loading.md`——先 grep/glob 定位再只读命中片段，禁止整仓通读；关键词从 input.md 提炼（业务名词、服务名、接口名、模块名）

## 指令内容

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set status planning stage spec next "生成并确认 spec.md"`（自动刷新 updated_at）

2. **检索与定位**
   - 输入: input.md 中的需求关键词
   - 动作: 按「输入源与加载策略」grep 定位 wiki 与代码中的相关内容，列出命中要点（带来源路径）
   - 按需参考 reference（须经本命令引用方可加载）: `grill-with-docs.md`、`grilling.md`、`domain-modeling.md`、`to-spec.md`

3. **生成 spec.md**
   - 输入: `$work/input.md` 原文 + wiki/代码命中要点 + `$root/harness/template/spec.md`
   - 动作: 按模板章节在 `$work/spec.md` 输出：背景目标与范围、Story 拆分（优先级、涉及系统/模块、验收标准）、系统与模块影响面、模块关系与交互、边界约定、验收标准（合同）、风险与待澄清
   - 纪律: 对原始需求只做格式整理与梳理，不篡改原始含义；不写数据结构、编码步骤等实现细节（属于 plan.md）

4. **澄清与确认（人类审阅关口）**
   - 动作: 逐条提出待澄清问题并回写答案；spec.md 必须经用户明确确认

5. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.spec true stage spec next "执行 plan 生成详细设计"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): spec <branch>"`，把 spec.md 与 status.yaml 的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；代码仓库的提交仍由 `commit` 命令执行（自动生成提交信息后直接提交，无需二次确认）

## 后置完成检验

- [ ] `$work/spec.md` 存在，story、边界、交互、验收标准完整
- [ ] 待澄清问题均有关闭或后续结论
- [ ] 用户已审阅确认；本环节未修改任何代码文件
- [ ] `$work/status.yaml` 已同步（planning / progress.spec=true）

## 下一步建议

- 执行 `plan`，基于确认的 spec 产出详细开发计划与任务拆解
