---
command: fix
short: fx
triggers: 修正, 需求修正, 修改需求, 修正代码, fix
params: [修正内容（自然语言描述）]
summary: 后续环节发现需求不明确或实现不正确时进行修正——需求修正走 spec→plan→代码，代码修正走代码→同步文档，任务状态同步回 status.yaml
---

# fix 需求/实现修正

> 在 spec/plan/code/testcode 等后续环节中，发现**需求不明确、理解偏差或实现不正确**时使用。
> 根据用户指出的修正对象选择修正路径，保证「需求文档、计划、代码」三者始终一致。

## 前置准入条件

- 已确定当前工作区 `$work`
- 已有 spec.md（通常也有 plan.md 与部分代码）
- 执行前重新读取 `$work/status.yaml`、spec.md、plan.md，尊重本地最新状态

## 输入源与加载策略（节约 token）

遵守 `harness/rule/context-loading.md`：相关产物（spec.md / plan.md / tech-design.md / status.yaml 的 tasks）按修正点 grep 定位相关章节再读取；wiki 与代码按修正点关键词定位后只读必要片段

## 指令内容

### 0. 判定修正类型

根据用户描述判定属于哪条路径（无法判断时先问一句）：

- **需求修正**：用户指出需求理解有误、需求变更、不明确之处需要明确 → 走路径 A
- **代码修正**：用户指出实现与需求不符、代码行为不正确 → 走路径 B

### 路径 A：需求修正（文档先行，spec → plan → 代码）

1. **回写状态**：执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage fix task 需求修正 next "修正 spec.md"`（自动刷新 updated_at）；受影响任务必要时在 tasks 中置 `blocked`（任务级状态直接编辑 YAML）
2. **修正 spec.md**：按用户修正内容更新需求规划（边界、story、验收标准等相关章节）；只改受影响部分，保留修订说明（修正点、原因、日期）
3. **修正 plan.md**：
   - 更新受影响的设计章节与「决策记录」
   - 调整模块划分与任务清单：新增/删除/修改任务，重算 deps 与并行关系
4. **同步 status.yaml 的 tasks**：直接编辑 YAML，使任务列表与 plan.md 一致；
   - 新增任务 `pending`；已 done 但受影响的任务回退为 `pending`（或新增修正任务），并在任务备注中记录原因
5. **修正代码**：对受影响的任务重新执行 code 的实现纪律（复用优先、按依赖顺序、grep 定位），使代码与修正后的文档一致
6. 用户审阅确认后恢复原环节状态

### 路径 B：代码修正（代码先行，代码 → 评估是否反向同步文档）

1. **回写状态**：执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage fix task 代码修正 next 修正代码`（自动刷新 updated_at）
2. **修正代码**：
   - grep 定位问题代码与类似正确实现；优先复用既有模式
   - 仅改动实现使行为正确；不擅自改 spec/plan
   - 相关任务置 `in_progress`，构建/测试通过后置回 `done`
3. **评估需求一致性**：代码修正后核对 spec.md / plan.md：
   - 若实现修正**未改变**需求与计划（纯粹 bug/实现偏差）：文档不动，仅记录修正说明
   - 若修正中**暴露出需求或计划需要相应调整**：告知用户差异，按路径 A 的第 2-4 步同步修正 spec.md、plan.md 与 tasks
4. 用户审阅确认后恢复原环节状态

### 共同纪律

- 修正涉及代码时只能改 `$work/repo/` 内文件，不执行破坏性 Git 操作
- 每次修正都要保持 spec.md ↔ plan.md ↔ tasks ↔ 代码 四者一致，不留偏差
- 修正记录写入 plan.md 的「修订记录」或在 status.yaml 日志体现（修正点、路径 A/B、日期）

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): fix and sync docs <branch>"`，把 spec.md / plan.md / status.yaml 的修正自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；工作区代码仓库的修正提交仍由 `commit` 命令执行（自动生成提交信息后直接提交，无需二次确认），不混为一次提交

## 后置完成检验

- [ ] 修正后的行为/需求符合用户预期，构建与相关测试通过
- [ ] 走路径 A：spec、plan、tasks、代码均已同步
- [ ] 走路径 B：代码已修正；如需文档调整已同步，否则已明确说明无需调整
- [ ] status.yaml 任务状态与实际一致；改动均在 `$work/repo/` 或工作区文档内

## 下一步建议

- 继续被中断的环节（code / testcode / review）
- 全部完成后执行 `commit`，提交说明中标注 fix 内容
