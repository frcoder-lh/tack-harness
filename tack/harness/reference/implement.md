# Implement — 按任务清单构建

根据开发计划、技术设计与任务清单进行编码实现的方法论（被 `/tack code` 引用）。命令的准入准出、仓库准入判定、状态回写与暂停时机以 `harness/cmd/dev/code.md` 为唯一权威，本文件只讲实现纪律。

## 前置条件

- 已执行完 plan，`space/<workspace>/status.yaml` 的 `tasks` 列表非空且本批任务依赖已就绪
- 涉及仓库已接入、worktree 已就绪——由 code 命令的仓库准入判定负责；缺失时转 `create-repo` / `worktree`，不在本方法论内处理

## 边界

- 所有代码修改只能在 `space/<workspace>/repo/<repo-name>/`（git worktree）内进行，禁止直接修改 `repo/` 主仓库（只读基准）；Git 操作边界统一遵守 `harness/rule/git-boundary.md`
- 编码过程不代为提交：代码提交由 `commit` 命令执行——自动生成提交信息后直接提交，无需用户二次确认

## 过程

1. 读取当前的开发计划（`space/<workspace>/plan.md`）、技术评审文档（`space/<workspace>/tech-design.md`，如有）和任务清单（`space/<workspace>/status.yaml` 的 `tasks` 列表）
2. 按 deps 拓扑顺序实现任务：无依赖的任务可并行，有依赖的严格串行
3. 在预约定的接缝处使用 TDD 方法（参考 `reference/tdd.md`）
4. 定期进行类型检查和测试；仓库模式下任务 done 以本地构建/相关测试通过为准
5. 任务完成后用代码审查流程自查（参考 `reference/code-review.md`）
6. 已有类似逻辑优先复用或严格模仿其模式，不另造风格

## 开发原则

- 垂直切片：每个任务都是端到端可验收的最小功能单元
- 测试优先：先写测试，再写实现
- 不做额外工作：只实现任务清单与 plan 决策记录中描述的内容；清单外的方案选择按工程最优解实现并记录（规则见 code 命令）
- 连续开发：不逐任务停顿，暂停/审核时机以 code 命令为准（受阻、业务决策不明、模块里程碑）
