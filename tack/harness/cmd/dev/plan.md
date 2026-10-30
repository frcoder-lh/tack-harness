---
command: plan
short: p
triggers: 详细设计, 开发计划, 任务拆解, plan, detailed design, development plan, task breakdown
params: [story 目录名（可选，默认唯一 story 或由用户选择）]
summary: 按 story 产出详细设计与施工图 story/<story>/plan.md——复杂任务先做多方案对比与用户选定，再落到代码/接口/SQL 细节、上线流程、模块划分与任务依赖；任务汇总到 status.yaml 的 tasks（多 story 时任务 ID 全局唯一）
---

# plan 开发计划（详细设计 + 施工图）

> development 工作流 planning 环节，**按 story 逐个执行**：把该 story 已确认的 spec 落成「怎么实施、先做什么、每步怎么验证」，具体到代码、接口、SQL 等可直接施工的细节。
> 细节集中在 `story/<story>/plan.md`；任务状态流转记在 status.yaml 的 `tasks` 列表。
> 对应技术方案中的详细设计与上线流程；别人拿到本文件可直接落实到代码。
> **关键目标**：所有需要用户决断的技术问题必须在本环节解决，让后续 code 阶段尽量不打扰用户。

## 前置准入条件

- 已确定当前工作区 `$work` 与目标 story（参数指定 `story/<story>`；未指定时若只有一个 story 直接使用，多个时由用户选择）
- `$work/story/<story>/spec.md` 存在且已经用户确认（`progress.spec: true`），其中产品/测试相关决策已全部关闭
- 执行前重新读取 `$work/status.yaml`、目标 story 的 analysis/spec，尊重本地最新内容
- spec 之外的业务决策不在本环节自行决定：发现缺失时走 `fix` 回到 spec 补充

## 输入源与加载

输入源统一口径、三级降级、代码检索顺序与防循环放大遵守 `harness/workflow/development-workflow.md`「上下文加载原则」节与 `harness/rule/context-loading.md`，项目 wiki 检索按 `harness/rule/wiki-read.md`。本环节特化：上一阶段产物以 `story/<story>/spec.md` 为主（整体设计、边界、验收标准），`story/<story>/analysis.md` 提供现有实现与兼容性事实，`context.md` 仅 grep 查 spec 未覆盖的背景细节；关键词从 spec.md 提炼（模块名/服务名/接口名/实体名）；**额外搜索是否已有类似实现**（同名/近义类、工具方法、既有模式），为「复用优先」收集依据

