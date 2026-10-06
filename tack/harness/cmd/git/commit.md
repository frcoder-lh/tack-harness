---
command: commit
short: ci
triggers: 提交, 本地提交, commit, local commit
params: [提交说明（可选）]
summary: 提交工作区内各仓库的本地改动；非 git 目录先初始化再提交；提交信息自动生成后直接提交，无需用户二次确认

# commit 本地提交

## 前置准入条件

- 已确定当前工作区 `$work`
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——只允许在 `$work/repo/<repo-name>/` 工作区代码仓库内执行 Git 操作
- 用户发起本命令即视为确认提交意图；提交信息按第 3 步自动生成（用户参数优先），生成后**直接提交、不再二次确认**；仅本地提交，不推送远端

## 指令内容

1. **检查改动**
   - 动作: 遍历 `$work/repo/<repo-name>/`，执行 `git status` 汇总各仓库改动文件；无改动的仓库跳过，全部仓库均无改动时提示"无改动可提交"并结束
2. **补初始化（若需要）**
   - 动作: 若某仓库目录不是 git 仓库，先执行 `git init`，再继续提交流程
3. **生成提交说明**
   - 输入: 用户参数优先；未提供参数时结合 `git diff --staged`（暂存前可用 `git diff` / `git status`）实际改动与 status.yaml 中 current.task 对应的任务内容
   - 动作: 按仓库 Conventional Commits 风格生成提交信息（如 `feat(scope): ...`），生成后直接进入下一步提交，**不暂停等待用户确认**
4. **逐仓库提交**
   - 动作: `git add -A` 后 `git commit`；不推送远端；不使用 `--no-verify` 跳过钩子，钩子失败时修复后重新提交
5. **汇报提交结果**
   - 动作: 提交完成后逐仓库展示 commit hash、提交信息、改动文件清单（须基于 `git show --stat` / `git status` 实际结果，禁止臆测）；若用户事后对提交内容有异议，再按用户指令处理，命令本身不预留确认回环

## 后置完成检验

- [ ] 所有有改动的仓库工作区干净（或剩余改动用户明确要求保留）
- [ ] 每个提交的 hash、提交信息、改动文件清单已如实向用户展示
- [ ] 未推送远端；未使用 `--no-verify`

## 下一步建议

- 执行 `push` 推送到远端
