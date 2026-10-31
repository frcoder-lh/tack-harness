---
command: init
short: i
triggers: 初始化, 初始化项目, init, 接入仓库, 整理文档, 项目信息, 登记服务, 接入代码, 添加仓库, initialize, init project, connect repo, organize docs, project info, register service, add repository
params: [内容（可选：项目描述 / git地址 / 本地路径 / 业务文档 / 服务映射）]
summary: 初始化项目上下文——先确定目标项目，再自动识别输入内容类型（项目信息/业务文档/git仓库/服务映射）并分类处理，AI 仅整理格式不篡改内容，按「索引 + 小文件」物化到 wiki/<project>/ 的分类文件与索引并写入 tack.yaml 空间登记
---

# init 初始化全局上下文

> tack 骨架（AGENTS.md、harness/、wiki/、space/ 等）已由 skill 调用 `harness/script/init-tack.sh` 复制完成；
> Git 可用性由调用链保证：Windows 由启动器 `run.ps1` 定位 Git for Windows 的 bash.exe（缺失时经 winget 自动安装）后再执行脚本；Linux / macOS 由 `init-tack.sh` 自身确保（缺失时分别经系统包管理器 / Homebrew 安装）。
> `init-tack.sh` 同时把 `$root` 初始化为 Git 仓库、由框架自动完成首次提交（已存在 `.git` 时跳过；空间仓库的 Git 操作全程框架自动，用户不直接操作）。
> 本命令负责收集**当前项目**的上下文并物化为 `wiki/<project>/` 公共知识，同时把结构化项目信息写入 `$root/tack.yaml` 空间登记、把代码仓库接入 `$root/repo/`。
> **首次初始化与后续补充都走本命令**：首次执行时 AI 主动询问用户补全项目 wiki；后续携带新材料（仓库/文档/映射）再次执行时只追加融合当前项目，不覆盖已有内容。
> 一个 tack 空间可登记多个项目：输入指向新项目时新建项目条目，指向已有项目时补充该项目 wiki。
>
> **核心原则**：AI 只做格式整理与归类，不篡改、不概括、不补充用户未提供的内容；用户提供的原始信息必须完整保留。

## 前置准入条件

- 目标目录已完成骨架复制（存在 `$root/AGENTS.md` 与 `$root/harness/`）

## 指令内容

### 0. 确定目标项目并自动分类处理（首选）

**先确定本次 init 的目标项目，再做内容分类**——项目级知识必须落到正确的 `wiki/<project>/`。

- 输入: 用户输入中的项目名/业务线线索、当前 `$work`、`tack.yaml` 的 projects（`project.sh project-list`）
- 动作:
  0. 先执行 `sh $root/harness/script/project.sh ensure $root`（幂等；区块缺失时补齐，后续项目操作才有落点）
  1. 有 `$work` 且 `$work/status.yaml` 的 `project` 非空：默认以该项目为目标，向用户确认
  2. 否则执行 `sh $root/harness/script/project.sh project-list $root`：
     - 只有一个项目：展示并请用户确认
     - 多个项目：列出 `name` 与 description，请用户选择
     - 没有项目：请用户提供项目名称（英文 slug）与一句话描述，执行
       `sh $root/harness/script/project.sh project-add $root "<name>" "<描述>"`
  3. 用户输入明确指向新项目（与已有项目名称/描述均不匹配）时，按上一条新建项目
- 边界: 不得自行编造项目名；项目确定前不写 `wiki/` 与 `tack.yaml`；项目确定后确保 `$root/wiki/<project>/` 存在（`project-add` 已创建，已有条目但目录缺失时 `mkdir -p`）

确定项目后，用户执行 `init` 时可能直接附带内容（参数或对话中的文本/链接/路径）。**对输入内容做类型识别，按类型自动分派处理，不要无脑走逐步引导**。

按以下规则识别内容类型（一段输入可同时包含多种类型，分别处理）：

