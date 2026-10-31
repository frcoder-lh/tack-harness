---
command: ask
short: a
triggers: 问, 提问, 代码问答, 分析代码, 代码分析, ask, question, code qa, analyze code, code analysis
params: [问题，或仓库名（整体分析时可选）]
summary: 代码理解——入口先选定「总结已有讨论 / 回答新问题 / 核实既有结论 / 整体分析」分支并只加载对应流程，按统一检索策略并发读取工作区分析与项目 wiki，再按需用代码核实；产物落 $work/doc/analysis/（按主题命名），同主题连续问答追加融合，关闭工作区时按归档规则转化沉淀
---

# ask 代码理解

> 入口只做四件事：回写状态 → 选定分支 → 加载对应流程 → 统一收尾；状态回写与空间提交由脚本承接。
> 公共检索按 `harness/rule/wiki-read.md`（含一轮并行取回与检索准确性规则）；只读代码不改代码，结论以代码为唯一真源，引用用 `仓库/路径#L12-L15`，不臆测。

## 前置准入条件

- 已确定当前工作区 `$work`（`$root/space/<workspace>/`）与所属项目（`$work/status.yaml` 的 `project`）
- 有可检索的代码：优先 `$work/repo/<repo-name>/`（已创建 worktree 时），没有所需仓库时使用 `$root/repo/<repo-name>/`（主仓库，只读）；本命令不创建 worktree
- 执行前读取 `$work/status.yaml`；检索准备按第 2 步所选分支取最小集（见分支表「检索准备」列），不统一做全量并行取回

## 指令内容

1. **回写环节状态（脚本）**
   - 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage ask task "<问题摘要或分支名>"`（updated_at 自动刷新）
   - 不改变 `status`（ask 可在任意状态下执行，不推进工作流状态机）

2. **选定分支（一次判定，只加载一份流程）**
   - 输入: 用户问题、参数与已有分析文档头部
   - 动作: 按下表判定意图；表外或意图不清时先追问聚焦，或列出候选请用户选择

     | 分支 | 判定信号 | 检索准备（最小集） | 流程文件 |
     |------|----------|--------------------|----------|
     | 总结已有讨论 | 要求总结/归纳已有分析、结论或讨论记录，不追新问题 | `$work/status.yaml` + `$work/doc/analysis/*.md`、`story/*/analysis.md` 头部 | `cmd/dev/ask/summarize.md` |
     | 回答新问题 | 提出新的代码逻辑问题，现有主题文档未覆盖 | 文档头部 + `$root/wiki/<project>/` 索引；进入代码检索时再确认目标仓库路径与 HEAD | `cmd/dev/ask/answer.md` |
     | 核实既有结论 | 要求核实、复核、确认已有结论，或怀疑其已过时 | 文档头部 + 目标仓库路径、HEAD、分支与工作区状态（与「基准 commit」对比） | `cmd/dev/ask/verify.md` |
     | 整体分析 | 未提出具体问题，要求分析仓库或代码结构 | 目标仓库路径与 Git 状态、全仓结构、`git log`、wiki 索引 | `cmd/dev/ask/overview.md` |

   - 边界: 简单总结不加载整体分析与问答/归档/沉淀说明；只有整体分析才扫描仓库结构与 git history

3. **执行对应流程**
   - 动作: 读取第 2 步选中的流程文件并按其步骤执行；检索一律按 `harness/rule/wiki-read.md`，不重复加载其他分支的说明

4. **统一收尾（脚本承接）**
   - 回写: `sh $root/harness/script/work-status.sh $work/status.yaml set progress.ask true next "等待用户继续提问或进入下一环节"`
   - 提交: `sh $root/harness/script/space.sh commit $root "chore(tack): code analysis <branch>"`（无变更自动跳过；含 `$work/doc/analysis/` 与 status.yaml，不含 worktree 代码，边界见 `harness/rule/git-boundary.md`）
   - 输出: 分析文档路径与摘要，或当场回答

## 后置完成检验

- [ ] 只加载了一个分支流程；简单总结未加载整体分析与其他无关说明
- [ ] 工作区分析一律按 `$work/doc/analysis/` 目录检索并按头部「主题」匹配，未假定 `-analysis` 后缀或固定文件名
- [ ] 整体分析：文档头部含主题与基准 commit，已做新鲜度检查，已呈现锚点/决策候选
- [ ] 回答/核实：同主题落在同一文档；新主题才新建，未产生重复文档
- [ ] 结论均有 `仓库/路径#L12-L15` 锚点或 commit hash 依据；未臆测；与旧结论冲突时注明「原结论 X，当前代码 Y」
- [ ] `$work/status.yaml` 已同步（progress.ask=true）；本命令未修改任何代码文件

## 下一步建议

- 继续围绕同一主题提问，结论会持续融合；执行 `analyze` / `spec` / `plan` 时引用 `$work/doc/analysis/` 与 `story/<story>/analysis.md` 作为代码侧上下文
- 发现的待确认问题可向项目成员澄清后回写文档
