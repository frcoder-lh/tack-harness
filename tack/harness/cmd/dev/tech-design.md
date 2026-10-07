---
command: tech-design
short: td
triggers: 技术方案, 技术文档, 技术评审, tech-design, technical design, tech doc, tech review
params: 无
summary: 结合技术模板与 spec/plan 产出技术评审文档 tech-design.md（扁平存放于工作区根）
---

# tech-design 技术评审文档

> development 工作流 planning 环节的第三步：根据需求输入与 spec/plan 分析产物，结合技术模板产出最终技术评审文档。

## 前置准入条件

- 已确定当前工作区 `$work`
- `$work/spec.md` 已确认；`$work/plan.md` 建议已确认（跳过需用户明确确认）
- 执行前重新读取相关文件，尊重本地最新内容

## 指令内容

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage tech-design next "生成并确认 tech-design.md"`（自动刷新 updated_at）

2. **读取模板与分析产物**
   - 输入: `$root/harness/template/tech-design.md`、`$work/spec.md`、`$work/plan.md`
   - 动作: 对照模板章节，必要时查阅 `$root/wiki/` 与 `$work/wiki/` 中的服务与配置信息
   - 加载纪律: 遵守 `harness/rule/context-loading.md`，按技术点关键词定位 wiki 小节与代码文件（数据模型、接口、配置）

3. **生成技术评审文档**
   - 动作: 在 **`$work/tech-design.md`**（扁平文件，非 doc/ 子目录）输出：需求回顾与方案概述、架构与模块划分、数据流、详细设计（数据模型/API/核心逻辑/异常处理）、技术选型、安全与性能设计、部署方案、风险与待确认
   - 多服务场景明确服务边界与调用关系，与 spec.md 的边界约定保持一致

4. **审阅与外链**
   - 输入: 用户审阅意见
   - 动作: 按意见修订并经用户确认；若团队用飞书等承载技术文档，将外链回填 `$work/status.yaml` 的 `tech_doc_url`

5. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.tech-design true next "执行 code 开始逐任务开发"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): tech-design <branch>"`，把 tech-design.md 与 status.yaml 的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] `$work/tech-design.md` 章节与模板一致，覆盖 spec/plan 全部范围
- [ ] 影响的服务/仓库清单明确，边界与 spec 一致
- [ ] 用户已审阅确认；外链（如有）已回填
- [ ] `$work/status.yaml` 已同步（progress.tech-design=true）

## 下一步建议

- 执行 `code` 按 status.yaml 的 tasks 列表逐任务开发
