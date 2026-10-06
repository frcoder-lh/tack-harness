---
command: release-check
short: rc
triggers: 上线检查, 发布检查, release-check, releasecheck, release check, go-live check
params: [目标分支（默认主干）]
summary: 上线前检查清单——以 plan.md/tech-design.md 与目标分支三点 diff 为输入，逐项识别数据库变更（给出变更语句）、配置变更（给出变更模板）、新增接口调用（需申请权限）、新增中间件（需提前申请配置）等上线检查项，产出 $work/release-check.md
---

# release-check 上线检查

> 回答「上线前要准备什么」：把 diff 中每一处环境相关变化翻译成可执行的上线检查项（含变更语句/模板/申请内容），逐项打勾后上线。

## 前置准入条件

- 已确定当前工作区 `$work`
- `$work/plan.md` 已确认；`$work/tech-design.md` 存在（无则在报告头部注明）
- 各涉及仓库当前分支改动已 `commit`（检查基于提交事实）；建议先 `fetch`
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——只读操作仅在 `$work/repo/<repo-name>/` 内执行

## 指令内容

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage review task 上线检查 next 生成release-check.md`（自动刷新 updated_at）；不改变 `status`

2. **确定范围并导出 diff 事实**
   - 动作: 与 `code-review` 第 2 步相同——汇总涉及仓库，逐仓库执行：
     `sh $root/harness/script/git-diff-context.sh $work/repo/<repo-name> $root/.tack/tmp/review [目标分支]`
     `empty: true` 的仓库说明后跳过；全部为空时中止并提示「与目标分支无差异」
   - 若已有 `$work/code-review.md` 且其头部基准与本次 merge-base/HEAD 一致，可复用其 diff 结论，仅补充检查项识别

3. **加载输入**
   - 规范: `$work/plan.md`、`$work/tech-design.md`（部署架构、依赖清单、数据模型章节）
   - 环境事实: `$root/wiki/manifest.md` 的「环境与事实信息」（部署环境、平台入口、申请流程，如已登记）
   - 事实: 各仓库 diff 文件 + 必要的完整文件上下文（配置模板、migration 全文）；加载纪律遵守 `harness/rule/context-loading.md`

4. **逐项识别上线检查项**（以 diff 为唯一事实来源，每项附 `路径:行号` 锚点）
   - **数据库变更**：新增/修改表、字段、索引，数据迁移与订正——从 migration 文件、ORM 实体、SQL 资源提取，**给出可执行变更语句**（DDL/DML）与回滚语句；标注执行环境（BOE/PPE/PROD）与执行时机（发布前/发布中/发布后）
   - **配置变更**：新增/修改的配置键（应用配置、配置中心、环境变量、特性开关）——**给出变更模板**：键名、值示例、说明、来源文件锚点、生效环境；区分「必须随发布生效」与「可后续调整」
   - **新增接口调用**：新增的对外依赖调用（HTTP/RPC client、消息生产、第三方 API）——列出目标服务与接口、来源锚点，标注**需申请的权限**（服务权限/网络白名单/鉴权凭据）与超时、重试、降级建议
   - **新增中间件**：新增的中间件依赖（MQ topic、Redis key 空间、ES 索引、调度平台任务等）——列出类型、用途、来源锚点，标注**需提前申请与配置**的资源（集群、topic、权限）与依赖环境
   - **其他检查项（仅列 diff 实际命中的，无命中省略）**：新增定时任务/Worker、新端口或新服务、密钥与凭据（走凭据管理平台，不入库）、监控告警与日志、容量与灰度、回滚预案
   - 纪律: 无命中的类别标注「本次无变更」；识别不出的疑似项列入「待人工确认」，不臆造

5. **生成检查清单 `$work/release-check.md`**
   - 头部: `> 审查范围: <target_ref>...HEAD（merge-base: <short-hash>）　仓库: <清单>　生成时间: <日期>`
   - 每类检查项一节，统一表格：`| # | 检查项 | 来源锚点 | 变更语句/模板/申请内容 | 环境 | 状态 |`（状态列留 `[ ]` 供上线时逐项打勾）
   - 末尾「上线顺序建议」：按依赖排序（资源申请 → 数据库变更 → 配置下发 → 代码发布 → 验证与灰度）；多仓库时标注发布顺序
   - 向用户呈现清单并请确认；有上线计划时提示登记 `$work/status.yaml` 的 `deploy` 区块（结构见 `harness/template/work-status.yaml`）

6. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.release_check true next "按清单完成上线准备；未合并先 merge，收尾走 close"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): release check <branch>"`，把 `$work/release-check.md` 与 status.yaml 变更自动提交到空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；`.tack/tmp/review/` 的 diff 临时文件不入库、可随时清理

## 后置完成检验

- [ ] 四类检查项（数据库/配置/接口调用/中间件）逐类有结论：变更语句、变更模板、申请内容齐全，或标注「本次无变更」
- [ ] 每条检查项附代码锚点；变更语句可执行且含回滚；配置模板含键/值示例/生效环境
- [ ] 无臆造检查项；存疑项已列入「待人工确认」
- [ ] `$work/status.yaml` 的 progress.release_check 已置 true；本命令未修改任何代码文件

## 下一步建议

- 按清单完成资源申请与环境配置后安排上线；未合并时先执行 `merge`
- 上线完成并验证后执行 `close` 关闭工作区（BOE 验证泳道不再使用时置 `recycled`）
