---
command: help
short: h
triggers: 帮助, 命令, help
params: [工作流或命令名（可选）]
summary: 扫描 harness，输出全部工作流与命令的触发词、参数与作用
---

# help 帮助

## 前置准入条件

- 无。不是 tack 空间时，只输出初始化指引

## 指令内容

1. **输出完整路由表（工作流 + 命令）**
   - 动作: 执行 `sh $root/harness/script/scan-routes.sh list $root/harness`，将输出原样呈现：先「工作流 (workflow)」表，再按分组（项目空间/需求开发/Git）展示命令表；包含简写、中英文触发词、参数、作用、对应文件

2. **非 tack 空间**
   - 动作: 仅提示当前目录不是 tack 空间，引导在空目录执行 `/tack` 初始化

3. **查看单条工作流或命令详情（带名称参数时）**
   - 输入: 用户指定的工作流、命令或触发词
   - 动作: 执行 `sh $root/harness/script/scan-routes.sh resolve $root/harness <名称>`，按输出类型前缀（`workflow|` / `cmd|`）定位文件，读取后展示其触发词、适用场景或前置准入条件与内容摘要

## 后置完成检验

- [ ] 用户能看到每条工作流/命令的调用方式、简写、触发词、参数与作用
- [ ] 列表与 harness/workflow、harness/cmd 目录实际文件一致（扫描生成，非手写）

## 下一步建议

- 根据用户意图引导进入对应工作流或直接执行对应命令
