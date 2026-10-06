---
command: solve
short: s
triggers: 冲突, 解决冲突, solve, conflict, resolve conflict
params: 无
summary: 引导式解决工作区内各仓库的合并/变基冲突
---

# solve 解决冲突

## 前置准入条件

- 存在处于冲突状态的合并或变基（`git status` 可见 unmerged paths）
- 冲突解决后必须由用户确认，AI 不擅自丢弃任何一方代码
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——只允许在 `$work/repo/<repo-name>/` 工作区代码仓库内执行 Git 操作

## 指令内容

1. **定位冲突**
   - 动作: 逐仓库执行 `git status` 与 `git diff --name-only --diff-filter=U`，列出全部冲突文件与冲突类型（modify/delete 等）
2. **逐文件分析与解决**
   - 输入: 用户对每个冲突点的取舍意见
   - 动作: 展示双方差异与上下文，结合代码意图给出解决建议；按用户决定编辑文件，删除冲突标记；modify/delete 冲突需用户明确选择保留还是删除
3. **验证**
   - 动作: `git add` 已解决文件；运行构建与相关测试
4. **继续中断的流程**
   - 动作: merge 冲突执行 `git merge --continue`（或按用户决定 abort）；rebase 冲突执行 `git rebase --continue`；禁止使用强制操作绕过冲突

## 后置完成检验

- [ ] `git status` 不再存在 unmerged paths
- [ ] 冲突文件无残留冲突标记，构建与测试通过
- [ ] 用户确认解决结果符合双方意图

## 下一步建议

- 继续 `merge` / rebase 流程，随后执行 `push`
