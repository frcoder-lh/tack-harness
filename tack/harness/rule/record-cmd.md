# 沉淀 cmd（命令）规则

> 被 `record` 命令引用：类型判定为 cmd 时，按本文件处理。

## 先扫描，再决定融合或新建

- 执行 `sh $root/harness/script/scan-routes.sh commands $root/harness` 全量列出命令，结合记录内容做语义匹配
- **命中相关条目**：读取对应内容，与用户确认如何**融合修正**——最小化修改，不重写无关内容
- **确无合适条目**：才进入新建

## 新建（只问 command，其余自动生成）

- 只向用户索取命令的 `command`；AI 根据用户对能力的描述自动生成其余全部内容草稿
- 复制 `$root/harness/template/cmd.md` 到 `harness/cmd/<分组>/<command>.md`
- 自动生成：
  - front matter：`short`（简写）、`triggers`（中英文触发词）、`params`、`summary`
  - 四段正文：前置准入条件、指令内容（分步写清输入与动作）、后置完成检验、下一步建议
  - 有明确误用边界时补「不适用场景」可选段

## front matter 写法规范

- `summary` 是语义路由的命中依据，必须同时写清**做什么 + 什么时候用**；禁止笼统描述（反例：「帮助处理文档」；正例：「在 plan 前对需求资料做澄清问询，产出确认稿」）
- `triggers` 收录用户真实会说的中英文说法（含动词与名词形态）；**先执行 `scan-routes.sh list` 核对**：名称、简写、每个触发词均不得与其他 workflow/cmd 重复，否则 resolve 会多命中
- `command` 必须与文件名完全一致；`short` 用 1-5 个字母且全局唯一
- 落盘后执行 `harness/script/lint-harness.sh` 自检，ERROR 必须清零

## 分组选择

- 项目空间操作进 **base**，需求开发环节进 **dev**，Git 操作进 **git**；允许新建自定义分组

## 分工原则

- 固定流程尽量落到 script，规则落 rule，模板落 template，复杂独立能力引用 reference

## 验证

- 执行 `sh $root/harness/script/scan-routes.sh list $root/harness`，确认新建/修改后的条目出现在路由表中
