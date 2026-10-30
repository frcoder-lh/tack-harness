# 上下文加载纪律

## 定位优先

- 先提炼关键词，再用 `grep` / `glob` 定位目标文件或代码片段。
- 禁止整仓通读、禁止整目录批量加载、禁止对同一文件全文重读。

## 工作区上下文先行

- 在工作区执行任何命令前，先读取 `$work/context.md`：它记录本工作区的需求、背景、链接与约束，可能包含当前任务所需的信息。
- 需求按 story 拆分后，本 story 的 `$work/story/<story>/analysis.md`（现有实现、可行性、兼容性）是 spec/plan/code 的首要代码侧依据；需求明确前的代码问答与分析记录在 `$work/doc/analysis/`。
- 生成的文档（`doc/tech-design.md`、`doc/test.md`、`doc/code-review.md`、`doc/release-check.md`）由对应命令直接读取，不按 wiki 检索。

## 项目作用域

- 每个命令先确认当前工作区与项目：`$work` 来自当前工作区，项目来自 `$work/status.yaml` 的 `project`（无 `$work` 时从 AGENTS.md `projects` 选择）
- 项目 wiki 的读写限定在 `$root/wiki/<project>/`，不隐式跨项目取用；读取按 `harness/rule/wiki-read.md`，写入按 `harness/rule/wiki-write.md`；工作区级参数（MR 地址、泳道、构建版本等）只读 `$work/status.yaml`

## 按需加载

- wiki / 文档类文件：按 `harness/rule/wiki-read.md` 先读索引选分类与文件，只读取命中的小节或相关片段。
- 代码文件：优先 `$work/repo/<repo-name>/`（已有 worktree），没有所需仓库时用 `$root/repo/<repo-name>/`（只读）；先定位再读取关键片段；代码是「唯一真源」。

## 引用方式

- dev 组命令（analyze / spec / plan / tech-design / code / fix / testcode / test / code-review / release-check）在指令内容中引用本文件。
- 各命令可保留特有补充说明（如 plan 保留「额外搜索类似实现」、testcode 保留测试命名模式）。
