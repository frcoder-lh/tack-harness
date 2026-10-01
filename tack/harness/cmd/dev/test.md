---
command: test
short: t
triggers: 测试, 系统测试, 集成测试, 端到端测试, e2e, test
params: [测试描述]
summary: 按需命令（非开发必经环节，用户需要时触发）——系统测试，把用户对测试的描述转化为可落地可执行的 test.md 方案；需要脚本时落到 run/ 目录（按需初始化 run）
---

# test 系统测试（按需命令）

> **按需触发，不是 development 主链路的必经环节**：code 完成后可直接 commit/push，AI 不主动引导进入系统测试；仅当用户主动表达（如"做系统测试/集成测试/e2e"）或进入 testing 工作流时才执行，不需要任何"跳过"标记。
> 与 `testcode`（单元测试，目标代码覆盖率达标）明确区分：本命令面向**完整系统功能**，目标是验证系统端到端行为是否符合预期。
> 产物是 `$work/test.md`（可落地、可执行的测试方案）；测试脚本放在 `$work/run/`。

## 前置准入条件

- 已确定当前工作区 `$work`
- 待测系统已有实现（位于 `$work/repo/`）或可部署的环境
- 不适用：只为冲代码覆盖率、写单测 → 走 `testcode`

## 指令内容

1. **接收测试描述并确认范围**
   - 输入: 用户对本次系统测试的描述（测什么功能、在什么环境、验证什么预期）
   - 动作: 描述宽泛时先澄清边界（测哪些功能、不测哪些、用什么环境），意图明确后再继续；不得带着模糊目的直接生成方案

2. **加载上下文（节约 token）**
   - 输入源: `$work/spec.md`（验收标准）、`$work/plan.md`（模块与接口）、`$work/wiki/` 与 `$root/wiki/`（环境与接口事实，grep 定位后读命中小节）、代码事实
   - 加载纪律: 遵守 `harness/rule/context-loading.md`；环境拓扑、泳道、部署方式等静态事实查 `$root/wiki/manifest.md`「部署环境与泳道」，缺失不臆造

3. **生成 test.md（可落地、可执行方案）**
   - 动作: 复制 `harness/template/test.md` 到 `$work/test.md`，把用户描述转化为结构化测试方案：
     - 测试目标与范围（含验收标准，逐条可勾选）
     - 测试环境（地址/入口；凭据来源指向 `run/local/`，不写明文）
     - 测试用例（场景 / 前置条件 / 操作步骤 / 预期结果 / 状态）
     - 测试数据准备
     - 执行方式（手工步骤 + 自动化脚本）
   - 边界: 敏感信息（密钥、token、账号）**一律不写入 test.md**，只标注「凭据来自 `run/local/<文件>`」

4. **按需初始化 run/ 目录与脚本**
   - 判定: 若测试方案中需要运行脚本（数据准备、接口调用、自动化验证、部署等），确保 `$work/run/` 存在
   - 动作: `$work/run/` 不存在时按 `run` 命令的初始化流程创建（`run.md` + `local/`）；测试脚本落在 `$work/run/` 下，脚本读取凭据时从 `$work/run/local/` 获取，不得硬编码
   - 边界: 初始化 run 后回到本命令继续，不切换到 run 执行流程

5. **回写状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage test next "按 test.md 执行系统测试"`；test.md 已确认后 `progress.test true`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): workspace state <branch>"`，把本命令对 status.yaml 与 test.md 的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；测试脚本属于工作区产物，由本步骤一并提交（`run/local/` 已被 .gitignore 排除，不会入库）

## 后置完成检验

- [ ] `$work/test.md` 已生成，测试目标、范围、验收标准明确，用例逐条可执行
- [ ] 敏感信息未写入 test.md，凭据来源均指向 `run/local/`
- [ ] 需要脚本的场景下 `$work/run/` 已初始化（含 `run.md` 与 `local/`），脚本路径与运行命令已填入 run.md
- [ ] status.yaml 已同步（stage=test，确认后 progress.test=true）

## 下一步建议

- 按 test.md 执行系统测试；需要运行脚本时执行 `run`（初始化或执行模式）
- 测试中发现缺陷走 `fix`；测试与否不阻塞主链路，用户可随时执行 `commit` / `merge`
