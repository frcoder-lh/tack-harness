# 读取项目 wiki 规则（公共读取指令）

> 所有读取 `$root/wiki/<project>/` 与工作区文档（`$work/doc/analysis/`、`$work/story/*/analysis.md`）的流程统一按本文件执行：`analyze`、`ask`、`work` 开场清单、`spec`、`plan`、`code`、`fix`、`testcode`、`test`、`tech-design`、`code-review`、`release-check`、`deploy` 等命令都引用本文件。
> 写入按 `harness/rule/wiki-write.md`；命名按 `harness/rule/naming.md`；只读当前项目，不跨项目取用。

## 一、先走索引，再读文件

1. **提炼关键词**：从问题、任务标题、模块名、服务名、接口名与业务术语提取检索词。
2. **读项目总索引**：先读 `$root/wiki/<project>/index.md`，按主题判断应去哪个分类，不逐个分类盲扫。
3. **读分类索引**：读该分类的 `index.md`，据「主题 | 文件 | 收录内容」选择具体文件或低层目录；索引指向子目录时，优先读子目录的 `index.md`，没有则按主题在子目录内定位文件。
4. **只读命中内容**：对选中的文件用 `grep` 定位命中小节，只读相关片段；禁止整目录批量加载与整文件反复通读。
5. **索引缺失或明显不完整**：可 `glob` 定位文件补充线索，但读取仍以命中片段为限；索引问题交由 `evolution` 的索引完整性校准处理。

## 二、分类导航

| 问题类型 | 优先查看 |
|----------|----------|
| 业务做什么、术语什么意思、领域边界与不变量 | `biz/`：`background.md`、`glossary.md`、`domains.md` |
| 某个术语/接口对应哪段代码、仓库怎么组织 | `code/`：`repos.md`、`anchors.md`、`interfaces.md` |
| 这个项目为什么这样定、有哪些工程约定 | `rule/`：`decisions.md`、`conventions.md` |
| 某服务部署在哪、地址/泳道/账号/配置怎么查 | `config/`：`services.md`、`env.md`、`accounts.md`、`settings.md` |
| 过去某个需求为什么做、是否设计如此 | `history/`：按工作区目录读 `summary.md`，需要复用脚本时读同目录 `run/` |

## 三、工作区文档与项目 wiki

- `$work/doc/analysis/`：需求明确前的代码问答与仓库分析（如 `<repo>-analysis.md`、主题问答文档），可能绑定旧代码；读取前先看头部「基准 commit」是否与当前 HEAD 一致。
- `$work/story/<story>/analysis.md`：需求分析产物（现有实现、可行性、兼容性、待确认问题），按 story 一份；同样先看「基准 commit」。
- `$work/doc/` 下的 `tech-design.md`、`test.md`、`code-review.md`、`release-check.md` 是命令产物，由对应命令直接读取，不按 wiki 索引检索。
- `$root/wiki/<project>/`：跨工作区的稳定知识，只放代码里拿不到的事实、导航锚点、业务背景、决策约定与配置参数。
- `ask` 与 `analyze` 的初步检索**同时并发检索**工作区 `doc/analysis/`、`story/*/analysis.md` 与 `$root/wiki/<project>/`（含 `history/`），命中合并后再判断下一步。

## 四、取用纪律

- 项目 wiki 与历史归档只作导航和背景，**不作为代码事实**；与当前代码不一致时以代码为准。
- 回答中注明差异：「历史记录为 X，当前代码为 Y」；归档里的可行性分析、找 bug 过程与实现细节不作为结论。
- 只有 `confirmed` / `verified` 的条目默认作为上下文；`reported` / `candidate` 只作线索，需核实后再使用。
- 工作区分析文档若基准 commit 已偏离当前 HEAD，先提示结论可能过时，再据实更新或重新分析。

## 五、深度检索与代码核实

出现以下任一情况时，不停留在 wiki，自动检索最新代码核实：

- 初步检索没有搜到相关信息；
- wiki 信息太老（基准 commit 偏离、复核条件已触发）或信息不全；
- 用户明确要求以代码为准或要求核实。

代码检索顺序：

1. 优先搜索当前工作区代码 `$work/repo/<repo-name>/`（worktree，检出当前分支）；
2. 当前工作区没有所需仓库时，搜索根目录主仓库 `$root/repo/<repo-name>/`（只读基准，不直接修改）；
3. 需要修改代码时，再由 `code` / `worktree` 按需创建 worktree。

## 六、禁止

- 禁止整仓通读、整目录批量加载、对同一文件全文反复读取。
- 禁止跨项目读取 `wiki/<other-project>/`。
- 禁止把 wiki 中未经原始产物证实的表述当作新事实再次传播（防循环放大）。
- 禁止把工作区级参数（MR 地址、泳道、构建版本等）从项目 wiki 读取——它们在 `$work/status.yaml`。
