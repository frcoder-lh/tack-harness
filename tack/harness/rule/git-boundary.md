# Git 边界规则

## 空间根仓库（tack 空间）

- 空间根仓库 `$root` 的提交由框架脚本 `harness/script/space.sh commit` 自动完成；调用方必须传入本次任务的文件清单，脚本只暂存清单范围并在提交前校验暂存区不含清单外文件。
- 空间登记写入（`project.sh`）与空间提交在同一空间级锁（`harness/script/space-lock.sh`）内串行执行，并发命令不会丢失登记更新、不会出现 Git index 冲突，也不会把其它工作区的改动混入本次提交。
- **禁止**直接对 `$root` 执行 `git add / commit / push / merge` 等操作。
- 自动提交前会经 `scan-secrets.sh --changed` 对本次全部变更文件做凭据扫描。

## 代码仓库（业务代码）

- 代码仓库的日常操作（查改、提交、推送、合并）**只允许**在 `$work/repo/<repo-name>/` 的 git worktree 内进行。
- 主仓库 `$root/repo/` 只作只读基准：接入（scan/link/clone）与远端同步（fetch）只经 `harness/script/repo.sh` 执行（`repo` 命令触发），不在其中执行用户 Git 操作。
- worktree 的创建与移除只能经 `harness/script/git-worktree-helper.sh` 完成。
- 代码仓库的提交统一由 `commit` 命令经 `git-commit-helper.sh` 执行（自动生成提交信息后直接提交，无需二次确认）；推送统一由 `push` 命令经 `git-push-helper.sh` 执行（脚本拒绝任何 force 参数）；框架自动提交只处理空间根仓库，不代为提交代码，两类提交不合并为一次。

## 安全禁令

- **禁止 force push**：不改写远端历史，推送始终保持 fast-forward。
- **禁止 `--no-verify` / `--no-hooks`**：不得跳过 Git 钩子；钩子失败时修复问题后重新提交。
- **禁止 `reset --hard` 等破坏性操作**：不丢弃工作区既有改动或改写历史。

## 引用方式

- git 组命令（commit / fetch / merge / push / solve / worktree）在「前置准入条件」中引用本文件。
- 各命令的「框架自动提交」边界行可补充特有说明，但必须以「遵守 `harness/rule/git-boundary.md`」开头。
- 分支命名与提交信息约定统一见 `git-standards.md`；新建/重命名工作区、补建 worktree、本地提交、合并等需要分支的环节按其约定加载。
