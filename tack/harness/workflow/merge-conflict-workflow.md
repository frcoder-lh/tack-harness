---
workflow: merge-conflict
short: mc
triggers: 冲突工作流, 合并冲突, merge-conflict, merge conflict, conflict workflow
summary: fetch → merge → solve → 验证 → push 的分支合并与冲突解决状态机（「解决冲突」直接走 solve 命令）
---

# merge-conflict 合并/冲突工作流

> 分支合并与冲突解决流程。可由 development 工作流的 merge 环节转入，也可在用户直接要求合并/解冲突时加载。
> 命令准入准出以 `harness/cmd/` 文件为准。

## 适用场景

- 把主干或目标分支合入当前工作区分支、或在平台发起合并
- 合并/变基出现冲突，需要引导式解决
- 边界：日常功能开发走 development；本工作流不负责功能编码

## 状态流转

```
initialized → fetching → merging → resolving → verifying → pushing → completed
                    \        \          \           \          \
                     └──────── blocked（远端不可达/取舍需业务确认/验证失败）
```

| 状态 | 含义 | 进入条件 |
|------|------|----------|
| initialized | 明确合并方向与目标分支 | 确定工作区、源/目标分支 |
| fetching | 拉取最新远端 | 执行 `fetch` |
| merging | 执行合并 | 开始 `merge` |
| resolving | 逐文件解决冲突 | 出现 unmerged paths，执行 `solve` |
| verifying | 冲突解决后的构建与测试 | 冲突标记清除、git add 完成 |
| pushing | 推送合并结果 | 验证通过 |
| completed | 合并交付 | push 完成 / 平台 MR 合并完成 |
| blocked | 受阻 | 需业务取舍、远端不可达、构建失败 |

## 各环节与命令映射

| # | 环节 | 命令 | 动作 | 完成后状态 |
|---|------|------|------|------------|
| 1 | 确认合并方向 | — | 逐仓库确认当前分支与目标分支（默认 master/main，用户确认） | initialized |
| 2 | 拉取最新 | `fetch` | `git fetch --all --prune`，查看 ahead/behind | fetching |
| 3 | 合并 | `merge` | 优先平台 MR/PR；本地 `git merge <目标>` | merging |
| 4 | 解决冲突 | `solve` | 列冲突文件→展示双方差异→按用户决定修改→add | resolving |
| 5 | 验证 | 构建/测试命令 | 构建通过、相关测试通过 | verifying |
| 6 | 继续/推送 | `git merge --continue`（或 rebase --continue）→ `push` | 回填 mr_url | pushing → completed |

## 各环节说明

1. **只做引导不做静默取舍**：每个冲突点展示双方差异与代码意图，解决建议由用户拍板；modify/delete 冲突需明确保留或删除
2. **不绕过冲突**：禁止强制操作、禁止 `--no-verify`；无法达成一致时置 blocked 保留冲突现场
3. **验证后继续**：冲突全部解决后构建与相关测试必须通过，再继续中断的 merge/rebase
4. **多仓库逐一处理**：每个涉及仓库独立走完 fetch→merge→solve→push，并在最终汇总各仓库结果
5. 可选参考：`reference/handoff.md`（冲突处理跨会话时交接现场）

## 状态回写要求

- 环节更新 `current.stage: merge`、`current.task`（冲突文件清单）、`current.next`
- 平台合并成功后回填工作区 status.yaml 的 `mr_url`、置 `progress.merged: true`
- 合并完成回到 development 工作流时由 `close` 收尾；独立执行则置 completed
