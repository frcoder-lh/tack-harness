# close 流程：消费 guidance 自进化（第 7 步）

> 由 `cmd/dev/close.md` 第 7 步在存在 pending guidance 时加载；步骤编号与主文件一致。

7. **自进化：消费 guidance，固化操作习惯到 harness**
   - 输入: 第 7 步入口已取得的 `sh $root/harness/script/work-status.sh $work/status.yaml guidance list pending` 结果
   - 动作: 逐条按 `harness/rule/record-classification.md` 判据评估——筛出**跨工作区可复用的操作习惯/流程修正**（应固化为 workflow/cmd/rule 的内容），一次性过程信息标记为不固化；汇总为候选清单：来源条目 id | 场景与用户引导 | 建议落点（workflow/cmd/rule 及具体文件）| 融合或新建
   - 询问: 向用户展示候选清单，可全部采纳、挑选部分或放弃（**落盘必须经用户确认**，本步不擅自改 harness）
   - 落盘: 采纳项走 `record` 流程——先扫描对应 workflow/cmd/rule，**能融合则融合**，确无合适条目才新建；同时按「沉淀生命周期」的固化门槛检查，发现确定性固定步骤一并提议固化为 script
   - 回写: 落盘完成的条目执行 `sh $root/harness/script/work-status.sh $work/status.yaml guidance <id> applied <相对 $root 的落点路径...>`（多落点空格分隔，脚本校验落点文件存在后只置 `status: applied`），路径不存在时按报错修复后重试；放弃或评估为不固化的执行 `sh $root/harness/script/work-status.sh $work/status.yaml guidance <id> rejected`；用户暂缓决断的保留 `pending` 与工作区，停止关闭，之后可通过 `evolution`/`record` 处置再续跑。
   - 边界: guidance 只作为候选素材，事实存疑、无法从工作区过程证实的不固化；wiki 类知识已在第 6 步处理，本步只面向 workflow/cmd/rule
