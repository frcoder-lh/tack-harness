# 命令执行与上下文复用

## 一次准备

- 已确认 `$work` 后，使用 `command-context.sh packet <root> <workspace> [story]` 一次取得状态、任务清单、文档摘要值与章节行号。准备范围服从当前命令：Git 操作只取 Git 事实；纯 help/list 查询直接使用索引；开发命令只补读目标 story 的相关章节。
- 文件首次使用时读取相关内容；同一会话中路径与内容指纹相同可复用。指纹只是新鲜度证据，不能替代首次阅读。工作区切换、上下文压缩后缺少正文、外部改动或摘要变化时重新读取。
- 规则按当前命令的显式引用和任务类型加载；共同依赖同一轮读取。同一规则在连续环节中只加载一次，新增语言、权限或数据操作时补齐对应约束。
- 独立仓库、文件和索引的读取同一轮并行；脚本可确定的顺序执行、参数检查和结果汇总在一次调用内完成。失败后先看退出码与最小日志片段，再决定恢复动作。

## story 确认与自动流转

- analysis/spec/plan 的审阅通过或用户已授权相应决策后，执行 `sh $root/harness/script/command-context.sh confirm $root <workspace> <story> <stage>`；回执绑定 context、该阶段及上游文档、命令与规则内容，保存于 `.tack/state/context/`。
- 恢复 auto 时先用 `sh $root/harness/script/command-context.sh stories $root <workspace>` 查询各 story 的确认状态；只读未确认/变化阶段所需的正文。回执缺失时核对原文与已有授权再补记，不能从文件存在或工作区级 progress 推断某个 story 已确认。
- `progress` 保留为兼容的工作区汇总；多 story 的准入以目标 story 的回执与实际任务为准。code 改动不会让已确认的需求文档自动失效，需求/规则变更会使相关回执失效。

## 评审证据

- code-review / release-check 在采集 diff 前执行 `sh $root/harness/script/command-context.sh evidence $root <workspace> <label> <target>`，label 分别为 `code-review`、`release-check`。
- 指纹包括工作区路径作用域、需求文档、规则、仓库 HEAD、目标引用、暂存/未暂存 diff 与未跟踪文件内容及名称；报告正文不参与自身的输入指纹。
- 首次评审读取完整范围；已有通过的报告且 `EVIDENCE=unchanged` 时复用其证据。变化时按 manifest 差异定位仓库/文档，刷新涉及的 diff 与问题清单；共享接口、规则或目标分支变化时扩大到其影响范围。
- 只有完成相应评审并记录结论后才执行 `accept`（evidence 相同参数后加本次返回的 EVIDENCE_TOKEN）；脚本重算指纹并核对指定 token，拒绝接受评审过程中变化的输入，多个评审者相互独立。测试环境、远端 CI/MR 状态、凭据与发布平台事实需当次查询，禁止用本地指纹推断仍有效。

## 合并回写与收尾

- 同一环节的 status/stage/task/next/progress 使用一次 `work-status.sh set`；连续任务使用 `tasks claim` 和 `tasks complete-next`，指定单任务的执行范围不得外扩。
- 阶段完成后，可使用 `sh $root/harness/script/command-batch.sh finish $root <workspace> <stage> "<下一步>" "<提交信息>" <本次文件...>` 合并进度回写与框架提交。只传本任务实际改动的文件；未完成或 blocked 阶段使用普通 set，不能调用 finish 标记完成。
- init 的标量/关键词/服务映射用 `command-batch.sh register` 一次执行 TSV 清单；work 用 `work-create`；worktree 用 `attach`；guidance 用 `guidance` 批量执行已确认清单。子操作失败即停，重试前核对已成功记录。
- 人工确认集中展示本次所有未决项、建议与依据；已有授权直接复用。模块里程碑只报告结果，遇业务决策、必要外部动作或明确的安全门禁才暂停。

## 增量产物

- analyze/spec/fix：以用户新增事实、文档差异与受影响 story 为范围，保留未变化结论；fix 重开已完成任务先用 `tasks set <id> pending`，完成分析后按依赖 claim。新增任务使用 `tasks import`，由脚本保留其它 story 和已有状态。
- tech-design：先建立「目标章节 → story/spec/plan 小节」映射，读已确认的输入；只重组变化章节及引用它的概览，统一审阅未决项。
- testcode：一轮运行约定的测试/覆盖率命令，返回通过数、失败数、覆盖率、未覆盖改动行和报告位置；正文只读取失败用例与相关覆盖缺口，新增改动后再跑受影响范围。
- test：先读现有测试方案及 `run-plan.sh index` 输出，复用可执行指令；只补缺失场景，环境、账号与数据需求集中补齐。
- record/study：先看紧凑路由、目录与标题，筛选相关素材再读正文；相同来源与落点的候选去重后一并审阅。校验只执行一遍入口 lint 已包含的子检查。
- evolution：显式 `full` 覆盖全部文件；`incremental` 基于调用方提供的变更清单或 Git 范围，再加入变更文件的反向引用和 pending guidance 对应落点。增量来源不可靠时回退 full；报告注明范围。
- close：先用 `command-batch.sh close-facts` 为当前及关联工作区取齐事实，汇总交付例外、归档、wiki/guidance 与额外文件的一个决策清单。批准后先子后父完成已有清理脚本；最后 `close-remove` 合并 purge 与移除登记，失败按保留的事实与登记继续。
