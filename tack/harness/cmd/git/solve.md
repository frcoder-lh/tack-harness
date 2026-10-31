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

按 `harness/rule/execution-efficiency.md` 一次采集冲突列表与双方相关片段，按共同根因分组处理；已确定的取舍复用到同类冲突，业务歧义集中询问。解决后统一执行相关验证与状态检查，失败时只补读失败证据。

1. **定位冲突**
   - 动作: 逐仓库执行 `sh $root/harness/script/git-facts.sh status "$work/repo/<repo-name>"`（取 `operation` / `conflicts`）与 `sh $root/harness/script/git-facts.sh conflicts "$work/repo/<repo-name>"`（列出未解决文件，退出码 10 表示存在冲突），据此列出全部冲突文件与冲突类型（modify/delete 等）
2. **逐文件分析与解决**
   - 输入: 用户对每个冲突点的取舍意见
   - 动作: 展示双方差异与上下文，结合代码意图给出解决建议；按用户决定编辑文件，删除冲突标记；modify/delete 冲突需用户明确选择保留还是删除
3. **验证**
   - 动作: `git add` 已解决文件；运行构建与相关测试
4. **继续中断的流程**
   - 动作: 重新采集 `git-facts.sh status` 的 operation；本命令统一负责继续。branch-op 工作区执行 `sh $root/harness/script/branch-op.sh continue $root space/<workspace> <repo> <merge或rebase>`；其他工作区按实际 operation 执行 `git merge --continue` 或 `git rebase --continue`。出现下一轮冲突时回到第 1 步，operation 为 none 时返回调用方进入后续推送；用户选择 abort 时报告已中止，调用方保留非完成态。禁止使用强制操作绕过冲突。

## 后置完成检验

- [ ] `git-facts.sh conflicts` 返回退出码 0（不再存在 unmerged paths）
- [ ] 冲突文件无残留冲突标记，构建与测试通过
- [ ] 用户确认解决结果符合双方意图

## 下一步建议

- 继续 `merge` / rebase 流程，随后执行 `push`
