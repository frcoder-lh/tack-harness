---
command: ask
short: a
triggers: 问, 提问, 代码问答, 分析代码, 代码分析, ask, question, code qa, analyze code, code analysis
params: [问题，或仓库名（整体分析时可选）]
summary: 代码理解——入口先选定「总结已有讨论 / 回答新问题 / 核实既有结论 / 整体分析」分支并只加载对应流程，由 command-context.sh analysis 一次取回分析文档头部与新鲜度，按统一检索策略读取工作区分析与项目 wiki，再按需用代码核实；产物落 $work/doc/analysis/（按主题命名、统一头部），同主题连续问答追加融合，关闭工作区时按归档规则转化沉淀
---

# ask 代码理解

> 入口只做四件事：选定分支 → 加载对应流程 → 执行 → 统一收尾；状态回写与空间提交由脚本承接。
> 公共检索与证据纪律按 `harness/rule/wiki-read.md`（含一轮并行取回与「检索准确性」）；只读代码不改代码，结论以代码为唯一真源，不臆测。

## 前置准入条件

- 已确定当前工作区 `$work`（`$root/space/<workspace>/`）与所属项目（`$work/status.yaml` 的 `project`）
- 有可检索的代码：优先 `$work/repo/<repo-name>/`（已创建 worktree 时），没有所需仓库时使用 `$root/repo/<repo-name>/`（主仓库，只读）；本命令不创建 worktree
- 检索准备按所选分支取最小集（见分支表「检索准备」列），不统一做全量并行取回

## 分析文档头部（各分支共用）

`$work/doc/analysis/` 下的文档统一使用以下头部，新建时写全、更新时就地刷新：

```markdown
# <中文主题>

> 主题: <主题关键词>
> 涉及仓库: <repo1, repo2>
> 基准 commit: <repo1@short-hash, repo2@short-hash>
> 最近更新: <日期>
```

- 单仓库时「基准 commit」可只写 short-hash；多仓库必须逐仓库写 `仓库@hash`，避免新鲜度比对错位
- 头部与新鲜度一律经 `sh $root/harness/script/command-context.sh analysis $root <workspace>` 取回（`DOC` 行为路径/主题/最近更新，`BASE` 行为逐仓库基准/HEAD/落后提交数/fresh|stale|unknown），不逐个打开文件读头部、不手工 `rev-list`

## 指令内容

按分支准备最小上下文，复用 `harness/rule/execution-efficiency.md` 的状态与文件指纹；已加载且未变化的入口、索引和证据直接使用，只有本次问题相关的分支文档与片段进入上下文。

1. **选定分支（一次判定，只加载一份流程）**
   - 输入: 用户问题、参数与 `command-context.sh analysis` 输出
   - 动作: 按下表判定意图；表外或意图不清时先追问聚焦，或列出候选请用户选择

     | 分支 | 判定信号 | 检索准备（最小集） | 流程文件 |
     |------|----------|--------------------|----------|
     | 总结已有讨论 | 要求总结/归纳已有分析、结论或讨论记录，不追新问题 | `analysis` 输出 + 目标文档结论区 | `cmd/dev/ask/summarize.md` |
     | 回答新问题 | 提出新的代码逻辑问题，现有主题文档未覆盖 | `analysis` 输出 + `$root/wiki/<project>/` 索引；进入代码检索时再确认目标仓库路径 | `cmd/dev/ask/answer.md` |
     | 核实既有结论 | 要求核实、复核、确认已有结论，或怀疑其已过时 | `analysis` 输出（`BASE` 行即基准与 HEAD 对比）+ 目标仓库分支与工作区状态 | `cmd/dev/ask/verify.md` |
     | 整体分析 | 未提出具体问题，要求分析仓库或代码结构 | 目标仓库路径与 Git 状态、全仓结构、`git log`、wiki 索引 | `cmd/dev/ask/overview.md` |

   - 边界: 简单总结不加载整体分析与问答/归档/沉淀说明；只有整体分析才扫描仓库结构与 git history

2. **执行对应流程**
   - 动作: 读取第 1 步选中的流程文件并按其步骤执行；检索一律按 `harness/rule/wiki-read.md`，不重复加载其他分支的说明

3. **统一收尾（脚本承接）**
   - 有文档变更: 执行 `sh $root/harness/script/command-batch.sh finish $root <workspace> ask "等待用户继续提问或进入下一环节" "chore(tack): code analysis <branch>" "$work/doc/analysis"`，一次回写 `stage ask`、`progress.ask true`、`next` 并提交（不含 worktree 代码，边界见 `harness/rule/git-boundary.md`）
   - 无文档变更（总结未产生新结论、当场回答未落盘）: 不回写状态、不提交
   - 输出: 分析文档路径与摘要，或当场回答
   - ask 可在任意状态下执行，不改变 `status`、不推进工作流状态机

## 后置完成检验

- [ ] 只加载了一个分支流程；简单总结未加载整体分析与其他无关说明
- [ ] 工作区分析经 `command-context.sh analysis` 取回并按「主题」匹配，未假定 `-analysis` 后缀或固定文件名
- [ ] 新建/更新的文档头部符合「分析文档头部」，多仓库基准逐仓库记录
- [ ] 整体分析：已做新鲜度检查，已呈现锚点/决策候选
- [ ] 回答/核实：同主题落在同一文档；新主题才新建，未产生重复文档
- [ ] 结论均有 `仓库/路径#L12-L15` 锚点或 commit hash 依据；未臆测；与旧结论冲突时注明「原结论 X，当前代码 Y」
- [ ] 有文档变更时已经 `finish` 回写 progress.ask=true 并提交；本命令未修改任何代码文件

## 下一步建议

- 继续围绕同一主题提问，结论会持续融合；执行 `analyze` / `spec` / `plan` 时引用 `$work/doc/analysis/` 与 `story/<story>/analysis.md` 作为代码侧上下文
- 发现的待确认问题可向项目成员澄清后回写文档