| 内容特征 | 类型 | 处理动作 |
|----------|------|----------|
| `git@` 开头、`http(s)://` 且含 `.git`、以 `.git` 结尾 | git 远端仓库 | → 第 4 步「接入代码仓库」的远端克隆分支 |
| 本地绝对/相对路径，且该路径下存在 `.git` 目录 | git 本地仓库 | → 第 4 步「接入代码仓库」的本地软链分支 |
| 一句话/多段描述项目、业务线、目标用户、市场定位 | 项目整体信息 | → 第 2 步 |
| PRD、设计文档、业务说明、新人 landing、架构图等文档正文或链接 | 业务文档/知识 | → 第 3 步 |
| 含「服务名 + 仓库」等映射信息 | 服务与仓库映射 | → 第 5 步 |
| 无法识别或内容为空 | — | 进入第 1 步后，按 2→3→4→5 顺序逐步引导用户补充 |

识别后直接跳转到对应步骤执行，**已识别的类型不再重复询问**；执行完所有识别到的类型后，进入第 6 步整理物化。

### 1. 确认空间登记

- 动作: 第 0 步已执行 `project.sh ensure`；此处只需确认 `tack.yaml` 的 `projects` 字段存在（缺失时重新执行 ensure）

### 2. 收集项目整体信息

- 输入: 用户用自然语言描述项目（一句话或多段均可），可补充业务线、目标用户、市场定位
- 动作:
  - 提炼项目名称（英文 slug，如 `user-center`）、关键词（3-8 个）、一句话描述；名称与文件名命名遵守 `harness/rule/naming.md`
  - 向用户确认提炼结果，允许修改
- 落盘:
  - 项目条目不存在时先新建：`sh $root/harness/script/project.sh project-add $root "<名称>" "<描述>"`
  - 标量执行脚本写入：`sh $root/harness/script/project.sh project-set $root "<名称>" description "<描述>"`、`project-set $root "<名称>" root_path "<项目根路径>"`
  - 结构化字段 `projects[].keywords` 经用户确认后执行 `sh $root/harness/script/project.sh project-keywords $root "<名称>" "<kw1,kw2,...>"` 写入

### 3. 收集业务文档与全局上下文

- 输入: 用户提供以下任意形式的资料（可分批粘贴，也可给链接让 AI 抓取摘要）：
  - 业务线信息（业务范围、目标用户、核心业务、市场定位）
  - 新人 landing 文档（上手指引、团队约定、常用链接）
  - 项目整体信息（发起原因、要解决的问题、预期目标）
  - 相关 PRD、设计文档、架构图链接
- 动作:
  - 对每段资料标注来源（用户口述 / 文档链接 / 粘贴文本）
  - **不做内容改写**，只做归类、去重（完全重复的段落）、格式整理（标题层级、列表、表格）
  - 信息缺口直接列出「待补充」项向用户询问，不臆造

### 4. 接入代码仓库

- **远端仓库**：
  1. 从输入中提取 git 地址（`git@...`、`https://...git` 等）
  2. 执行 `sh $root/harness/script/repo.sh clone $root <git地址...>`，克隆到 `$root/repo/`
- **本地仓库**：
  1. 从输入中提取本地路径，确认该路径含 `.git`
  2. 执行 `sh $root/harness/script/repo.sh link $root <路径...>`，软链到 `$root/repo/`
- **批量扫描**（用户给出扫描目录而非具体仓库路径时）：
  1. 执行 `sh $root/harness/script/repo.sh scan $root <扫描目录>`（深度 ≤ 5）
  2. 列出扫描到的仓库，由用户勾选确认
  3. 执行 `repo.sh link` 软链已选仓库
- 多种方式可混用，循环直到用户确认没有更多仓库

### 5. 建立服务与仓库映射

- 输入: 已接入的仓库列表 + 用户补充的服务信息
- 动作: 对每个仓库，向用户确认（输入中已包含的不重复询问）：
  - 服务名称（如 `用户服务`）
  - 对应代码仓库（已接入的 repo 名）
  - 服务职责简述（可为空）——代码外信息，不进 YAML，随第 6 步 `wiki/<project>/config/services.md` 物化
- 落盘:
  - 每个仓库执行一次 `sh $root/harness/script/project.sh project-service-repo $root "<项目名>" "<服务名称>" "<repo 名>" "<repo_git，无则空串>" "<repo_path>"` 追加当前项目的映射（每条**仅含服务↔仓库映射字段**：service_name / repo_name / repo_git / repo_path）
  - 服务职责等代码外信息不进 YAML，在第 6 步物化到 `wiki/<project>/config/services.md`
  - `projects[].repo_scan_path` 记录本地扫描目录（无脚本接口，直接编辑 `tack.yaml` 对应项目条目该字段）
  - 提示用户人工审阅补全

