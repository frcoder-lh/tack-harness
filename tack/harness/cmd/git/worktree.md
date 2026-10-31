---
command: worktree
short: wt
triggers: 工作树, worktree
params: [仓库名]
summary: 为当前工作区的指定仓库按需补建 git worktree（新建工作区只创建 status.yaml 与 context.md，需要修改代码时才创建 worktree）
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
   - 边界: 分支不存在由脚本基于默认分支新建；分支命名与提交信息遵循 `harness/rule/git-standards.md`
2. **创建并登记 worktree**
   - 动作: 执行 `sh $root/harness/script/command-batch.sh attach $root <work_dir> <branch> <repo-name>`；脚本持锁调用 worktree helper、验证实际分支、合并 services 并登记新建分支，成功返回 `ATTACHED=<repo>`
   - 恢复: 中断后重跑同一调用；新建分支标记保留到登记完成，已有 worktree 必须仍在目标分支

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): attach worktree <repo-name>" "$root/tack.yaml" "$work/status.yaml"`，把 services 登记变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；仅提交 `tack.yaml` / status.yaml 登记变更；worktree 创建本身由框架脚本完成，代码仓库不产生提交

## 后置完成检验

- [ ] `git -C $work/repo/<repo-name> status` 正常且位于目标分支
- [ ] `tack.yaml` work 条目与工作区 status.yaml 的 services 已更新

## 下一步建议

- 在新 worktree 中执行 `code` 继续开发
