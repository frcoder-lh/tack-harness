# Implement — 按任务清单构建

根据技术设计文档或任务清单描述进行开发。

## 前置条件

只有执行完 breakdown 并生成任务清单（`work/<branch>/plan/tasks.md`）后，才能进入代码实现阶段。

## 前置检查

在开始任何代码修改前，必须：

1. **确认 `repo/` 是一个 git 仓库**
   ```
   git -C repo/<repo-name> status
   ```
   如果报错，需先执行 `/tack init-repos`。

2. **运行 git-worktree-helper.sh 创建 worktree**
   ```
   sh harness/script/git-worktree-helper.sh create <root-path> <branch> <repo-name>
   ```
   这会在 `work/<branch>/repo/` 下创建 git worktree。

3. **所有代码修改必须在 `work/<branch>/repo/` 路径下进行**

4. **禁止直接修改 `repo/` 主仓库**（只读基准库）

## 过程

1. 读取当前的技术设计文档（`work/<branch>/harness/tech-design.md`）和任务清单（`work/<branch>/plan/tasks.md`）
2. 按依赖顺序逐个实现任务
3. 在预约定的接缝处使用 TDD 方法（参考 `resources/tdd.md`）
4. 定期进行类型检查和测试
5. 每个任务完成后，使用代码审查流程（参考 `resources/code-review.md`）审查工作
6. 将工作提交到当前分支
7. 每个任务完成后暂停，等待用户审核确认后再继续下一个

## 开发原则

- 垂直切片：每个任务都是端到端可验收的最小功能单元
- 测试优先：先写测试，再写实现
- 小步前进：每个任务完成后暂停审核
- 不做额外工作：只实现任务清单中描述的内容
- **代码改动仅限 worktree**: 所有代码修改必须在 `work/<branch>/repo/` 工作区内进行，禁止修改根目录 `repo/`（只读基准库）