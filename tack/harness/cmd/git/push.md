---
command: push
short: ps
triggers: 推送, 远程推送, push, push remote
params: 无
summary: 推送工作区提交到远端；未关联远端时先引导关联
---

# push 远程推送

## 前置准入条件

- 已确定当前工作区 `$work`
- 各仓库已有本地提交
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——只允许在 `$work/repo/<repo-name>/` 工作区代码仓库内执行 Git 操作

## 指令内容

1. **检查远端关联**
   - 动作: 逐仓库执行 `git remote -v`；若仓库未关联任何远端，**停止推送**并提示用户先创建远端仓库后执行 `git remote add origin <url>`，关联后再重新执行本命令
2. **推送**
   - 动作: 当前分支无上游时使用 `git push -u origin <branch>`（首次推送）；已有上游直接 `git push`；多仓库逐个推送
3. **回填协作信息**
   - 动作: 若平台返回创建 MR/PR 的链接，记录到 `$work/status.yaml` 的 `mr_url`；禁止 force push

## 后置完成检验

- [ ] 每个仓库本地提交均已推送（未关联远端的仓库已给出明确指引）
- [ ] 首次推送的分支已建立上游跟踪
- [ ] mr_url 已在有返回值时回填

## 下一步建议

- 需要合入主干时执行 `merge`；完成后执行 `close` 关闭工作区
