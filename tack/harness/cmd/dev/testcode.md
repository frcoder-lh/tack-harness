---
command: testcode
short: tc
triggers: 单测, 测试, 生成单测, testcode
params: [任务ID（可选）]
summary: 可选阶段——基于 spec/plan 与代码生成单元测试，循环生成与检测直到新增/改动代码覆盖率达到 90%；用户可明确跳过
---

# testcode 单元测试（可选阶段）

> development 工作流 developing 之后的**可选**环节，也是 testing 工作流的核心执行命令。
> 用户可选择跳过本阶段（在 status.yaml 置 `progress.testcode_skipped: true`）直接进入 commit。

## 前置准入条件

- 已确定当前工作区 `$work`
- 目标任务已有实现代码（位于 `$work/repo/`）
- 仓库具备可运行的测试与覆盖率工具；没有时先与用户确认引入方式，不擅自增加重型依赖

## 输入源与加载策略（节约 token）

1. **上一阶段产物**：`$work/plan.md`（测试策略提要、任务验收标准）、`$work/spec.md`（业务规则与验收标准）
2. **代码事实**：本任务的代码 diff 与被测源码
3. **`$work/wiki/`、`$root/wiki/`**：需要背景时 grep 定位后读命中小节

**加载纪律**：遵守 `harness/rule/context-loading.md`；按任务 ID/关键词定位被测代码与已有测试（命名如 `*Test`、`*_test`、`*.spec`）

## 指令内容

1. **确认是否执行本阶段**
   - 动作: code 完成后询问用户是否进入单测阶段；用户明确跳过时：
     - 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.testcode_skipped true next commit`（自动刷新 updated_at）
     - 结束本命令
   - 选择执行则继续

2. **确定范围并回写状态**
   - 输入: 任务 ID（未指定则取最近完成、尚未补测试的任务）
   - 动作: 从 status.yaml 的 `tasks` 与代码 diff 圈定本任务新增/修改逻辑；执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage testcode task "<任务ID>" next "补齐全测并达标"`

3. **生成单元测试**
   - 输入: spec 的业务规则/验收标准 + plan 的测试策略 + 被测代码
   - 动作: 按需参考 `reference/tdd.md` 与 `harness/template/test-plan.md`，为核心分支、边界条件、异常路径编写测试；**断言对准 spec/plan 的预期行为**；测试代码只能落在 `$work/repo/`
   - 模仿仓库中已有测试的风格与组织方式

4. **循环生成与检测（覆盖率准出）**
   - 动作: 运行测试与覆盖率统计；对未覆盖分支继续补用例，重复「生成 → 运行 → 分析缺口」，直到**新增/改动代码覆盖率达到 90%**；确认不可测的代码向用户说明原因并记录

5. **审核与回写**
   - 动作: 输出新增用例清单、覆盖率结果（前后对比）、未覆盖行及原因；用户审核测试质量（非为覆盖率写无效断言）后，执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.testcode true next commit`

6. **部署验证登记（按需）**
   - 输入: 用户是否需要部署到环境泳道做联调/验证（部署动作在外部平台执行，本命令不代为部署，只登记事实）
   - 动作: 部署完成后把泳道事实登记到 `$work/status.yaml` 的 `deploy` 区块（结构见 `harness/template/work-status.yaml`）：repo / env / lane（建议从 work_id 派生）/ route / build / url / status；环境拓扑与泳道申请方式不明时查 `$root/wiki/manifest.md`「部署环境与泳道」，缺失则提示用户补充并经 `record` 沉淀
   - 边界: 只登记事实与链接，不臆造环境信息；`deploying/deployed` 状态的泳道在 `close` 时会检查回收

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): workspace state <branch>"`，把本命令对 status.yaml 的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；测试代码属于工作区代码仓库改动，由 `commit` 命令经用户确认后提交，本步骤不代为提交

## 后置完成检验

- [ ] 全部新测试通过且无稳定性问题
- [ ] 新增/改动代码覆盖率 ≥ 90%（例外已向用户说明并记录）
- [ ] 测试断言与 spec/plan 的预期行为一致
- [ ] 用户已审核测试质量；status.yaml 已同步（testcode=true 或 testcode_skipped=true）
- [ ] 已按需登记 `deploy` 泳道（或用户确认无需部署验证）

## 下一步建议

- 执行 `commit` 提交代码与测试；独立测试任务按 testing 工作流完成收尾
