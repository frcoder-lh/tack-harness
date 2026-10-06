---
command: run
short: rn
triggers: 运行, 执行, 跑脚本, 执行脚本, run, execute, run script
params: [模式（可选：init 显式初始化；默认自动判断）]
summary: 按需命令（非开发必经环节，用户需要时触发）——脚本执行管理：当前工作区无 run/ 时初始化（run.md + local/），有 run.md 时加载并按其中清单执行脚本；敏感数据一律落 run/local/
---

# run 脚本执行（按需命令）

> **按需触发，不是 development 主链路的必经环节**：仅当用户主动要求执行脚本（或 `test` 方案需要脚本）时运行，不需要任何"跳过"标记，不执行不阻塞提交与合并。
> 两种模式自动判断：`$work/run/` 不存在 → 初始化；`$work/run/run.md` 存在 → 执行。
> 用户也可显式传 `init` 强制初始化。

## 前置准入条件

- 已确定当前工作区 `$work`
- 执行模式下 `$work/run/run.md` 存在且脚本清单非空

## 不适用场景

- 只生成测试方案、不实际运行脚本 → 走 `test`
- 编译/运行被测代码本身（属于 `code` 的构建验证）→ 走 `code` 内部流程

## 模式 1：初始化 run/ 目录

触发条件：`$work/run/` 不存在，或用户显式传 `init`。

1. **创建目录骨架**
   - 动作: 创建 `$work/run/` 与 `$work/run/local/`
   - 边界: `run/local/` 已被 `.gitignore` 全局忽略，敏感数据不入版本库

2. **生成 run.md**
   - 动作: 复制 `harness/template/run.md` 到 `$work/run/run.md`
   - 内容: 说明执行 run 命令后如何运行和启动脚本；包含「执行前准备」「脚本清单与执行顺序」「执行约定」三节

3. **提示用户填入凭据**
   - 动作: 告知用户把密钥、token、账号等敏感信息写入 `$work/run/local/` 下的文件（如 `local/credentials.sh`、`local/.env`），脚本需要时从该目录读取，不得硬编码

## 模式 2：执行 run 流程

触发条件：`$work/run/run.md` 存在且用户未传 `init`。

1. **加载 run.md**
   - 动作: 读取 `$work/run/run.md` 的「脚本清单与执行顺序」表，解析每条脚本的路径、运行命令、依赖关系

2. **前置检查**
   - 动作: 确认清单中引用的脚本文件存在；确认 `run/local/` 下所需的凭据文件已就绪（缺失则提示用户补充，不臆造、不继续执行）

3. **按顺序执行脚本**
   - 动作: 按 run.md 清单顺序逐条执行；每条执行前向用户简述用途，执行后报告退出码与关键输出
   - 边界: 某条脚本退出码非 0 时停止后续步骤，报告失败原因，由用户决定修复后重跑或中止；需要人工介入的步骤等待用户确认

4. **回写状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage run next "<执行结果摘要>"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): workspace state <branch>"`，把初始化产生的 run.md、status.yaml 变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；`run/local/` 已被 .gitignore 排除，不会入库；执行模式下的运行日志不入库

## 后置完成检验

- 初始化模式:
  - [ ] `$work/run/run.md` 已生成，`$work/run/local/` 目录已创建
  - [ ] 已告知用户凭据写入 `run/local/`、不得硬编码
- 执行模式:
  - [ ] run.md 脚本清单已逐条执行，退出码与结果已报告
  - [ ] 失败脚本已停止后续步骤并告知用户
  - [ ] status.yaml 已同步（stage=run）

## 下一步建议

- 初始化后：在 `run/local/` 填入凭据、在 run.md 补充脚本清单，再执行 `run`
- 执行完成：回到 `test` 核对用例状态；脚本执行与否不阻塞主链路，用户可随时 `commit` / `merge`
