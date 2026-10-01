---
command: worktree
short: wt
triggers: 工作树, worktree
params: [仓库名]
summary: 为当前工作区的指定仓库补建 git worktree
---

# worktree 新建 worktree

## 前置准入条件

- 已确定当前工作区 `$work`
- 参数指定的仓库在 `$root/repo/<repo-name>` 已存在且是有效 git 仓库
- 该仓库在当前工作区尚无 worktree
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——worktree 的创建/移除是框架管理行为，只能经 `harness/script/git-worktree-helper.sh` 完成

## 指令内容

1. **确认目标仓库与分支**
   - 输入: 仓库名参数；分支默认取工作区分支（`$work/status.yaml` 的 `branch`，不带日期前缀）；工作区目录名取 `$work/status.yaml` 的 `work_dir`（即 `basename "$work"`）
2. **创建 worktree**
   - 动作: 执行 `sh $root/harness/script/git-worktree-helper.sh create $root <work_dir> <branch> <repo-name>`，创建到 `$work/repo/<repo-name>`；分支不存在时自动基于默认分支新建
3. **更新登记**
   - 动作: 将仓库名补入 AGENTS.md 项目信息区块中该 work 条目的 services（直接编辑 YAML），并同步 `$work/status.yaml` 的 services

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): attach worktree <repo-name>"`，把 services 登记变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；仅提交 AGENTS.md / status.yaml 登记变更；worktree 创建本身由框架脚本完成，代码仓库不产生提交

## 后置完成检验

- [ ] `git -C $work/repo/<repo-name> status` 正常且位于目标分支
- [ ] AGENTS.md work 条目与工作区 status.yaml 的 services 已更新

## 下一步建议

- 在新 worktree 中执行 `code` 继续开发
