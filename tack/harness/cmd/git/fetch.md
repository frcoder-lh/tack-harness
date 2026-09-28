---
command: fetch
short: f
triggers: 拉取, 拉代码, fetch
params: 无
summary: 拉取工作区内各仓库的最新远端代码
---

# fetch 拉取最新代码

## 前置准入条件

- 已确定当前工作区 `$work`
- `$work/repo/` 下存在至少一个 git 仓库
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——只允许在 `$work/repo/<repo-name>/` 工作区代码仓库内执行 Git 操作

## 指令内容

1. **逐仓库拉取**
   - 动作: 遍历 `$work/repo/<repo-name>/`，对每个仓库执行 `git fetch --all --prune`
2. **展示差异**
   - 动作: 对比当前分支与上游，展示 ahead/behind 提交数与远端新增分支；只 fetch 不 merge，不改动工作区内容

## 后置完成检验

- [ ] 每个仓库 fetch 成功（失败的仓库与原因已列出）
- [ ] 用户清楚本地分支与远端的差异

## 下一步建议

- 需要同步远端改动时执行 `merge`
