---
command: run
short: rn
triggers: 运行, 执行, 跑脚本, 执行脚本, run, execute, run script
params: [指令名或模式（可选：init 显式初始化；默认自动判断）]
summary: 按需命令（非开发必经环节，用户需要时触发）——run 指令管理：无 run/ 时初始化索引（run/run.md），按用户描述新增指令目录（run/<指令>/：run.md + 脚本 + 数据 + local/），执行时按索引识别、校验并编排执行；敏感数据落各指令目录的 local/
---

# run 指令管理（按需命令）

> **按需触发，不是 development 主链路的必经环节**：仅当用户主动要求执行脚本（或 `test` 方案需要脚本）时运行；不执行不阻塞提交与合并。
> `run/run.md` 只负责指令的识别、索引与编排；每条指令的步骤、脚本清单与凭据要求记录在 `run/<指令>/run.md`。
> 三种模式自动判断：`$work/run/` 不存在或用户显式传 `init` → 初始化；用户描述新增/修改一条指令 → 新增或更新指令；其余 → 按索引识别并执行。

## 前置准入条件

- 已确定当前工作区 `$work`
- 执行模式下 `$work/run/run.md` 存在且指令索引非空

## 不适用场景

- 只生成测试方案、不实际运行脚本 → 走 `test`
- 编译/运行被测代码本身（属于 `code` 的构建验证）→ 走 `code` 内部流程

## 模式 1：初始化 run/ 索引

触发条件：`$work/run/` 不存在，或用户显式传 `init`。

1. **创建索引骨架**
   - 动作: 创建 `$work/run/`，复制 `harness/template/run.md` 到 `$work/run/run.md`
   - 内容: 索引文件只含「指令索引」「识别规则」「编排规则」「新增指令」四节，不写具体指令的脚本与命令

2. **说明目录约定**
   - 动作: 告知用户每条指令落 `$work/run/<指令>/`（脚本与数据），该指令的密钥、token、账号写入 `$work/run/<指令>/local/`（已被 .gitignore 忽略、不入库，落位规则见 `harness/rule/security.md`「工作区凭据落位」）

3. **衔接新增指令**
   - 判定: 用户已描述具体执行流程 → 继续模式 2；未描述 → 说明下一步需要提供指令后结束

## 模式 2：新增或更新指令

触发条件：用户要求新增、编写或修改一条 run 指令。

1. **明确指令名与用途**
   - 动作: 从用户描述确定指令名（目录名用小写 kebab-case）、触发词与用途；描述宽泛时先澄清边界，不带着模糊目的建目录

2. **创建指令目录与说明**
   - 动作: 创建 `$work/run/<指令>/` 与 `$work/run/<指令>/local/`；`<指令>/run.md` 不存在时复制 `harness/template/run-instruction.md`；脚本与数据一律放在 `<指令>/` 内，不散落到 `run/` 根目录

3. **填写执行清单**
   - 动作: 在 `<指令>/run.md` 填写「脚本清单与执行顺序」表与「机器可读清单（run-plan）」区块；`script` 与 `requires` 使用相对 `<指令>/` 的路径，必需凭据写进 `requires`（如 `local/credentials.sh`）
   - 边界: 凭据只落 `<指令>/local/`，脚本从该目录读取，不得硬编码

4. **登记索引**
   - 动作: 在 `$work/run/run.md`「指令索引」表登记指令名、目录、触发词、用途与依赖；已有同名指令时就地更新，不重复追加

5. **校验**
   - 动作: 执行 `sh $root/harness/script/run-plan.sh check $work/run/<指令>`：
     - 退出码 0：清单结构、脚本文件、依赖顺序与 `requires` 文件均有效
     - 退出码 3：缺少机器可读清单区块——按 `harness/template/run-instruction.md` 补齐后重试
     - 退出码 4：按 `ERROR<TAB>code<TAB>seq<TAB>detail` 修复清单（缺脚本/缺 local 文件/依赖顺序非法等），不得跳过
     - 退出码 1/2：目录或用法错误，修正后重试

6. **提示用户填入凭据**
   - 动作: 告知用户把该指令的密钥、token、账号写入 `$work/run/<指令>/local/` 下的文件

## 模式 3：识别并执行指令

触发条件：`$work/run/run.md` 存在且用户未传 `init`、未要求新增/修改指令。

1. **识别目标指令**
   - 动作: 读取 `$work/run/run.md` 的「指令索引」与「识别规则」，按用户输入（指令名、触发词或用途）匹配目标指令；用户指定多个时按「依赖」列排序
   - 未命中或多命中: 列出索引请用户选择，不臆造指令

2. **前置检查**
   - 动作: 对每条目标指令读取其 `run.md`，执行 `sh $root/harness/script/run-plan.sh check $work/run/<指令>`（退出码含义同模式 2 第 5 步），并确认 `requires` 列出的凭据文件已就绪（缺失则提示用户补充，不臆造、不继续执行）

3. **按编排顺序执行**
   - 动作: 按「依赖」顺序逐条执行各指令的机器可读清单；每条脚本执行前向用户简述用途，执行后报告退出码与关键输出
   - 边界: 某条脚本退出码非 0 时停止后续脚本与后续指令，报告失败原因，由用户决定修复后重跑或中止；需要人工介入的步骤等待用户确认

4. **回写状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set stage run progress.run true next "<执行结果摘要>"`（初始化与新增指令模式不置 `progress.run`）

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): workspace state <branch>"`，把 `run/run.md`、各指令目录下的说明与脚本、status.yaml 变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；`run/<指令>/local/` 已被 .gitignore 排除，不会入库；执行模式下的运行日志不入库

## 后置完成检验

- 初始化模式:
  - [ ] `$work/run/run.md` 已按索引模板生成，未记录具体指令细节
  - [ ] 已说明指令目录与 `<指令>/local/` 的凭据落位
- 新增/更新指令模式:
  - [ ] `$work/run/<指令>/` 与其 `local/` 已创建，`run.md`、脚本与数据均在该目录内
  - [ ] `run-plan.sh check $work/run/<指令>` 退出码 0
  - [ ] 索引表已登记（或更新）该指令的目录、触发词、用途与依赖
  - [ ] 已告知用户凭据写入 `<指令>/local/`、不得硬编码
- 执行模式:
  - [ ] 目标指令按索引识别；未命中或多命中时已交由用户选择
  - [ ] 每条目标指令 `run-plan.sh check` 退出码 0，`requires` 文件已就绪
  - [ ] 各指令已按依赖顺序执行，退出码与结果已报告
  - [ ] 失败时已停止后续脚本与指令并告知用户
  - [ ] status.yaml 已同步（stage=run、progress.run=true）

## 下一步建议

- 初始化后：提供一条指令的描述新增指令，再执行 `run`
- 新增指令后：在 `<指令>/local/` 填入凭据、补齐脚本清单，再执行 `run`
- 执行完成：回到 `test` 核对用例状态；脚本执行与否不阻塞主链路，用户可随时 `commit` / `merge`
