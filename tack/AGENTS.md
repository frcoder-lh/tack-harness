# AGENTS.md

本空间由 tack harness 驱动  
Github：https://github.com/frcoder-lh/tack-harness

## 环境变量

- `$root` = tack 空间的根目录（本文件所在目录）
- `$work` = 当前会话正在处理的工作区目录（`$root/space/<workspace>/`）
- `$project` = `$work` 所属项目名（`$work/status.yaml` 的 `project` 字段值）
- `$workflow` = `$work` 所属任务名（`$work/status.yaml` 的 `workflow` 字段值）

## 脚本调用约定
本空间下的脚本均为 POSIX sh。文档中的 `sh $root/harness/script/<name>.sh <args>`：
- macOS / Linux：直接执行。
- Windows：一律改为 `powershell -ExecutionPolicy Bypass -File "$root\harness\script\run.ps1" <name> <args>`；路径参数用正斜杠。安装、路径转换、换行与工具定位等细节见 `harness/rule/windows-env.md`。

## 命令路由（按需加载）

入口只有命令：`harness/cmd/` 的 cmd 是唯一触发入口；`harness/workflow/` 是工作区流转的状态机，由命令或语义识别后写入 `$work/status.yaml`，用于辅助长任务推进、引导下一步或为自动完成提供路径。工作区可以没有工作流；无法识别意图或没有对应工作流时，由用户自行执行指令。

用户输入以 `/tack` 为可选前缀。会话启动时只识别空间位置，收到请求后再解析路由：
1. 去掉 `/tack` 前缀，执行 `scan-routes resolve "$root/harness" "<输入>"`。带参数的命令先按命令前缀精确匹配，参数原文完整保留；显式命令命中后不再按意图重新路由。
   - 退出码 **0**（唯一命中）：按输出行前缀 `cmd|` / `workflow|` 定位文件——cmd 直接执行其四段正文，不再执行 `index` / `list`；workflow 只按状态机引导，不当作触发入口。注入内容已含指令正文或索引时直接复用。
   - 退出码 **2**（多命中）：列出候选项让用户选择。
   - 退出码 **1**（无命中）：进入语义识别。
2. **语义识别**：执行 `scan-routes index "$root/harness"` 取得紧凑索引（名称、简写、触发词、短描述、路径），与输入做语义匹配，挑最可能的 1-3 条向用户确认；仍不明确时列候选让用户选择；与 tack 工作流无关的请求直接正常回答。
3. **确认工作区与项目**（见「工作区与项目确认」），识别意图所属 workflow 并按状态机引导。

缓存：上下文已有命令正文或紧凑索引时直接复用，不重复读取；用户提示文件已改动或进入新的修改阶段时重新读取。用户请求帮助时，用 `scan-routes list "$root/harness"` 展示完整路由表。

## AGENT 核心约束

- 用中文思考和回答；所有输入输出必须有事实来源，禁止编造。
- **文件读取纪律**：首次使用某本地文件前读取相关片段；同一连续操作中复用最新读取或编辑结果；用户提示外部改动、文件版本变化或进入新的修改阶段时，重新读取相关片段。细则见 `harness/rule/context-loading.md`。
- **并行**：无依赖的子任务与工具调用在同一轮并行发出；有依赖的按顺序串行。
- **省往返、省上下文**：先 grep/glob 定位再只读命中片段；list/扫描/日志类输出先在 shell 侧裁剪；同一文件多处关联改动先列映射再整块替换；删除/归档/重命名类需求先确认关联面再动手。
- **引用按名称**：规则、流程、约束一律用稳定名称引用（如「工作区与项目确认」「沉淀生命周期」），不使用「第 N 条」式编号。
- **可定位引用**：markdown 中引用文件或代码用 `path/to/file.md#L12-L15`，不写「某行附近」式模糊指向。
- **反向描述不保留**：事实一旦被移除且没有必须阻止该行为的意图，直接删除相关描述；否定表述只用于真实禁令。删除前确认无文档引用、脚本调用等真实消费者，并同步清理失效引用。
- **命名**：目录、文件、分支、函数、变量、命令与工作流命名前先读 `harness/rule/naming.md`。

