---
command: merge
short: m
triggers: 合并, merge
params: [目标分支（默认主干）]
summary: 将目标分支合并进当前工作区分支（或在平台上发起合并）
---

# merge 合并分支

## 前置准入条件

- 已确定当前工作区 `$work`
- 当前分支改动已 `commit`；建议先执行 `fetch` 获取最新远端
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——只允许在 `$work/repo/<repo-name>/` 工作区代码仓库内执行 Git 操作

## 指令内容

1. **确认合并方向与目标分支**
   - 输入: 目标分支参数（默认仓库主干 master/main，由用户确认）
   - 动作: 在每个涉及的仓库确认当前分支名与目标分支

2. **变更审查（审查必选，禁止跳过）**
   - 动作:
     - 读取 `$root/harness/agents/code-reviewer.md`，按其委派方式发起审查；审查方法论遵循 `harness/reference/code-review.md` 的双轴（Spec/Standards）
     - 小改动可委派单一 reviewer 实例；跨模块/多仓库大改动并行委派 3 个实例（规范符合度 / bug 与正确性 / 约定与安全），审查范围为 `git diff <目标分支>...HEAD`
     - 规范来源：`$work/spec.md`、`plan.md`、`tech-design.md`；标准来源：`harness/rule/coding-standards.md`、`harness/rule/security.md`
     - 汇总各实例结论，按 Critical / Warning / Suggestion 分组呈现（每条含 `文件:行号` 证据与依据），审查者只读不改
   - 边界: 只审查本次变更新引入的问题；历史问题单列提示，不阻断合并

3. **审查结论三选一分流（由用户决定，禁止 AI 自行放行）**
   - 无 Critical/Warning（仅 Suggestion 或无问题）：一句话说明后直接进入第 4 步
   - 存在 Critical/Warning 时，向用户呈现清单并要求三选一：
     - **立即修复**：中止本次合并，转 `fix`（或 `code`）修复，修复后重新执行本命令第 2 步复审
     - **记录后续**：逐条登记到 `$work/status.yaml`（如 `follow_ups` 列表：问题、位置、来源审查、计划处理时间）或平台 issue，用户确认后继续合并
     - **维持现状**：用户明确确认承担风险，在 `$work/status.yaml` 记录确认人与事项后继续合并
   - 动作: 把分流结果回写 `$work/status.yaml`（`current.next` 注明选择；修复/记录/确认的落盘位置）

4. **执行合并**
   - 动作: 优先引导在代码平台发起 MR/PR 合并（以平台审查结论为准，第 2 步自查作为提交前门禁）；需要本地合并时逐仓库执行 `git merge <目标分支>`

5. **冲突处理**
   - 动作: 出现冲突立即停止自动处理，转交 `solve` 命令；不做静默取舍

6. **合并后同步**
   - 动作: 本地合并成功后提示 `push`；平台合并后回填 MR 链接到 `$work/status.yaml`（mr_url），并置 `progress.merged: true`；冲突解决可转入 merge-conflict 工作流
   - 合并 ≠ 上线: 用户需要在 PPE/PROD 等环境继续验证或上线时，把各环境的上线计划与泳道/版本事实登记到 `$work/status.yaml` 的 `deploy` 区块（结构见 `harness/template/work-status.yaml`）；BOE 验证泳道不再使用时将对应条目置 `recycled`

## 后置完成检验

- [ ] 第 2 步审查已执行，问题清单按级别呈现且均有证据
- [ ] 存在 Critical/Warning 时三选一分流有用户明确选择，结果已回写 status.yaml（修复转 fix / 后续项已登记 / 风险有人确认）
- [ ] 每个仓库合并结果明确（成功 / 冲突转 solve / 用户选择跳过）
- [ ] 合并后构建通过；本次按需执行过的测试（testcode/test/run）结果均通过——测试非必经环节，未执行不阻塞合并
- [ ] `$work/status.yaml` 的 mr_url 已更新（平台合并时）
- [ ] `deploy` 区块已按需登记上线计划或泳道回收（无部署需求时向用户说明并跳过）

## 下一步建议

- 上线前需要检查清单时执行 `release-check`（数据库/配置/接口权限/中间件等检查项）
- 合并并上线完成后执行 `close` 关闭工作区