### 6. AI 按事实物化到 wiki/<project>/（有内容才生成，不造空文件）

> 项目目录由第 0 步的 `project-add` 创建（或已存在）。**文件只在具备真实事实时按 `harness/template/` 对应模板物化到 `$root/wiki/<project>/`**；
> 组织方式（索引 + 小文件）、分类、写入与索引更新统一遵守 `harness/rule/wiki-write.md`；已存在的文件不覆盖，追加对应小节或让用户确认合并方式。绝不允许编造内容填充。
> 首次物化某分类内容时，一并创建该分类目录、`<分类>/index.md` 与项目总索引 `index.md`，并按 `wiki-write.md` 的索引写法登记。

| 目标文件 | 结构模板 | 物化条件 |
|----------|----------|----------|
| `wiki/<project>/index.md` | `harness/template/wiki-index.md` | 首次物化任一分类时创建，登记已创建的分类 |
| `wiki/<project>/<分类>/index.md` | `harness/template/wiki-category-index.md` | 首次物化该分类内容时创建 |
| `wiki/<project>/config/services.md` | `harness/template/wiki-config-services.md` | 当前项目已接入 ≥1 个仓库 |
| `wiki/<project>/config/env.md` | `harness/template/wiki-config-env.md` | 用户提供了部署环境、泳道、网关/发布地址等事实 |
| `wiki/<project>/config/accounts.md` | `harness/template/wiki-config-accounts.md` | 用户提供了租户、角色或账号申请方式等事实 |
| `wiki/<project>/config/settings.md` | `harness/template/wiki-config-settings.md` | 用户提供了关键配置或中间件/平台事实 |
| `wiki/<project>/code/repos.md` | `harness/template/wiki-code-repos.md` | 当前项目已接入 ≥1 个仓库 |
| `wiki/<project>/code/anchors.md` | `harness/template/wiki-code-anchors.md` | 有真实术语→代码入口锚点（init 通常不造，由 `ask` 提炼、`record` 沉淀） |
| `wiki/<project>/code/interfaces.md` | `harness/template/wiki-code-interfaces.md` | 有非显然的接口→业务场景映射 |
| `wiki/<project>/biz/background.md` | `harness/template/wiki-biz-background.md` | 用户提供了任何业务资料（项目描述、业务文档、背景信息等） |
| `wiki/<project>/biz/glossary.md` | `harness/template/wiki-biz-glossary.md` | 用户提供的业务资料中包含术语/概念定义 |
| `wiki/<project>/biz/domains.md` | `harness/template/wiki-biz-domains.md` | 用户提供的业务资料中包含按业务领域的职责与边界 |
| `wiki/<project>/rule/decisions.md` | `harness/template/wiki-rule-decisions.md` | 用户当场提供了明确的技术决策资料（历史 ADR 等）；**常规初始化不造本文件**——决策主要在后续 `close`/`record` 从工作区 plan 决策记录沉淀、`ask` 从 git history 发现候选 |
| `wiki/<project>/rule/conventions.md` | `harness/template/wiki-rule-conventions.md` | 用户当场提供了明确的工程约定（团队约定文档等） |

- **`config/services.md`**：从 `tack.yaml` 当前项目条目的 `service_repo_mapping` 渲染——服务总览表与服务详情中的服务名、仓库、git 地址直接填真实行；
  服务职责、负责团队、权威文档取自第 5 步用户提供的信息（**不经过 mapping**），缺失标「待补充」；
  外部依赖与协作契约用户提供则记录，无则标「待补充」，只记跨团队依赖、不记代码可分析的普通调用链
- **`config/env.md` / `config/accounts.md` / `config/settings.md`**：仅在用户提供了对应事实时填真实条目，各表带权威事实源、负责人、最近核验、复核条件；
  整类无内容则不生成该文件；**禁止写入密码、密钥、token 等凭据明文**（只记录获取方式）
