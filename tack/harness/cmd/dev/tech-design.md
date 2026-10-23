---
command: tech-design
short: td
triggers: 技术方案, 技术文档, 技术评审, tech-design, technical design, tech doc, tech review
params: 无
summary: 仅在需要正式评审时，按技术模板将已确认的 spec 与 plan 重组为技术评审文档 tech-design.md（扁平存放于工作区根，不新增设计决策）
---

# tech-design 技术评审文档（按需）

> development 工作流 planning 的按需环节：仅在需要正式评审时生成。
> 定位：把 spec.md 与 plan.md 按技术模板重组为评审文档，内容全部来源于两者，不新增设计、不新增决策。
> 发现评审所需信息缺失时，先回补 spec/plan（走 `fix`），不在本文档另起口径。

## 前置准入条件

- 已确定当前工作区 `$work`
- `$work/spec.md` 已确认（`progress.spec: true`）；`$work/plan.md` 已确认（`progress.plan: true`）
- 已确认本次需要正式评审（用户或团队评审流程触发）

## 指令内容

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage tech-design next "生成并确认 tech-design.md"`（自动刷新 updated_at）

2. **读取模板与分析产物**
   - 输入: `$root/harness/template/tech-design.md`、`$work/spec.md`、`$work/plan.md`（执行前重新读取，尊重本地最新内容）
   - 动作: 对照模板章节，必要时查阅 `$root/wiki/<project>/` 与 `$work/wiki/` 中的服务与配置信息；核对 spec 与 plan 的口径一致
   - 加载纪律: 遵守 `harness/rule/context-loading.md`，按技术点关键词定位 wiki 小节与代码文件（数据模型、接口、配置）

3. **生成技术评审文档**
   - 动作: 在 **`$work/tech-design.md`**（扁平文件，非 doc/ 子目录）按模板输出：需求回顾与方案概述（来源 spec）、架构与模块划分、数据流、详细设计（数据模型/API/核心逻辑/异常处理）、技术选型、安全与性能设计、部署与上线方案（来源 plan）、风险与待确认
   - 来源要求: 每个章节标注来源（spec.md / plan.md 及对应位置），内容可在两份文档中找到依据
   - 纪律: 只做评审化重组与呈现，不新增设计事实、不新增决策；确需补充时回补 spec/plan 后重新生成
   - 多服务场景明确服务边界与调用关系，与 spec.md 的边界约定保持一致

4. **审阅与外链**
   - 输入: 用户审阅意见
   - 动作: 按意见修订并经用户确认；若团队用飞书等承载技术文档，执行 `sh $root/harness/script/work-status.sh $work/status.yaml set tech_doc_url "<url>"` 回填外链

5. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.tech-design true next "执行 code 开始逐任务开发"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): tech-design <branch>"`，把 tech-design.md 与 status.yaml 的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] `$work/tech-design.md` 章节与模板一致，覆盖 spec/plan 全部范围
- [ ] 每个章节标注来源，内容可在 spec.md / plan.md 找到依据，无新增设计决策
- [ ] 影响的服务/仓库清单明确，边界与 spec 一致
- [ ] 用户/评审人已审阅确认；外链（如有）已回填
- [ ] `$work/status.yaml` 已同步（progress.tech-design=true）

## 下一步建议

- 执行 `code` 按 status.yaml 的 tasks 列表逐任务开发