## 指令内容

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage plan next "生成并确认 story/<story>/plan.md"`（自动刷新 updated_at）

2. **收集链路信息与可复用资产**
   - 动作: 按「输入源与加载策略」定位并阅读 spec 圈定系统的代码事实（数据模型、接口、配置位置），不改动主仓库
   - 输出: 一份「已有可复用资产」清单（类似逻辑、工具类、配置模式及其文件路径），后续设计优先复用或模仿
   - 按需参考 reference: `domain-modeling.md`、`codebase-design.md`、`research.md`、`to-tickets.md`

3. **生成 plan.md 主体**
   - 输入: `story/<story>/spec.md` + `story/<story>/analysis.md` + `context.md` 相关片段 + `$root/wiki/<project>/` 与 `doc/analysis/` 命中内容 + 代码事实 + `$root/harness/template/plan.md`
   - 动作: 按模板在 `$work/story/<story>/plan.md` 输出：
     - 需求理解（关键约束与假设）
     - 开发环节与顺序（环节、仓库/模块、依赖、产出）
     - 业务整体逻辑（流程、状态、规则分支）
     - 数据层：实体对象、配置项（如 TCC/配置中心/特性开关）、数据变更与 SQL（DDL/DML、迁移/刷数脚本、执行顺序与回滚语句）
     - 逻辑层：领域服务、关键算法、事务一致性、异常分支
     - 接口层：接口/方法签名、入参出参、错误码、上下游调用、幂等与鉴权
     - 逐环节编码落地：改动文件范围、实现要点、自测方式、风险与回滚
     - 测试策略提要
   - 纪律: 施工图粒度——文件路径、接口签名、SQL 语句、配置键、执行顺序与验证方式齐备，别人拿到即可直接编码

4. **方案对比与选定（复杂任务门禁）**
   - 复杂度判定:
     - **可跳过**：单模块改动、存在明确可模仿的既有模式、无架构分歧的任务——一句话说明判定理由后直接采用推荐方案，仍在 plan.md 记录最终方案
     - **必须多方案**：跨模块/多仓库协作、存在两种以上合理实现路线、影响既有架构或公共接口、含非平凡数据结构/事务/兼容性变更
   - 动作（必须多方案时）:
     - 先读取 `$root/harness/agents/code-architect.md`，通过 Task 子代理**并行委派 2-3 个 architect 实例**，分别持「最小改动 / 干净架构 / 务实平衡」取向独立出方案；委派 query 须包含仓库路径、spec 关键要求、第 2 步的可复用资产清单与只读约束
     - 主 AI 汇总各方案，在 plan.md「方案对比与决策」小节输出：
       - 每个方案：核心思路、改动清单（新增/修改文件与模块）、数据与接口变更、构建顺序、Pros/Cons、风险与回滚（格式要求见角色文件）
       - **方案对比表**：对比维度至少含改动面、复用度、可维护性、兼容影响、工作量、主要风险
       - **明确推荐一个方案并给出理由**（结合代码事实与项目现状，不做无立场罗列）
     - 提交用户选定：说明推荐理由，请用户确认推荐方案或指定其他方案（也可要求补充方案）；**用户未选定前不进入模块划分**
   - 边界: 本步骤处理架构级路线选择；实现级的局部选择（异常策略、配置方式、命名等）仍归第 7 步决策点

5. **模块划分（低耦合优先）**
   - 动作: 将需求拆为**若干尽可能独立的模块**，在 plan.md 输出模块划分表：
     - 模块 | 职责（单一） | 所属仓库 | 对外暴露（接口/事件） | 依赖的模块 | 可复用资产
   - 原则:
     - 不相关的模块之间耦合越低越好：只通过明确的接口/事件交互，避免共享内部实现
     - 每个模块可独立开发、独立验证、独立演示
     - 模块内部可再拆垂直任务；模块间依赖必须形成有向无环图
   - 标注模块依赖图（文本形式，如 `A → B` 表示 B 依赖 A）

6. **逐级拆解任务**
   - 动作: 按「模块 → 特性 → 任务」拆到可独立开发、可独立验证的粒度；按 `$root/harness/template/plan.md` 的「任务清单」章节在 plan.md 末尾成稿（拆解方法按需参考 `reference/to-tickets.md`）
   - 每个任务标注：ID、标题、所属模块/仓库、**依赖任务（deps）**、验收标准、**验证方式（自测命令/测试用例/人工步骤）**、是否可与其他任务并行
   - ID 规则: 任务 ID 在整个工作区内唯一——多 story 时以 story 目录名为前缀（如 `login-validation-A-01`），单 story 可按模块分组（如 `A-01`）；无依赖的任务可并行，同模块内任务通常串行

7. **决策点前置（必须在本环节关闭）**
   - 动作: 穷举开发中可能出现的选择（技术选型、方案分支、边界处理、异常策略、配置方式等），在 plan.md 设「决策记录」小节
   - 对每个决策点：给出**推荐方案 + 理由**，能依据代码事实或最佳实践确定的直接定为结论；确实需要业务/用户决断的，列给用户一次性确认
   - 约定：code 阶段若再遇本清单外的多方案选择，AI 自动按工程最优解实现并在提交说明中记录，不中断开发
   - 分工: 架构级路线已在第 4 步关闭，本步骤只收实现级局部选择，不重复方案对比

8. **设计上线流程**
   - 动作: 在 plan.md「上线流程」小节输出可执行步骤——发布顺序（服务/仓库/依赖）、数据库变更执行顺序与兼容窗口、配置项上线顺序、灰度/分批与开关策略、回滚步骤与判定、上线前检查项
   - 边界: 上线前检查项的逐项核对由 `release-check` 按需承接；本环节只给流程、顺序与回滚方案

9. **同步任务清单到 status.yaml**
   - 动作: 汇总 `$work/story/*/plan.md` 全部任务（本次 story 的最新任务与其它 story 已有任务，按 ID 去重）写成规范化 TSV（Tab 分隔，列：`id` / `title` / `module` / `repo` / `deps-csv` / `status`，deps 用逗号分隔），先 `mkdir -p $root/.tack/tmp` 再落 `$root/.tack/tmp/tasks.tsv`；执行
     `sh $root/harness/script/work-status.sh $work/status.yaml tasks replace $root/.tack/tmp/tasks.tsv`
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml tasks validate`；退出码 4 时按 `ERROR<TAB>code<TAB>id<TAB>detail` 修复 TSV 后重试，不得绕过
   - 说明: 脚本按 id 保留已有 `acceptance` 字段，任务级状态不再手工编辑 YAML；验证方式保留在 plan.md 任务条目中；tasks 是工作区级全量清单，不得用单个 story 的任务覆盖其它 story

10. **澄清与确认（人类审阅关口）**
   - 动作: 与用户逐条确认**第 4 步选定的实现方案**、技术取舍、模块边界、任务粒度、上线流程与第 7 步的待决策项；用户确认前不进入 code

11. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.plan true next "执行 code 开始逐任务开发（需要正式评审时先执行 tech-design）"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): plan <branch>"`，把 `story/<story>/plan.md` 与 status.yaml（tasks）的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] `story/<story>/plan.md` 覆盖业务逻辑、数据层（含 SQL 与迁移）、逻辑层、接口层、上线流程、逐环节编码落地
- [ ] 施工图粒度达标：文件路径、接口签名、SQL 语句、配置键、执行顺序与验证方式齐备
- [ ] 方案门禁已履行：复杂任务有 ≥2 个方案、对比表与明确推荐，且用户已选定；简单任务已记录跳过理由与最终方案
- [ ] 模块划分低耦合、边界清晰，依赖关系无环
- [ ] 每个任务有明确交付物、deps、验收标准与验证方式；任务 ID 在工作区内唯一
- [ ] status.yaml 的 `tasks` 为全工作区汇总（含其它 story 已有任务），经 `tasks replace` 写入且 `tasks validate` 通过，初始均为 pending
- [ ] 「决策记录」中需用户决断的事项已全部关闭
- [ ] 上线流程包含发布顺序、数据与配置上线顺序、灰度策略与回滚步骤
- [ ] 已标注可复用资产；用户已审阅确认；未修改代码文件
- [ ] status.yaml 已同步（progress.plan=true）

## 下一步建议

- 需要正式评审时执行 `tech-design` 生成评审文档，否则直接执行 `code`
- 工作区还有未完成的 story 时，可先继续 `spec <story>` / `plan <story>`，再统一进入 `code`
