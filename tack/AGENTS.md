# AGENTS.md

本空间由 tack harness 驱动。

## 环境变量

- `$root` = tack 空间的根目录（本文件所在目录）
- `$work` = 当前正在进行的工作目录（`$root/space/<branch>/`）

## 加载 tack harness

检查大模型的上下文中是否已加载了 tack 的工作流和命令路由，如果没有加载，调用 `harness/script/scan-routes.sh`，扫描工作流和命令路由并加载到大模型的上下文中。用户没有明确指定技能时，默认都从 tack 的命令路由中选择。

- Windows（PowerShell；`$root` 替换为本空间实际路径，路径参数一律用正斜杠）：

  ```powershell
  powershell -ExecutionPolicy Bypass -File "$root\harness\script\run.ps1" scan-routes list "$root/harness"
  ```

- macOS / Linux：

  ```sh
  sh "$root/harness/script/scan-routes.sh" list "$root/harness"
  ```

版本检查不在会话加载时执行（避免与任务抢占）——挂载点为 `close` / `evolution` / `record` / `help` 命令收尾，见对应 cmd 文件。

## 命令路由

用户输入以 `/tack` 为可选前缀（可省略，也可直接用自然语言）。去掉开头的 `/tack`（含后续空格）后，按以下顺序解析：

1. **精确/模糊路由**：按上文脚本调用约定执行 `scan-routes resolve "$root/harness" "<输入>"`
   - 退出码 **0**（唯一命中）：按输出行前缀 `workflow|` / `cmd|` 定位文件并严格执行——cmd 执行其四段正文；workflow 按状态机引导对应命令
   - 退出码 **2**（多命中）：列出候选项让用户选择
   - 退出码 **1**（无命中）：进入语义识别
2. **语义识别**：执行 `scan-routes workflows "$root/harness"` 与 `scan-routes commands "$root/harness"` 取得全部触发词，与输入做语义匹配（中英文同义词、意图归类），挑出最可能的 1-3 条向用户确认；仍不明确时展示路由表让用户选择
3. **确认当前工作**：按核心约束第 5 条确认用户当前工作（`$work=$root/space/<branch>`），识别意图所属 workflow，按状态机引导命令

## 脚本调用约定（跨平台）

`harness/script/` 下的固定流程脚本均为 POSIX sh。本文档及 `harness/cmd/`、`harness/workflow/` 中出现的 `sh $root/harness/script/<name>.sh <args>`：

- **Windows 上一律改执行为**：`powershell -ExecutionPolicy Bypass -File "$root\harness\script\run.ps1" <name> <args>`
  - `run.ps1` 自动定位 Git for Windows 的 bash.exe（未安装时首次运行自动通过 winget 安装 Git for Windows）、归一化路径参数并透传退出码
  - 必须带 `-ExecutionPolicy Bypass`（Windows 默认执行策略禁止运行 .ps1）；所有路径参数使用正斜杠（如 `D:/Code/AI/my-project`），禁止反斜杠
- macOS / Linux 直接按文档中的 `sh` 命令执行
- Windows 上执行任意 shell 命令与创建文件的更多纪律（多行脚本、here-string、GNU 工具路径、LF 换行约定）见 `harness/rule/windows-env.md`

## tack harness 核心约束

1. 必须用中文思考和回答
2. 所有输入输出必须有事实来源和事实依据，禁止随意编造
3. 尊重用户本地改动，每次需要用到本地文件时，重新读取，不要相信大模型的上下文
4. **多个子任务能并行时尽量并行执行**：拆解出的子任务/工具调用之间无依赖时，在同一轮次内并行发出（如多个文件的新建/修改、多个独立检索）；有依赖的按依赖顺序串行，前序完成后再执行
5. **收到用户指令后，先确认是否为base指令，如果是则直接执行，否则确认用户当前在进行哪项工作，必须明确，如果不明确，先向用户确认。然后识别用户在进行哪个类型的 workflow，按照 workflow 进行状态流转和命令引导**
6. **Git 双层边界——空间仓库框架托管，用户只操作工作区代码仓库**：
   - `$root` 空间根仓库（保存 harness/、wiki/、AGENTS.md、space/ 下的工作文档）的 Git 操作**全部由框架自动完成**（初始化首次提交、各命令阶段末经 `harness/script/space.sh commit` 自动提交），**不引导、不要求用户对 `$root` 执行任何 git 命令**
   - 用户的 Git 操作（fetch/commit/push/merge/solve）只作用于 `$work/repo/<repo-name>/` 工作区代码仓库，且需人工确认；worktree 的创建/移除也由框架脚本自动完成
   - `.gitignore` 已排除 `repo/` 与 `space/*/repo/`，代码仓库内容与空间仓库互不串扰
