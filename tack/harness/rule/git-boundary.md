# Git 边界规则

## 空间根仓库（tack 空间）

- 空间根仓库 `$root` 的提交由框架脚本 `harness/script/space.sh commit` 自动完成。
- **禁止**直接对 `$root` 执行 `git add / commit / push / merge` 等操作。
- 自动提交前会经过 `scan-secrets.sh` 门禁扫描。

## 代码仓库（业务代码）

- 代码仓库的操作**只允许**在 `$work/repo/<repo-name>/` 的 git worktree 内进行。
- worktree 的创建与移除只能经 `harness/script/git-worktree-helper.sh` 完成。

## 引用方式

- git 组命令（commit / fetch / merge / push / solve / worktree）在「前置准入条件」中引用本文件。
- 各命令的「框架自动提交」边界行可补充特有说明，但必须以「遵守 `harness/rule/git-boundary.md`」开头。
