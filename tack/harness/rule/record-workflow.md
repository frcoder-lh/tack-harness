# 沉淀 workflow（工作流）规则

> 被 `record` 命令引用：类型判定为 workflow 时，按本文件处理。

## 先扫描，再决定融合或新建

- 执行 `sh $root/harness/script/scan-routes.sh workflows $root/harness` 全量列出工作流并做语义匹配
- **命中相关条目**：读取对应内容，与用户确认如何**融合修正**——最小化修改，不重写无关内容
- **确无合适条目**：才进入新建

## 新建（只问工作流名，其余自动生成）

- 只向用户索取工作流名；AI 根据用户描述自动生成其余全部内容草稿
- 复制 `$root/harness/template/workflow.md` 到 `harness/workflow/<名称>-workflow.md`
- 自动生成：`short`、`triggers`、`summary`，以及适用场景、状态流转、环节→命令映射、状态回写要求

## 验证

- 执行 `sh $root/harness/script/scan-routes.sh list $root/harness`，确认新建/修改后的条目出现在路由表中
