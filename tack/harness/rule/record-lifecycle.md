# 记录与固化生命周期

> 常驻引用名：guidance 采集规则 / 沉淀生命周期。常驻 AGENTS.md 只保留「触发条件 → 原始记录 → 固化入口」三行骨架，本文件在采集或固化时加载。
> 分类判据见 `harness/rule/record-classification.md`；各类落盘细则见 `harness/rule/record-*.md`。

## 触发条件

| 条件 | 说明 |
|------|------|
| 任务/环节结束 | 用户对 AI 的做法有过引导、纠偏或补充约定 |
| 耗时任务完成前 | 多步骤、跨文件、多轮试错的任务，主动做一次沉淀预判 |
| 修改 `harness/cmd/` | 检查命令中是否有可提炼为 `harness/script/` 的机械固定步骤 |
| 用户主动要求 | 用户说「记录 / 记住 / 沉淀 / 把刚才的引导记下来」时走 `record` |

## 原始记录

- 位置：`$work/status.yaml` 的 `guidance` 列表；字段结构见 `harness/template/work-status.yaml`。
- 只记事实：场景、用户原话或引导、建议固化点（`cmd` / `workflow` / `rule` / `script` / `wiki`），不做演绎。
- 状态先置 `pending`；**不直接改动 harness**，采集与固化分离。
- 耗时任务的沉淀预判同样只追加原始记录，不自行落盘。
- 无工作区时（如纯会话中的引导），待创建或切换工作区后再补记。

## 固化入口

| 入口 | 触发方式 | 行为 |
|------|----------|------|
| `record` | 用户主动要求 | 按分类判据扫描现有条目，能融合则融合、确无条目才新建；人工审阅后落盘并回写 applied |
| `close` | 工作区关闭时自动执行 | 消费本工作区全部 pending，形成候选清单；用户确认后固化到 workflow/cmd/rule，未确认的保留 pending，不阻塞关闭 |
| `evolution` | 用户发起专项审查 | 审查全部 cmd/rule/workflow 与各工作区 pending，输出 A/B 两组候选，确认后落盘 |

## 固化门槛

- 只有「未来会以同样方式重复」的机械步骤才提炼为 `harness/script/` 脚本；一次性操作不固化。
- 可复用的操作习惯固化到 workflow/cmd/rule；项目级事实进 `$root/wiki/<project>/`；能力进 `harness/`。
- 事实存疑、无法从工作区过程证实的内容不固化。

## 回写

- 已落盘：`sh $root/harness/script/work-status.sh <status.yaml> guidance <id> applied <相对 $root 的落点路径...>`
- 评估后不固化：`... guidance <id> rejected`
- 用户暂缓：保留 `pending`，可由后续 `close` / `evolution` 继续处理。
