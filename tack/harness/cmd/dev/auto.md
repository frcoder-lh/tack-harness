---
command: auto
short: au
triggers: 自动执行, 全自动, 自动流转, 自动开发, auto, auto run, automatic execution, autopilot
params: [结束点或附加要求（可选）]
summary: 自动执行当前工作流剩余环节直到终态——开始前一次性补齐缺失信息并确认全流程，确认后连续执行不中断，结束时汇总关键决策与结果
---

# auto 自动执行

> 面向「从当前进度一路做到需求完成」的场景：把当前工作流剩余环节串成一条链路，前置一次性补齐信息并确认，确认后按各环节命令的规则连续执行，不再逐环节等待审阅。
> 各环节的准入准出、规则、脚本调用与安全禁令以对应 `harness/cmd/` 文件为唯一权威；本命令只负责编排、授权边界与最终汇报。

## 前置准入条件

- 已确定当前工作区 `$work` 与所属项目（`$work/status.yaml` 的 `project`）；项目为空或与 `tack.yaml` 的 `projects` 不一致时先向用户确认
- 无 `$work` 时先执行 `work` 创建或切换工作区，本命令不新建工作区
- `$work/status.yaml` 存在；当前工作流由 `workflow` / `status` 与 `progress` 判定（development / testing / bugfix / merge-conflict / branch-op）
- 当前工作流不在 `blocked` 状态；已 blocked 时先补齐阻塞原因并解除，再进入第 1 步
- 执行前重新读取 status.yaml 与已有产物，尊重本地最新内容

## 指令内容

1. **确认当前状态并推导剩余链路**
   - 动作: 读取 `$work/status.yaml`（status / workflow / progress / tasks / current / branches / deploy）、已有产物（context、`story/*/analysis.md`、`story/*/spec.md`、`story/*/plan.md`、`doc/tech-design.md`、`doc/test.md`、`doc/code-review.md`）与当前工作流文档的「各环节与命令映射」
   - 已完成的环节（progress 为 true 或产物已确认）不重跑；`in_progress` / `blocked` 的任务按状态续跑；工作区有多个 story 时，按 story 逐个完成 analyze → spec → plan，再统一进入 code
   - 按工作流推导剩余链路（默认执行到该工作流终态，`close` 是否包含由第 2 步确认）：

     | 工作流 | 剩余链路（从当前环节起） | 默认终态 |
     |--------|--------------------------|----------|
     | development | analyze → spec → plan →（需要正式评审时）tech-design → code → commit → push → merge（push 遇 non-fast-forward 转 fetch/solve；merge 自带 fetch 与冲突处理） | merged |
     | testing | testcode → test → run（按需）→ commit → push | completed |
     | bugfix | 复现 → 诊断/缺陷溯源 → code → 验证 → commit → push →（按需 merge） | completed |
     | merge-conflict | fetch → merge → solve（冲突时）→ 验证 → push | completed |
     | branch-op | prepare → integrate → solve（冲突时）→ push | completed |

   - 用户参数或后续确认可调整链路（如「带上 tech-design」「带上 testcode」「到 merge 为止」「一并 close」），以调整后的链路为准
   - 断点续跑: 上次 auto 中断时，从 `current.next` 与未完成环节继续，不重复已完成环节

2. **一次性补齐后续流程缺失的信息**
   - 动作: 只收集**无法从 status.yaml、已有产物、代码、git 事实与 wiki 判定、且后续环节必须输入**的信息；已有结论不重复询问
   - 按当前工作流取用检查清单（仅问缺失项）：

     | 工作流 | 必问项（事实缺失时） |
     |--------|----------------------|
     | development | 原始需求与验收标准（`context.md` 为空或含糊、`story/` 尚未拆分）；涉及仓库是否就绪、缺失时是否新建；远端关联与 push 权限；源分支引用（本地/远端，仅两侧内容不同时必须确认）；目标分支无法自动判定时的取值；保护分支是否走平台 MR 及由谁合并；是否需要正式评审（决定是否执行 tech-design，默认不执行）；按需命令是否纳入（testcode / test / run / code-review / release-check，默认不纳入）；是否一并 close（默认不）；是否需要 deploy 登记 |
     | testing | 测试范围或任务 ID；覆盖率门槛（默认 90%）；测试环境与凭据；是否需要系统测试与脚本执行；提交、推送与是否合并 |
     | bugfix | 现象、期望与实际；复现环境与步骤；日志/账号等必需输入；根因判定与修复授权（按证据确认后直接修复）；是否补回归测试；是否 merge |
     | merge-conflict | 源分支、目标分支与本地/远端引用；冲突取舍原则（业务优先级、保留哪侧）；验证命令；是否推送 |
     | branch-op | 源分支、目标分支、op（merge/rebase）与源引用；是否推送；rebase 推回原分支需当次明确的重写历史授权；是否在收尾时清理临时分支 |

   - 缺失但用户未补充、且无法从事实取得的输入不得编造：列为阻塞项，本轮不开始执行
   - 输出: 一份「已补齐信息 + 仍缺失/待确认项」清单；本次执行约定（结束点、跳过项、附加要求、收尾策略）暂存在待确认内容中，用户确认后才写入 status.yaml

