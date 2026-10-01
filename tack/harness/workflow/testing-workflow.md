---
workflow: testing
short: tst
triggers: 测试工作流, 补测试, 测试任务, testing
summary: 测试计划 → 单测驱动的需求-代码一致性审查与缺陷发现（testcode）→ 系统测试（test，端到端功能验证）→ 回归验证的测试状态机
---

# testing 测试工作流

> 以测试为目的时的独立工作流：`testcode` / `test` / `run` 在 development 中只是**用户按需触发的命令**（非必经环节），当用户意图本身就是"测试/补测试/回归"时，按本工作流的状态机推进。
> 命令准入准出以 `harness/cmd/` 文件为准。

## 适用场景

- 为已有实现补单元测试、冲覆盖率 → `testcode`
- 验证完整系统功能是否符合预期（端到端、集成、E2E）→ `test`
- 需求开发中用户主动要求做测试（development 下随时可切入，完成后回主链路，未触发不影响提交合并）
- 修复后回归验证
- 边界：写功能代码本身走 development；定位并修缺陷走 bugfix

## 两类测试的区分

| 维度 | `testcode`（单元测试） | `test`（系统测试） |
|------|------------------------|---------------------|
| 目标 | 新增/改动代码覆盖率 ≥ 90% | 完整系统功能符合预期 |
| 产物 | 测试代码（落 `$work/repo/`） | `$work/test.md` 方案 + 可选 `run/` 脚本 |
| 脚本 | 仓库内测试框架 | `$work/run/` 下脚本，敏感数据落 `run/local/` |
| 触发词 | 单测 / 单元测试 / testcode | 测试 / 系统测试 / 集成测试 / test |

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
| 2 | 需求-代码一致性审查 + 单元测试 | `testcode` | 审查发现清单、测试代码、缺陷修复 | testing |
| 3 | 循环暴露问题与修代码 | `testcode` | 覆盖率结果（前后对比）、缺陷修复记录 | testing → verifying |
| 4 | 系统测试方案 | `test` | `$work/test.md`（可落地可执行方案）；需脚本时初始化 `run/` | testing / progress.test |
| 5 | 执行测试脚本 | `run` | 加载 `run/run.md` 执行；敏感数据落 `run/local/` | testing / progress.run |
| 6 | 回归验证 | 构建/全量测试命令 | 全量测试通过、无稳定性问题 | verifying |
| 7 | 提交 | `commit` `push` | 测试提交 | completed |

## 各环节说明

1. **范围圈定**：从 status.yaml 的 `tasks` 列表与代码 diff 圈定本任务新增/修改逻辑；识别核心分支、边界条件、异常路径
2. **需求-代码一致性审查**：逐条核对 spec/plan 验收标准与代码实现，识别未实现、实现偏差、遗漏边界；基于审查发现设计**能暴露问题的用例**，断言对准需求预期而非代码当前行为
3. **测试编写与缺陷修复**：按需参考 `reference/tdd.md`；测试代码只能落在 `$work/repo/`；用例失败即确认缺陷，**修代码而非改测试适配**；没有测试框架时先与用户确认引入方式，不擅自加重型依赖
4. **覆盖率准出**：重复「审查 → 设计暴露问题的用例 → 运行 → 修代码 → 回归」直到新增/改动代码覆盖率 ≥ 90%；不可测代码需向用户说明原因；不为覆盖率写无效断言
5. **质量审核**：用户审核断言有效性（对准需求预期、非为覆盖率写无效断言）与缺陷修复是否到位；按需参考 `reference/code-review.md`

## 状态回写要求

- 环节开始前更新 `current.stage: testcode`、`current.task`（被测任务 ID）、`current.next`
- 覆盖率达标且回归通过后：`progress.testcode: true`；从 development 按需切入的，status 回到所属主工作流状态（commit/push 是否执行由用户决定，测试不构成前置门禁）
- 独立测试任务完成并提交后可置 completed；受阻置 blocked 并写明缺口