## tack harness 核心约束

- **工作区与项目确认**：收到指令后先判断是否 base 组命令（`help` / `init` / `work` / `repo` / `record` / `update` / `study` / `evolution`），是则直接执行；否则需要确认当前工作区与项目，必须明确`$work`、`$project`、`$workflow`。确认后识别用户在进行哪个 workflow，按状态机引导。
- **Git 双层边界**：`$root` 空间仓库的 Git 操作全部由框架脚本完成，不引导、不要求用户对 `$root` 执行 git；用户 Git 操作只作用于 `$work/repo/<repo-name>/` 代码仓库，由用户主动发起命令触发；`commit` 生成提交信息后直接提交并如实汇报，`push` 等影响远端的操作需用户明确指令。细则见 `harness/rule/git-boundary.md`。
- **知识落点分层**：可复用能力进 `harness/`；项目级代码外事实进 `$root/wiki/<project>/`（写入按 `harness/rule/wiki-write.md`，读取按 `harness/rule/wiki-read.md`）；工作区级参数进 `$work/status.yaml`。项目知识只读写当前项目，不跨项目取用。
- **沉淀的生命周期（guidance 采集规则）**：
  - **触发条件**：每个任务/环节结束时，如果任务耗时较长，或经过用户多次引导才完成，则触发沉淀；修改 `harness/cmd/` 时，如果有可固化的脚本，则触发沉淀。
  - **原始记录**：把用户引导、纠偏、补充约定作为 `guidance` 追加到 `$work/status.yaml`，只记事实与建议固化点，不直接改动 harness；字段见 `harness/template/work-status.yaml`。
  - **固化入口**：`record`（用户主动沉淀）、`close` 收尾自审（消费 pending）、`evolution`（专项审查）。细则见 `harness/rule/record-lifecycle.md`。

## 数据来源

| 数据 | 来源 | 读取方式 |
|------|------|----------|
| 空间版本、项目、服务仓库映射、工作区登记 | `$root/tack.yaml` | `project.sh space-info / project-get / repo-list / work-list / work-get`，按目标范围读取 |
| 工作区状态与进展 | `$work/status.yaml` | 直接读取，或经 `work-status.sh` 回写 |
| 实际目录 | 文件系统 | `$root/space/<workspace>/` 等 |
| 实时分支与仓库状态 | Git | `git -C <repo>` 或框架脚本 |

- 登记查询只取目标范围：项目/工作区不明确时才读简短列表，仓库查询必须带项目名。

## 目录概览

| 目录/文件 | 作用 |
|-----------|------|
| `AGENTS.md` | 本文件：常驻入口（路由、约束、数据来源） |
| `tack.yaml` | 空间登记：版本、项目、服务仓库映射、工作区 |
| `harness/cmd/` | 命令入口（唯一触发入口），定义准入准出 |
| `harness/workflow/` | 工作区流转状态机，辅助长任务推进 |
| `harness/agents/` | 可委派角色，供发现与委派，不参与路由 |
| `harness/script/` | 固定流程脚本（清单见 `harness/rule/script-catalog.md`） |
| `harness/script/hook/` | 可选 Hook 加速层（见 `harness/rule/hooks.md`） |
| `harness/rule/` | 业务、代码与安全规则，按需加载 |
| `harness/template/` | 命令、工作流与文档模板 |
| `harness/reference/` | 通用方法论与复杂独立能力，被引用时才加载 |
| `wiki/<project>/` | 项目知识（分类与组织见 `harness/rule/wiki-write.md`） |
| `space/<workspace>/` | 工作区（内部布局见 `harness/rule/workspace-layout.md`） |
| `repo/` | 代码主仓库，只读基准 |
| `.tack/` | 框架本地运行时数据（日志、备份、临时文件、状态），不入库 |