3. **确认整个流程（本次执行唯一的人类审阅关口）**
   - 向用户展示:
     - 当前工作区 / 项目 / 工作流 / 当前环节
     - 剩余链路（含可选与按需环节、结束点）
     - 本次执行约定
     - 已知风险与可能的阻塞点
   - 明确授权范围: 各环节的常规确认关口由本次确认一次性授权——spec/plan/tech-design 审阅、plan 多方案选定、code 模块里程碑、merge 方向与源引用、close 的非完成态确认等，由 AI 按对应命令规则执行并记录决策；**不包含**安全禁令与准入校验的放宽，也不代替用户做业务/产品决策
   - 明确收尾策略（仅在包含 `close` 时生效）: 默认只列出 wiki / guidance 候选与建议落点、不自动写入；用户可在确认时明确授权「有工作区来源且可证实的候选自动落盘」
   - 明确说明: 确认后连续执行，仅在真实阻塞时停止
   - 用户确认 → 进入第 4 步；用户调整链路或约定 → 更新后重新确认；用户不确认 → 中止，不产生执行副作用

4. **连续执行剩余链路**
   - 前置动作: 把第 3 步确认的执行约定写入 `$work/status.yaml` 的 `current.next`（执行 `sh $root/harness/script/work-status.sh $work/status.yaml set next "auto: <结束点与关键约定>"`）
   - 每个环节: 读取并严格执行对应 `harness/cmd/` 命令文件（准入、脚本调用、自动提交、安全禁令全部适用），按第 3 步授权完成该环节常规确认关口，不逐环节等待用户审阅
   - 环节衔接: 上一环节通过后置完成检验并回写 status.yaml 后进入下一环节；仓库未就绪时按 `code` 的仓库准入转 `repo` / `worktree`，完成后继续；push 遇 non-fast-forward 按 `push` 规则转 `fetch` / `solve` 后重试；合并冲突按 `merge` / `solve` 处理
   - 发现需求或实现偏差: 按 `fix` 修正后继续，修正内容与理由纳入最终汇报
   - 决策记录: 方案选择、跳过/降级项、冲突取舍、自动修正等写入对应产物（plan.md「决策记录」/「修订记录」、status.yaml `current.next` 或 `guidance`），并在最终汇报汇总
   - **不中断原则**: 除以下真实阻塞外不停止——
     - 必须用户本人完成的外部动作（登录 / CAPTCHA、远端权限、平台 MR 审批、环境或凭据缺失）
     - 后续环节必须的**业务/产品**决策，且无法按工程常识或本次约定判定
     - 命令文件明确禁止绕过的安全或破坏性操作（如裸 `--force`、`--no-verify`；branch-op rebase 的 `--force-with-lease` 按该工作流规则并需本次明确授权）
   - 阻塞处理: 相关任务置 `blocked`，`current.next` 写明阻塞点、已完成环节与恢复方式，按真实进度汇报后结束本轮；用户补齐后再次执行 `auto` 从断点续跑
   - 进度汇报: 每个环节结束用一句话汇报产物与状态，不等待确认

5. **结束与汇报**
   - 结束判定: 到达约定终态且约定范围内无未完成项；`tasks` 全部 done 或已列明 blocked / 后续
   - 按固定四段输出:
     1. **关键决策**: 环节 / 决策点、选定方案与理由、依据（产物 / 代码事实 / git 事实）
     2. **执行结果**: 各环节产物与状态、tasks 完成情况、commit hash、push 结果、MR 链接、merge 结果；包含 close 时补 close 结果与 wiki / guidance 处理结果
     3. **阻塞与跳过**: 中断点及原因、未执行的可选 / 按需环节、遗留待办（follow_ups）
     4. **后续建议**: 需要人工完成的外部动作、建议的测试与上线动作
   - 边界: 结论必须有 status.yaml、产物文件或 git 事实来源，禁止把计划项写成已完成

## 框架自动提交（无需用户操作）

- 各环节按被调命令自带的 `space.sh commit` 完成提交；`auto` 不新增产物文件
- 中断时对 `current.next` 的回写，若所在环节未提交，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): auto state <branch>" "$work/status.yaml"` 收口，保持空间仓库无未提交残留

## 后置完成检验

- [ ] 剩余链路已按第 1 步推导并展示给用户确认；用户确认后才开始执行
- [ ] 缺失信息已一次性补齐，未编造输入；无法补齐的项已列为阻塞并停止
- [ ] 每个环节均按对应 cmd 文件执行，准入、脚本调用与安全禁令未被放宽
- [ ] 各环节产物与 status.yaml 状态一致，tasks 无未说明的滞留
- [ ] 已完成环节未重跑；中断后再次执行可从断点续跑
- [ ] 最终汇报包含关键决策、执行结果、阻塞与跳过、后续建议四段，且均有事实来源

## 下一步建议

- 默认终态为 merged / completed：需要收尾时执行 `close`（或在下次 `auto` 时指定一并 close）
- 需要额外质量门禁时，可在下次执行时把 `testcode` / `test` / `code-review` / `release-check` 纳入链路
- 有遗留阻塞项时，补齐后再次执行 `auto` 从断点续跑
