---
workflow: bugfix
short: bug
triggers: 改bug工作流, 修bug, 修缺陷, 排障, bugfix, fix bug, fix defect, troubleshoot, bugfix workflow
summary: 复现 → 诊断定位 → 修复 → 验证 → 提交的缺陷修复状态机
---

# bugfix 改 bug 工作流

> 缺陷修复与线上问题排查流程。AGENTS 识别到「有个 bug/报错/线上问题」意图时加载本工作流。
> 命令准入准出以 `harness/cmd/` 文件为准。

## 适用场景

- 修复明确的缺陷、报错、异常行为
- 线上问题排查与定位
- 边界：无问题的纯新功能走 development；只补测试走 testing

## 状态流转

```
initialized → reproducing → diagnosing → fixing → verifying → completed
                     \           \          \         \
                      └──────── blocked（无法复现/缺信息/等依赖）
```

| 状态 | 含义 | 进入条件 |
|------|------|----------|
| initialized | 缺陷已登记（现象、环境、入口） | 用户描述问题并确定工作区 |
| reproducing | 稳定复现中 | 明确复现步骤或构造失败用例 |
| diagnosing | 根因定位中 | 已能复现，开始查代码/日志/数据 |
| fixing | 代码修复中 | 根因已确认并经用户认可 |
| verifying | 修复验证中（回归 + 相关链路） | 修复代码完成 |
| completed | 修复交付 | 验证通过、用户确认、提交推送 |
| blocked | 受阻 | 无法复现/根因不确定/等日志数据 |

## 各环节与命令映射

| # | 环节 | 命令/动作 | 产物 | 完成后状态 |
|---|------|-----------|------|------------|
| 1 | 登记现象与入口 | 工作区 input.md 记录现象、日志、环境；必要时 `work` 建修复分支 | 问题描述 | initialized |
| 2 | 稳定复现 | 构造复现步骤/失败测试（可引用 testcode） | 复现用例 | reproducing |
| 3 | 诊断定位 | 按 `reference/diagnosing-bugs.md` 科学排查（假设→证据→结论） | 根因结论（可沉淀 wiki） | diagnosing |
| 3.5 | 缺陷溯源 | `git-bug-trace.sh` 追溯引入缺陷的 commit、时间、对应需求与合并到主干的 MR | `status.yaml` 的 `bug_origin` 区块 | diagnosing |
| 4 | 修复 | `code`（加载 rule；改动仅限 worktree） | 修复代码 | fixing |
| 5 | 验证 | `testcode` / 复现用例回归 / 相关链路回归 | 测试与回归结果 | verifying |
| 6 | 提交推送 | `commit` `push`（必要时 `merge`） | 提交记录 | completed |
| — | 经验沉淀 | `record`（根因与排查路径沉淀 wiki/rule） | wiki 条目 | 完成后 |

## 各环节说明

1. **先复现后动手**：无法稳定复现的问题先补信息（日志、数据、环境），不凭猜测改代码；受阻置 blocked
2. **基于证据诊断**：按需参考 `reference/diagnosing-bugs.md`——提出假设、用运行/日志/代码证据证实或排除，结论写入工作区文档；可复用的链路结论经人工审阅后分文件沉淀到 `$root/wiki/`
3. **缺陷溯源（根因确认后必做）**：定位到缺陷代码行后，调用 `harness/script/git-bug-trace.sh <repo> <file> <line> [end-line] [target-branch]` 追溯缺陷来源，输出含：引入 commit、引入时间、作者、对应需求/工单 ID（从 commit message 提取）、commit 链接、把该 commit 带入主干的合并提交与 MR 链接。将结果写入 `$work/status.yaml` 的 `bug_origin` 区块。溯源价值：①确认缺陷是需求引入还是历史遗留；②评估同需求关联代码是否有同类问题；③MR 链接可回溯当时的审查结论与关联改动。若 `--ancestry-path` 未找到合并提交（被 rebase/cherry-pick 改写），在 `note` 注明并退而记录引入 commit 本身
4. **最小修复**：根因经用户认可后再改；只改与缺陷相关代码，不顺手重构；遵守 `harness/rule/`
5. **防回归**：为缺陷补一个能复现旧问题的测试，修复后该测试转绿；跑相关链路回归
6. **提交信息**：说清现象、根因、修复方式（如 `fix(scope): ...`）

## 状态回写要求

- 每环节经 `work-status.sh` 回写：`status` 按状态流转表更新（reproducing / diagnosing / fixing / verifying）、`current.stage`（reproduce / diagnose / fix / verify）、`current.task`、`current.next`
- 假设未证实不改代码；根因结论与修复方案需用户确认后才进入 fixing
- **缺陷溯源结果写入 `bug_origin` 区块**：`git-bug-trace.sh` 的输出（commit/author/date/commit_url 等标签）按下表字段映射回填到 `$work/status.yaml` 的 `bug_origin`：`introduced_commit` / `introduced_commit_url` / `introduced_at` / `introduced_by` / `requirement` / `merge_commit` / `merge_subject` / `merge_url` / `target_branch` / `note`（结构见 `harness/template/work-status.yaml`）
- 验证通过、用户确认并提交推送后置 completed；受阻置 blocked；完成后若在用户引导下获得可复用排查经验，按核心约束用 `record` 沉淀
