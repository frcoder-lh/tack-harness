---
workflow: branch-op
short: bop
triggers: 分支操作, branch-op, branch operation, branch ops
summary: 无需求/无分析/无测试的分支级 merge、rebase 状态机——临时分支加时间戳隔离操作后推回原分支，临时资源在 close 时清理
---

# branch-op 分支操作工作流

> 用户意图为「把 A 分支 merge 到 B 分支」「把 A 分支 rebase 到 B 分支」等纯分支搬运时加载。
> 由 `work` 命令的意图分流进入，不设独立命令入口；命令准入准出以 `harness/cmd/` 文件为准，
> 机械流程由 `harness/script/branch-op.sh` 固化。

## 适用场景

- 两个**已存在**的分支之间做集成：merge（A → B）或 rebase（A onto B，结果更新 A）
- 源/目标分支可能正被其他 worktree 检出，不能直接占用——全程只操作时间戳临时分支
- 边界：
  - 功能开发、需求驱动的改动走 development；纯缺陷修复走 bugfix
  - 「把目标合入当前开发分支并做验证交付」走 merge-conflict（含构建测试环节）
  - 本工作流不产生任何业务代码改动，搬运的都是源分支上已有提交

## 明确跳过的环节

- 不录入需求（input.md 仅留空模板）、不做代码分析 ask
- 不做 spec / plan / tech-design、不生成任务清单
- 不做 code-reviewer 审查（被搬运提交在其原工作区负责审查）
- 不做构建与测试
- 不直接检出、提交或改动原 A、B 分支

## 状态流转

```
initialized → preparing → integrating → pushing → completed
                              ↕ resolving        │
                           （冲突时 solve →      │
                             continue，仍冲突     │
                             则留在 resolving）   │
                                              close 时 cleanup（删 worktree 与两个临时分支）
```

| 状态 | 含义 | 进入条件 |
|------|------|----------|
| initialized | 已解析 op/A/B 与涉及仓库 | work 意图分流完成 |
| preparing | 建骨架、fetch、建时间戳临时分支与工作 worktree | `branch-op.sh prepare` |
| integrating | merge/rebase 执行中（无冲突即一步完成） | `branch-op.sh integrate` |
| resolving | 逐文件解决冲突 | integrate/continue 退出码 10，执行 `solve` |
| pushing | 结果推回原分支 | integrate 全部完成，执行 `branch-op.sh push` |
| completed | 结果已推回原分支 | push 成功 |
| blocked | 受阻 | 远端不可达、分支不存在、授权被拒等 |

> 临时 worktree 与两个临时分支在 completed 后仍保留，`close` 第 6 步统一清理。

## 各环节与动作映射

| # | 环节 | 执行 | 完成后状态 |
|---|------|------|------------|
| 1 | 解析意图与确认仓库 | `work` 分流：解析 op（合并→merge，变基→rebase）、A、B；逐仓库校验分支存在并由用户确认 | initialized |
| 2 | 建骨架与 prepare | `work.sh --no-worktree` 建工作区骨架 → `branch-op.sh prepare ...`（每仓库一次），解析输出的临时分支名 | preparing |
| 3 | 集成 | `branch-op.sh integrate ...`；退出码 10 → 第 4 步 | integrating |
| 4 | 解决冲突 | `solve`：展示双方差异与意图，用户拍板，禁止静默取舍 | resolving |
| 5 | 继续 | `branch-op.sh continue ...`；退出码 10 回第 4 步；用户放弃则 `abort` 后置 blocked | integrating |
| 6 | 推送 | `branch-op.sh push ...`（授权要求见下） | pushing → completed |
| 7 | 清理 | `close` 时 `branch-op.sh cleanup ...`（worktree 有改动时经用户确认方可 force） | — |

## 推送与授权纪律

1. **merge**：`B-ts` 普通推送为远端 B（`git push origin B-ts:B`）；B 在此期间被他人更新导致非 fast-forward 时，重新 fetch 后重走 prepare/integrate，禁止 force
2. **rebase**：推回 A 必然需要改写远端历史，执行前必须：
   - 向用户说明「A 的历史将被重写」并取得**当次明确授权**（一事一授，不沿用、不推定）
   - 以环境变量 `BRANCH_OP_FORCE_AUTHORIZED=1` 调 `branch-op.sh push`，脚本以 fetch 时的 `origin/A` 旧值做 `--force-with-lease` 租约
   - 租约失败说明 A 被他人更新：重新 prepare 后再 rebase，禁止放宽为裸 `--force`
3. 多仓库时逐仓库独立走完 prepare→integrate→push，最终汇总各仓库结果

## 状态回写要求

- 工作区 `status.yaml`：`workflow: branch-op`；`status` 按上表流转；`current.stage` 取 prepare/integrate/resolve/push/cleanup
- `branch_op` 区块记录每仓库的临时分支名与推送状态（结构见 `harness/template/work-status.yaml`），是续跑与 close 清理的依据
- `branches` 列表同时登记两个临时分支（`role: tmp, source: branch-op`），作为全工作流通用的分支登记簿；close 时 `branch-op.sh cleanup` 删除临时分支后，由 close 命令对这两条 tmp 条目执行 `work-status.sh branch mark <repo> <name> cleaned`
- push 成功后置 `status: completed`；本工作流不使用 progress.merged
- 用户引导/纠偏照常采集到 `guidance`（AGENTS.md 核心约束第 11 条）
