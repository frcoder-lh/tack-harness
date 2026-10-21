# 上下文加载纪律

## 定位优先

- 先提炼关键词，再用 `grep` / `glob` 定位目标文件或代码片段。
- 禁止整仓通读、禁止整目录批量加载、禁止对同一文件全文重读。

## 项目作用域

- 每个命令先确认当前工作区与项目：`$work` 来自当前工作区，项目来自 `$work/status.yaml` 的 `project`（无 `$work` 时从 AGENTS.md `projects` 选择）
- 项目 wiki 的读写限定在 `$root/wiki/<project>/`，不隐式跨项目取用；工作区级参数（MR 地址、泳道、构建版本等）只读 `$work/status.yaml`

## 按需加载

- wiki / 文档类文件：只读取命中的小节或相关片段。
- 代码文件：先定位再读取关键片段；代码是「唯一真源」。

## 引用方式

- dev 组命令（spec / plan / tech-design / code / fix / testcode / test / code-review / release-check）在指令内容中引用本文件。
- 各命令可保留特有补充说明（如 plan 保留「额外搜索类似实现」、testcode 保留测试命名模式）。
