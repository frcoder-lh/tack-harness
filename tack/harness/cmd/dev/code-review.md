---
command: code-review
short: rv
triggers: 代码审查, 审查报告, code-review, codereview, review, code review, review report
params: [目标分支（默认主干）]
summary: 合并前独立深度审查——以 plan.md/tech-design.md 为规范、与目标分支的三点 diff 为事实，逐函数分析改动内容、逻辑正确性与代码危害，评估影响的接口与业务场景，产出 $work/code-review.md 审查报告
---

# code-review 代码审查

> 产出**独立审查报告文档**的深度审查：回答「改了什么、改得对不对、会影响谁」。
> 审查方法论（双轴 Spec/Standards、Fowler 代码味道基线）以 `harness/reference/code-review.md` 为准，本命令是其 harness 化执行：脚本导出 diff 事实、逐函数锚点分析、报告落盘。
> 与 `merge` 第 2 步的门禁审查（分级问题清单 + 三选一分流）互补：本命令可在编码完成后任何时刻执行，报告落盘、可评审、可归档；审查基准一致时，`merge` 门禁审查可直接复用本报告结论。

## 前置准入条件

- 已确定当前工作区 `$work`
- `$work/plan.md` 已确认（`progress.plan: true`）；`$work/tech-design.md` 存在（无则在报告头部注明规范来源仅 plan.md）
- 各涉及仓库当前分支改动已 `commit`（审查基于提交事实，未提交改动不进入范围）；建议先 `fetch`
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——只读操作仅在 `$work/repo/<repo-name>/` 内执行

## 指令内容

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage review task 代码审查 next 生成code-review.md`（自动刷新 updated_at）；不改变 `status`

2. **确定审查范围并导出 diff 事实**
   - 输入: 目标分支参数（默认主干 master/main，由脚本自动探测）
   - 动作: 汇总本需求涉及的仓库（status.yaml tasks 的 `repo` 字段 + plan.md 模块划分「所属仓库」列，去重），逐仓库执行：
     `sh $root/harness/script/git-diff-context.sh $work/repo/<repo-name> $root/.tack/tmp/review [目标分支]`
     解析输出行：`target_ref`、`merge_base`、`head`、`empty`、`files_changed`、`diff_file`、`stat_file`
   - `empty: true` 的仓库向用户说明后跳过；全部为空时中止并提示「与目标分支无差异，无需审查」
   - 边界: 脚本只搬运确定性事实（ref 解析、merge-base、diff 导出），逐函数语义分析由本命令完成

3. **加载规范与标准来源**
   - 规范: `$work/plan.md`（模块划分、逐环节落地、决策记录）、`$work/tech-design.md`（技术方案）；`$work/spec.md`（验收标准，辅助）
   - 标准: `$root/harness/rule/coding-standards.md` 已有实质条目的小节（空小节跳过）；涉及外部输入、鉴权、凭据、数据库查询、文件路径时**必加载 `security.md`**
   - 上下文辅助: `$work/wiki/`（分析文档、调用链梳理）用于影响面定位；加载纪律遵守 `harness/rule/context-loading.md`

4. **逐函数分析改动（双轴审查）**
   - 方法: 审查框架遵循 `harness/reference/code-review.md` 的双轴（Spec/Standards，含 Fowler 代码味道基线）；本命令把双轴落到「仓库 → 文件 → 函数/方法」粒度，逐个分析：
     1. **改动内容（事实组织）**：该函数改了什么（新增/修改/删除、意图一句话），对应代码段以 `路径#L起-L止` 锚点引用（取 HEAD 侧行号，删除的代码标注 diff 位置）
     2. **规范轴（Spec）**：实现是否忠实于 plan.md 落地方案与 tech-design.md 技术方案（功能缺失、部分实现、范围蔓延），不一致处指出并引用规范条目；并深化查明显 bug——边界与异常分支遗漏、空值/越界、并发与事务、资源未释放、错误被吞
     3. **标准轴（Standards）**：对照 coding-standards.md 实质条目、代码味道基线与 security.md 安全模式，查安全（注入/越权/凭据泄露）、性能（N+1/无界循环/缺分页）、兼容性（函数签名或协议变更影响既有调用方）
   - 大改动（跨模块/多仓库）时**并行委派 code-reviewer**：读取 `$root/harness/agents/code-reviewer.md`，按其三视角（规范符合度 / bug 与正确性 / 约定与安全，与双轴的映射见该文件）各委派一个实例，审查范围 `git diff <目标分支>...HEAD`；主 AI 按双轴归类各实例结论融入报告，每条保留 `文件:行号` 证据
   - 纪律: 只审查本次变更新引入或放大的问题；顺手发现的历史问题单列「历史问题（不在本次范围）」，不计入结论；没有证据（路径:行号 + 依据）不报

5. **影响面分析**
   - 动作: 基于 diff 与调用链（结合 `$work/wiki/` 分析文档、代码内搜索调用方）识别：
     - **受影响接口**：对外 HTTP/RPC API（路径/方法/入出参变化）、消息生产/消费（topic、消息体）、定时任务、DB schema（表/字段/索引）、被改函数的全部调用方
     - **涉及业务场景**：沿调用链向上追到用户可感知入口（页面/接口/任务），列场景名与关联代码入口锚点
   - 输出: 接口表（接口 | 变化类型 | 代码锚点 | 影响说明）与场景表（场景 | 入口锚点 | 关联改动）

6. **生成审查报告 `$work/code-review.md`**
   - 头部: `> 审查范围: <target_ref>...HEAD（merge-base: <short-hash>）　仓库: <清单>　生成时间: <日期>`
   - 章节结构:
     1. **概览**：各仓库改动统计（文件数/+/−）与一句话总评
     2. **改动清单**：按仓库-文件-函数列出「改动内容 + 对应代码段锚点」
     3. **双轴发现**：分「Spec（规范符合 / bug 与正确性）」「Standards（约定 / 安全 / 味道）」两组呈现（双轴不合并，方法论见 `harness/reference/code-review.md`），每条按 Critical / Warning / Suggestion 分级：`[级别] 标题 —— 文件:行号 —— 依据（规范条款/标准条目/安全模式）—— 修复建议`
     4. **影响面**：受影响接口表、涉及场景表
     5. **结论与建议**：是否可进入合并；需修复项的处置建议（`fix` / 记录后续）
   - 向用户呈现报告要点并请审阅；用户指出误判时修正后重出对应小节

7. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.review true next "修复审查发现问题（fix）或执行 merge；上线前可执行 release-check"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): code review <branch>"`，把 `$work/code-review.md` 与 status.yaml 变更自动提交到空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；`.tack/tmp/review/` 的 diff 临时文件不入库、可随时清理

## 后置完成检验

- [ ] 每个涉及仓库均经 git-diff-context.sh 导出事实，empty 仓库已说明；报告头部审查范围与实际一致
- [ ] 改动清单覆盖 diff 中全部改动文件与函数，每条有 `路径#L行号` 锚点
- [ ] 双轴发现均有证据（路径:行号 + 依据）：规范轴对照 plan.md/tech-design.md 具体条目，标准轴引用编码标准/代码味道/security.md 条目；无臆测
- [ ] 影响面已列出受影响接口与涉及场景；签名/协议变更已核对全部调用方
- [ ] `$work/status.yaml` 的 progress.review 已置 true；本命令未修改任何代码文件

## 下一步建议

- 存在 Critical/Warning：执行 `fix` 修复后重新执行本命令复审
- 审查通过：执行 `merge`（其门禁审查可复用本报告结论）；上线前执行 `release-check` 生成上线检查清单