- **`code/repos.md`**：仓库概览表由脚本从当前项目的 `service_repo_mapping` 渲染真实行（主要语言/框架未知可留空，不臆测，不作为人工维护内容）
- **`code/anchors.md` / `code/interfaces.md`**：初始为空——init 不臆造锚点，由后续 `ask` 提炼候选、`record` 沉淀（人工审阅后生效）；接口表只记非显然映射，不建完整 API 清单
- **`biz/background.md`**：业务线概述（含业务范围与非业务范围）、只记录长期背景的项目背景、业务状态与不变量、相关文档、来源资料索引
- **`biz/glossary.md`**：术语 | 标准定义 | 别名/旧称 | 边界与反例 | 来源 | 最近确认；只放业务释义，术语到检索关键词/代码入口的锚点放 `code/anchors.md`
- **`biz/domains.md`**：按业务领域（而非技术服务）组织，说明每个领域负责什么、不负责什么、核心对象、业务不变量、上下游关系
- **`rule/decisions.md` / `rule/conventions.md`**：仅当用户当场提供了历史技术决策/工程约定资料时，按模板结构物化并标注来源（资料链接或「用户口述 <日期>」）；
  用户未提供则**不生成**，不得从代码结构臆测选型原因
- 条件不满足时**不生成文件**，向用户说明「提供对应信息后即可创建」；用户后续可用 `init` 补充或 `record` 沉淀

各文件只整理用户提供的信息与已登记的结构化事实，不臆测技术栈、依赖或业务规则；
**wiki 不记录代码实现逻辑、调用链等易变内容**（代码以代码本身为唯一真源，临期分析放各工作区的 `$work/doc/analysis/` 与 `story/*/analysis.md`）。

### 7. 主动询问补全与人工审阅

- **首次初始化该项目**（`wiki/<project>/` 由本次首次物化）：
  - 动作: 对照已物化内容列出「待补充」清单（如各服务职责、环境与中间件事实、租户/账号获取方式、业务背景资料等），**主动询问用户现在能否补全**
  - 用户当场能提供的：按本文件边界补充并融合进对应项目 wiki 文件；暂时没有的保留「待补充」，不反复催逼
- **后续补充执行 init**：只处理当前项目新材料的追加融合，已有内容不重复询问
- 动作: 展示本次物化/更新的 `wiki/<project>/` 文件（如有）与 `tack.yaml` 当前项目条目，提示用户审阅
- 用户可直接修改文件；修改后无需重新执行 init

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): init global context"`，把本次物化的 wiki/、AGENTS.md 项目信息等空间变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；代码仓库接入（clone/link）不属于空间提交内容（`repo/` 已被忽略）

## 后置完成检验

- [ ] `$root` 已是 Git 仓库（存在 `$root/.git`，`git -C "$root" status` 可执行；初始化脚本自动完成）
- [ ] `$root/repo/` 下每个条目都可进入并执行 `git status`
- [ ] 已确定目标项目：`tack.yaml` 的 `projects` 中存在同名条目，且本次只写入该项目的结构与 wiki
- [ ] 当前项目的名称、关键词、描述已填写
- [ ] 当前项目的 `service_repo_mapping` 已记录全部已接入仓库，并经用户审阅
- [ ] 已接入仓库时，`wiki/<project>/config/services.md`、`wiki/<project>/code/repos.md` 已按模板生成且含真实仓库行；未接入时二者不存在，项目目录中没有空壳文件
- [ ] 用户提供了业务资料时，`wiki/<project>/biz/background.md`（含术语时 `biz/glossary.md`、含领域时 `biz/domains.md`）已生成；未提供时这些文件不存在
- [ ] 用户提供了历史决策/约定资料时，`wiki/<project>/rule/decisions.md` / `rule/conventions.md` 已按模板生成且带来源；未提供时这些文件不存在（常规初始化不造）
- [ ] 新建文件已按 `harness/rule/wiki-write.md` 登记到对应分类索引与项目总索引；`sh $root/harness/script/wiki-index.sh check $root <project>` 退出码为 0
- [ ] 用户提供的原始信息已整理入项目 wiki，或以来源资料索引登记，未被篡改或遗漏
- [ ] 项目 wiki 只含代码外事实、导航锚点、业务背景与带来源的决策约定，未记录代码实现逻辑/调用链，未写入凭据明文
- [ ] 首次初始化该项目时已主动询问用户补全 wiki（「待补充」清单已呈现）；后续补充时只追加融合
- [ ] AGENTS.md 未被改动；其他项目的 wiki 未被误写

## 下一步建议

- 执行 `work` 创建第一个工作区，开始需求开发
- 后续在开发中获得的可复用知识，用 `record` 沉淀到当前项目 `wiki/<project>/` 或 `harness/`
