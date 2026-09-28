---
command: commit
short: ci
triggers: 提交, 本地提交, commit
params: [提交说明（可选）]
summary: 提交工作区内各仓库的本地改动；非 git 目录先初始化再提交
---

# commit 本地提交

## 前置准入条件

- 已确定当前工作区 `$work`
- 提交前需用户确认提交说明与改动范围
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——只允许在 `$work/repo/<repo-name>/` 工作区代码仓库内执行 Git 操作

## 指令内容

1. **检查改动**
   - 动作: 遍历 `$work/repo/<repo-name>/`，执行 `git status` 汇总改动文件
2. **补初始化（若需要）**
   - 动作: 若某仓库目录不是 git 仓库，先执行 `git init`，再继续提交流程
3. **生成并确认提交说明**
   - 输入: 用户参数或结合当前 status.yaml 中 current.task 对应的任务内容
   - 动作: 按仓库 Conventional Commits 风格生成提交信息（如 `feat(scope): ...`），展示给用户确认
4. **逐仓库提交**
   - 动作: `git add -A` 后 `git commit`；不推送远端；不使用 `--no-verify` 跳过钩子，钩子失败时修复后重新提交

## 后置完成检验

- [ ] 所有有改动的仓库工作区干净（或剩余改动用户明确要求保留）
- [ ] 提交信息经用户确认

## 下一步建议

- 执行 `push` 推送到远端
