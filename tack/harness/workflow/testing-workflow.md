---
workflow: testing
short: test
triggers: 测试工作流, 补测试, 测试任务, testing
summary: 测试计划 → 单测循环 → 覆盖率准出 → 回归验证的测试状态机
---

# testing 测试工作流

> 独立的测试/补测试流程，也在 development 工作流的 testcode 环节被引用。
> 按状态机推进；命令准入准出以 `harness/cmd/` 文件为准。

## 适用场景

- 为已有实现补单元测试、冲覆盖率
- 需求开发到测试环节（承接 development 的 code 之后）
- 修复后回归验证
- 边界：写功能代码本身走 development；定位并修缺陷走 bugfix

## 状态流转

```
initialized → test-planning → testing → verifying → completed
                       \          \          \
                        └──────── blocked（测试环境/依赖不可用、需求不明）
```

| 状态 | 含义 | 进入条件 |
|------|------|----------|
| initialized | 明确被测对象与任务 | 指定任务 ID / 确定工作区与范围 |
| test-planning | 制定测试计划 | 读取 status.yaml 的 tasks 列表、代码 diff 与 test-plan.md |
| testing | 编写与运行测试的循环中 | 开始执行 `testcode` |
| verifying | 覆盖率达标后的回归验证 | 新增/改动代码覆盖率 ≥ 90% |
| completed | 测试交付完成 | 用户审核测试质量并确认 |
| blocked | 受阻 | 无测试框架/环境不可用/需求不明 |

## 各环节与命令映射

| # | 环节 | 命令 | 产物 | 完成后状态/进度 |
|---|------|------|------|----------------|
| 1 | 确定测试范围与计划 | （按 test-plan.md 人工/AI 协作出测试计划，可记入 plan.md） | 测试范围、用例清单 | test-planning |
| 2 | 生成单元测试 | `testcode` | 测试代码 | testing |
| 3 | 循环检测与补缺口 | `testcode` | 覆盖率结果（前后对比） | testing → verifying |
| 4 | 回归验证 | 构建/全量测试命令 | 全量测试通过、无稳定性问题 | verifying |
| 5 | 提交 | `commit` `push` | 测试提交 | completed |

## 各环节说明

1. **范围圈定**：从 status.yaml 的 `tasks` 列表与代码 diff 圈定本任务新增/修改逻辑；识别核心分支、边界条件、异常路径
2. **测试编写**：按需参考 `reference/tdd.md`；测试代码只能落在 `$work/repo/`；没有测试框架时先与用户确认引入方式，不擅自加重型依赖
3. **覆盖率准出**：重复「生成 → 运行 → 分析缺口」直到新增/改动代码覆盖率 ≥ 90%；不可测代码需向用户说明原因
4. **质量审核**：用户审核断言有效性（非为覆盖率写无效断言）；按需参考 `reference/code-review.md`

## 状态回写要求

- 环节开始前更新 `current.stage: testcode`、`current.task`（被测任务 ID）、`current.next`
- 覆盖率达标且回归通过后：`progress.testcode: true`，status 回到所属主工作流状态（development 下继续 reviewing 前的 commit/push）
- 独立测试任务完成并提交后可置 completed；受阻置 blocked 并写明缺口
