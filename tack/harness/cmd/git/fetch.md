---
command: fetch
short: f
triggers: 拉取, 拉代码, fetch
params: 无
summary: 拉取各仓库远端最新代码并同步到本地分支（缺失上游自动关联）
---

# fetch 拉取并同步最新代码

## 前置准入条件

- 已确定当前工作区 `$work`
- `$work/repo/` 下存在至少一个 git 仓库
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——只允许在 `$work/repo/<repo-name>/` 工作区代码仓库内执行 Git 操作

## 指令内容

1. **逐仓库同步远端**
   - 动作: 遍历 `$work/repo/<repo-name>/`，对每个仓库执行 `sh $root/harness/script/git-fetch-helper.sh sync "$work/repo/<repo-name>"`
   - 脚本职责（每仓库内顺序执行）：
     - `git fetch --all --prune` 拉取全部远端引用并清理已删除分支
     - 检查当前分支上游跟踪：缺失时自动 `git branch --set-upstream-to=origin/<同当前分支名>`；`origin/<同当前分支名>` 不存在则停止该仓库同步，列出远端候选分支请用户手动设置上游
     - `git pull` 把远端同当前分支最新代码合并到本地
     - 输出 `git status -sb` 汇报 ahead/behind
2. **冲突处理**
   - 动作: `git pull` 产生冲突立即停止自动处理，转 `solve` 命令；不做静默取舍
3. **结果汇总**
   - 动作: 汇总各仓库结果（成功 / 跳过 detached HEAD / 冲突转 solve / 上游缺失待手动设置），失败仓库与原因逐条列出

## 后置完成检验

- [ ] 每个仓库 fetch 与 pull 结果明确（成功 / 跳过 detached HEAD / 冲突转 solve / 上游缺失待手动设置）
- [ ] 上游关联缺失的仓库已自动修复（origin 同名分支存在时）或已提示用户手动设置
- [ ] 成功同步的仓库本地分支已与远端同名分支对齐（behind=0；用户本地未推送的提交造成 ahead>0 不视为同步失败）

## 下一步建议

- 本地有新提交时执行 `commit`；推送远端执行 `push`；合入主干执行 `merge`