7. 每个任务/环节执行结束后，凡用户对 AI 的做法有过引导、纠偏、补充约定，自动把原始事实追加到 `$work/status.yaml` 的 `guidance` 列表（采集时机与固化时机见第 11 条）；用户要求立即沉淀时走 `record`
8. **耗时较长任务完成后的主动沉淀预判**：除第 7 条（用户引导触发）与第 10 条（改 cmd 文件触发）外，凡耗时较长的任务（多步骤、跨文件、多轮试错）完成前，AI 主动做一次沉淀预判——本次是否暴露了可复用的操作模式、可固化的机械流程、或值得入 `wiki/`、`decisions/` 的事实？预判结果**不直接改动 harness**，而是作为 `guidance` 原始记录追加到 `$work/status.yaml`（标注建议固化点：cmd/workflow/rule/script/wiki），由第 11 条的 close 自进化审查统一消化。固化门槛同第 10 条：只有"未来会以同样方式重复"的机械步骤才提炼为 `harness/script/` 脚本，一次性操作不固化
9. 用户主动要求记录或记忆时，使用 record 命令进行记录
10. **每次优化 `harness/cmd/` 指令文件时，必须同步检查其中是否有固定、可重复的流程可提炼为 `harness/script/` 脚本**：发现机械性固定步骤（确定性的文件操作、状态流转、格式转换、校验等）应沉淀为脚本，并将指令文件中的手工步骤替换为脚本调用；也可运行 `evolution` 命令做专项审查。指令文件只保留意图、判断与决策，不堆叠应由脚本固化的流程
11. **harness 的更新时机（手动更新 + 自进化）**：
   - **手动更新**：用户明确要求记录/沉淀某个技能时走 `record`（更新优化 cmd/workflow/rule/wiki 或本文件常驻约定）；用户手动发起 harness 优化时走 `evolution`
   - **自动采集**：每个任务/环节结束时，凡用户对 AI 的做法有过引导、纠偏、补充约定，自动向 `$work/status.yaml` 的 `guidance` 列表追加一条原始记录（无需用户要求；只记事实与建议固化点，**不直接改动 harness**）。记录格式与字段见 `harness/template/work-status.yaml`
   - **自动固化**：执行 `close` 关闭工作区时自动触发一次自进化审查——把 `guidance` 中 `raw` 条目的可复用操作习惯固化到 workflow/cmd/rule（先扫描、能融合则融合），经用户确认后落盘并将条目置 `distilled`；未消化完的 raw 条目不阻塞关闭。用户也可随时手动执行 `evolution` 或 `record` 提前固化
12. **markdown 引用可定位**：生成 markdown 文件时，引用文件或代码一律采用 GitHub 风格的可定位行数锚点格式（如 `path/to/file.md#L12-L15`），读者可直接跳到对应行，禁止只给文件名或"某行附近"式模糊指向

## 目录概览

| 目录/文件 | 作用 |
|-----------|------|
| `AGENTS.md` | 本文件：驱动说明、核心约束、项目信息 |
| `harness/cmd/` | 命令入口（base/dev/git 分组），定义准入准出 |
| `harness/agents/` | 可委派角色（code-explorer / code-architect / code-reviewer）：被 cmd 引用后经 Task 子代理在独立上下文执行，可多实例并行；只供发现与委派，不参与命令路由 |
| `harness/workflow/` | 工作流状态机（development/testing/bugfix/merge-conflict/branch-op） |
| `harness/script/` | 固定流程脚本（init-tack、space、scan-routes、lint-harness、scan-secrets、check-guidance、work-status、project、repo、work、git-worktree-helper、branch-op、skill-update、check-update；Windows 统一经 `run.ps1` 启动器调用） |
| `harness/rule/` | 业务、代码与安全规则（coding-standards、security、git-boundary、context-loading、windows-env、record-* 等；不参与路由，按需加载） |
| `harness/template/` | 命令/工作流/文档/工作区模板 |
| `harness/reference/` | 通用方法论与复杂独立能力（随 harness 分发、不接受项目级沉淀，项目做法归 rule/wiki；须被 cmd/workflow/agents/rule 引用后才加载，不参与路由） |
| `wiki/` | 公共知识：业务背景、代码导航锚点（术语→代码入口、接口→场景）、服务清单与代码外事实、技术决策与工程约定（decisions）；条目带来源、矛盾保留演变；不记易变代码逻辑（人工可读写，AI 蒸馏内容须人工审阅） |
| `space/<branch>/` | 每个工作的工作区（status.yaml、input.md、spec/plan/tech-design、wiki/、repo worktree） |
| `repo/` | 代码主仓库（只保留一份，只读基准；worktree 用到哪个仓库再从这里获取） |

## 沉淀约定

> 由 `/tack record` 沉淀的项目级常驻约定，人工审阅后生效；更新时优先与已有条目融合，不重复追加。
> 项目信息 YAML 区块由 project.sh 维护，请勿手改。
> 本区块尚无条目；使用「记录/沉淀：……」可把每次会话都必须遵守的约定沉淀到这里。

## 项目信息

> 以下 YAML 区块由 `harness/script/project.sh` 维护（`init`、`work`、`close` 时自动更新）；可手工查阅，keywords、service_repo_mapping 等结构化内容由 init 命令经人工确认后编辑。区块边界标记请勿删除。

<!-- tack:info:start -->
skill_version: ""
skill_update_url: "https://github.com/frcoder-lh/tack-harness"
skill_trigger: "tack"
project:
  name: ""
  keywords:
    - ""
  description: ""
  root_path: ""
  repo_scan_path: []
  service_repo_mapping: []
work: []
<!-- tack:info:end -->
