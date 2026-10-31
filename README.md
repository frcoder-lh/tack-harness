# [Tack Harness](https://frcoder-lh.github.io/tack-harness/)

**精简克制・人类可读・任意配置** — 专为软件研发打造的编程工作流框架

[English](README.en.md) | 简体中文

[![stars](https://img.shields.io/github/stars/frcoder-lh/tack-harness?style=flat-square&label=stars)](https://github.com/frcoder-lh/tack-harness)
![last-commit](https://img.shields.io/github/last-commit/frcoder-lh/tack-harness?style=flat-square)
![license](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)
![shell](https://img.shields.io/badge/shell-POSIX%20sh-4e8cff?style=flat-square)

## 1. 简介

Tack Harness 是一套专为软件研发打造的编程工作流框架：

在软件开发的各个环节对 AI 提供引导和约束：需求分析、规划设计、按模板生成技术文档、代码开发、代码提交与合并、CR 与修正 CR 建议；除此之外，还可以根据需要自定义增加或修改每个环节，进化为属于自己的编程工作流。

- 时间维度上遵循软件工程生命周期流转，空间维度上按照研发习惯组织目录结构；
- 封装了 Git 操作并支持 worktree，允许多个 agent 并行开发不同需求；
- 规范化 AI 开发流程，沉淀公共开发逻辑，集中共享上下文，提高研发效率，降低 token 消耗。

因此，无论是小规模项目，还是大型项目，都能从中受益。

与将流程固化的现有 AI 编码工具不同，Tack Harness 采取以下设计原则：

| 原则 | 说明 |
| --- | --- |
| **流程可固定** | 凡可由脚本完成的操作均不依赖大模型，通过固定流程脚本保证稳定性并控制 token 成本 |
| **能力可扩展** | 新增一个 Markdown 文件即注册一条新能力，无需修改 skill 本体 |
| **状态可追踪** | 工作区 `status.yaml` 为唯一有状态文件，AI 可随时明确当前进度与下一步操作 |
| **改动可隔离** | 通过 worktree 隔离各需求的代码改动，主仓库始终保持只读基准 |
| **经验可沉淀** | 每个完成的任务自动将实践经验沉淀为命令、工作流、规则或 wiki 条目 |

核心特性：

| 特性 | 说明 |
| --- | --- |
| **依赖注入** | skill 为容器、能力为注入物：skill 本体极简，不含任何命令实现；命令、工作流、可委派角色均为项目内的 Markdown 文件，文件头（command/short/triggers/summary）即注入声明，`scan-routes` 运行时动态扫描并装配为路由表。新增一个文件即注入一条新能力，skill 零改动、升级不覆盖 |
| **工作流状态机** | 开发、测试、缺陷修复、冲突合并、分支操作各有独立工作流，定义状态流转并编排命令。工作区 `status.yaml` 的状态由工作流定义，AI 始终明确当前阶段与下一步 |
| **需求分析** | 一个工作区可承载多个研发 story：`analyze` 先读需求内容，再查 `doc/analysis/` 与项目 wiki，最后检索代码，按「完整闭环功能」拆 story 并产出 `story/<story>/analysis.md`（现有实现、可行性、兼容性、待确认问题）；`spec` / `plan` 按 story 逐级推进 |
| **可复用执行指令** | `run` 指令按目录组织：`run/run.md` 只做识别、索引与编排，每条指令的脚本、数据与凭据各自成目录（`local/` 不入库）；`close` 关闭工作区时把 `summary.md` 与 `run/` 一并归入 `wiki/<project>/history/<workspace>/` 并登记 `history/index.md`，脚本可在后续需求中直接复用 |
| **按需创建** | 新建工作区只创建 `status.yaml` 与 `context.md`，story/doc/repo 等目录与 worktree 均按需创建：检索代码先用主仓库 `repo/`，需要修改代码时才创建 worktree，减少初始化开销 |
| **索引化 wiki** | 项目 wiki 采用「索引 + 小文件」：`index.md` 总索引，`biz/`、`code/`、`rule/`、`config/`、`history/` 各分类有 `index.md`；读写统一走 `wiki-read` / `wiki-write`，`evolution` 校验索引完整性 |
| **缺陷溯源** | bugfix 工作流内置 `git-bug-trace`：定位缺陷代码行后一键追溯引入 commit、时间、作者、对应需求/工单 ID 与合并到主干的 MR 链接（GitHub/GitLab/Bitbucket），结果落 `status.yaml` 的 `bug_origin`；区分需求引入与历史遗留，回溯 MR 审查结论与关联改动 |
| **审查与上线门禁** | `code-review` 以 plan/技术方案为规范、目标分支三点 diff 为事实逐函数审查改动正确性与危害、评估影响接口与场景，产出独立审查报告；`release-check` 产出上线检查清单——数据库变更语句、配置变更模板、接口权限申请、中间件资源申请，逐项打勾后发布 |
| **命令自创造** | `record` 为 "生成指令的指令"。首先扫描已有命令尝试融合修正；若无合适命令，仅需提供 `command`，其余内容自动生成 |
| **自进化** | guidance 闭环：任务各环节自动把用户的引导、纠偏、补充约定以原始事实追加到 `status.yaml` 的 `guidance` 列表（pending）；`close` 收尾时自动审查并固化到 workflow/cmd/rule（applied/rejected），落点在回写时直接校验，形成「采集 → 固化 → 校验」的自进化回路 |
| **自动流转** | `auto` 自动执行当前工作流剩余环节到终态：开始前一次性补齐缺失信息并确认全流程，确认后连续执行不中断，结束时汇总关键决策与结果；默认到 merged / completed，可指定一并 close |
| **多项目隔离** | 一个空间可管理多个项目：`tack.yaml` 的 `projects` 数组登记项目，工作条目与 `status.yaml` 记录所属项目；项目知识只读写 `wiki/<project>/`，能力进 harness、项目参数进项目 wiki、工作区参数进 `status.yaml` |
| **三平台 shell 门禁** | 全部 harness 脚本按 POSIX sh 与 Linux/macOS/Windows 共有工具选项编写；`lint-shell-portability` 随 `lint-harness` 运行，检出裸 `mktemp`、GNU 专有选项、bashism 与 sed 方言问题，`evolution` 审查时即修 |
| **自动更新检查** | `close`/`evolution`/`record`/`help` 命令收尾时静默检查新版本（7 天 + 同版本双节流，不在会话开始时抢占任务）；发现新版本时展示本机版本到最新版本之间的全部更新内容，用户确认后说「更新」即可升级 |
| **角色委派** | `harness/agents/` 内置可委派角色（code-explorer / code-architect / code-reviewer），被 `ask`/`plan`/`tech-design`/`code-review`/`merge` 等命令引用后经 Task 子代理在独立上下文并行执行；只供发现与委派，不参与命令路由 |
| **Hook 加速层** | `harness/script/hook/` 提供 IDE Hooks 可选加速（SessionStart 只注入空间位置、UserPromptSubmit 按路由结果注入索引或指令正文、PreToolUse 边界观察）；仅搬运确定性事实，AGENTS.md + `scan-routes.sh` 仍是唯一事实源，默认不启用、不拦截 |
| **向外学习** | `study` 把外部 skill 或仓库当作教材：通读结构、提炼可借鉴点、以新增/融合/优化方式落盘到 harness 对应位置，全程唯一确认点是统一预览，确认后自动提交并触发一次 `evolution` 向内自审 |
| **精简克制** | 保持最小目录结构、基础命令与必要状态流转；凡可脚本化的操作不依赖大模型 |
| **简单易用** | 所有命令支持中英文触发词与简写（如 `需求规划`/`spec`/`sp`） |
| **开放配置** | 全部命令、工作流、规则均位于项目 `harness/` 目录下，可自由增改，升级不覆盖 |
| **安全可控** | worktree 隔离改动、命令准入准出、人工审阅关口、禁用破坏性 Git 操作 |


## 目录

- [1. 简介](#1-简介)
- [2. 快速开始](#2-快速开始)
- [3. 安装](#3-安装)
- [4. 使用流程](#4-使用流程)
- [5. 工作流模型](#5-工作流模型)
- [6. 工作区结构](#6-工作区结构)
- [7. 命令参考](#7-命令参考)
- [8. 扩展机制](#8-扩展机制)
- [9. 安全模型](#9-安全模型)
- [10. 常见问题](#10-常见问题)
- [11. 贡献](#11-贡献)
- [12. 联系方式](#12-联系方式)
- [13. 致谢](#13-致谢)
- [14. License](#14-license)


## 2. 快速开始

```bash
# 1. 安装（推荐由 agent 自行安装）
安装这个skill：https://github.com/frcoder-lh/tack-harness

# 2. 在空目录中初始化工作空间
/tack

# 3. 创建需求并完成规划与开发
/tack work 用户登录
/tack spec && /tack plan && /tack code
```

> ✅ 完成上述步骤即走通一条完整研发链路，全部命令见[命令参考](#7-命令参考)。


## 3. 安装

### 方式一：由 agent 自行安装（推荐）

在 TRAE 中输入：

```
安装这个skill：https://github.com/frcoder-lh/tack-harness
```

### 方式二：一键安装脚本

```bash
curl -fsSL https://raw.githubusercontent.com/frcoder-lh/tack-harness/master/install.sh | sh -s
```

> Windows Git Bash 下若报 `CRYPT_E_NO_REVOCATION_CHECK` 吊销检查错误（schannel 后端无法访问证书吊销服务），加 `--ssl-no-revoke` 即可：
> `curl -fsSL --ssl-no-revoke https://raw.githubusercontent.com/frcoder-lh/tack-harness/master/install.sh | sh -s`

> 默认安装最新 GitHub Release：下载 `tack-harness-<tag>.tar.gz` 并强制核验 SHA-256；安装开发版需显式加 `--branch master`（跳过摘要校验）。

### 方式三：克隆后安装

```bash
git clone git@github.com:frcoder-lh/tack-harness.git
cd tack-harness

sh install.sh                              # 交互式安装（推荐）
sh install.sh --agent trae                 # 安装到 TRAE
sh install.sh --list                       # 查看支持的所有 agent
sh install.sh --agent trae --dry-run       # 预览安装内容
sh install.sh --branch master              # 安装 master 开发版（跳过摘要校验）
```

> Windows 用户请在「Git Bash」终端中执行上述命令；或在 PowerShell 中执行：
> `& "C:\Program Files\Git\bin\bash.exe" install.sh --agent trae-cn`
> （TRAE 国内版用 `trae-cn`，国际版用 `trae`）

### 方式四：从 Releases 下载压缩包

无法使用 Git 克隆，或希望安装某个固定版本时，可从 [Releases 页面](https://github.com/frcoder-lh/tack-harness/releases)下载压缩包（如 `tack-harness-V0.0.1.zip` 或 `tack-harness-V0.0.1.tar.gz`；zip 包内为仓库根目录文件、无外层目录，tar.gz 含同名外层目录），解压后执行安装脚本：

```bash
mkdir tack-harness
unzip tack-harness-V0.0.1.zip -d tack-harness
cd tack-harness

sh install.sh
```

## 4. 使用流程

以下以 "用户登录" 需求为例，说明从空目录到需求上线的完整流程。

### 4.1 初始化项目空间

```
/tack
```

空目录将触发初始化：自动确保本机 Git 可用（缺失时按平台自动安装），tack 空间骨架完整复制至当前目录，并将该目录初始化为 Git 仓库、由框架自动完成首次提交；随后 `init` 引导用户以一句话描述项目（自动提炼项目名与关键词），并接入代码仓库 —— 本地已有仓库则扫描后软链，新仓库则填写 Git 地址克隆。项目信息记录于空间根目录的 `tack.yaml`。

> **Git 双层边界**：空间根仓库（harness/、wiki/、AGENTS.md、space/ 工作文档）的 Git 操作全部由框架在各命令阶段自动提交，用户无需操作；用户只在 `space/<YYYYMMDD>-<branch>/repo/` 工作区代码仓库内执行提交、推送等 Git 操作。

初始化后的空间结构：

```
my-project/
├── AGENTS.md            # 常驻说明书：命令路由 + AGENT/tack harness 核心约束 + 数据来源
├── tack.yaml            # 空间登记：版本、项目（关键词/仓库映射）、工作区列表
├── harness/             # 开发过程定义（需求无关，可自定义，升级不覆盖）
│   ├── README.md        #   harness 的使用说明
│   ├── cmd/             #   命令：发现、路由、准入准出
│   ├── agents/          #   可委派角色：独立上下文并行执行（explorer/architect/reviewer）
│   ├── workflow/        #   工作流：状态机与命令编排
│   ├── script/          #   固定流程脚本（清单见 harness/rule/script-catalog.md；Windows 统一经 run.ps1 启动器调用）
│   │   └── hook/        #   IDE Hook 可选加速层（SessionStart/UserPromptSubmit/PreToolUse，默认不启用、不拦截）
│   ├── rule/            #   业务、代码与安全规则（coding-standards、naming 命名、security、git-boundary 双层边界、context-loading 上下文加载、wiki-read/wiki-write wiki 读写、windows-env、record-* 沉淀规则；不参与路由，按需加载）
│   ├── template/        #   命令、工作流、文档、工作区模板
│   └── reference/       #   通用方法论与复杂独立能力（随 harness 分发、不接受项目沉淀；被命令/工作流/角色/规则引用后才加载）
├── wiki/                # 公共知识：按项目隔离的项目 wiki（init/record/close 按需物化，条目带来源、矛盾保留演变；不记易变代码逻辑）
│   └── <project>/       #   项目 wiki（索引 + 小文件），<project> 与 tack.yaml projects 名称一致：index.md 总索引 / biz 业务背景与术语 / code 仓库概览、术语→代码入口、接口→场景与长期分析 / rule 技术决策与工程约定 / config 服务清单、环境与泳道、网关地址、租户账号、关键配置 / history 工作区归档（summary.md + run/）
├── space/               # 工作空间：每个工作一个目录（<YYYYMMDD>-<分支名>，日期前缀便于按创建时间排序）
├── repo/                # 代码主仓库：只保留一份，只读基准
└── .tack/               # 框架本地运行时数据（gitignore，不入库、可随时清理）：log 日志 / backup 回滚备份 / tmp 临时文件 / state 本机状态
```

### 4.2 创建工作（需求）

```
/tack work 用户登录
```

`work` 根据目的生成英文分支名候选、自动推断涉及的关联服务（经用户确认后可增删），随后执行以下操作：

- 只创建 `space/20261001-user-login/` 目录、`status.yaml` 与 `context.md`，**不预建 `story/`、`doc/`、`repo/` 等目录、不检出 worktree**；目录在首次产生文件时按需创建，检索代码时先读主仓库 `repo/`，需要修改代码时再由 `code` 转 `worktree` 按需检出到 `space/20261001-user-login/repo/<repo-name>/`（多个 agent 可并行开发不同需求，互不干扰；worktree 检出的分支名仍为 `user-login`；分支名含 `/` 时目录中以 `-` 扁平化，如 `feature/login` → `20261001-feature-login`，git 分支名保留 `feature/login`）；
- 在 `space/20261001-user-login/` 生成工作区上下文文件：`status.yaml`（唯一有状态文件：属性 + 日志 + 待办）、`context.md`（工作区上下文，执行任何命令前先读）；
- 在 `tack.yaml` 登记该工作。

用户可将 PRD 片段、参考链接、多条需求写入 `space/20261001-user-login/context.md`（可一次提供多条，也可分先后追加），并可指定 AI 分析链路的入口。

### 4.3 需求分析（按研发 story 逐个推进）

```bash
/tack ask            # （可选，需求明确前）代码理解与代码问答，产物落 doc/analysis/，按主题分文件
/tack analyze        # 需求分析：前置为已提供需求内容/需求文档；先读需求内容，再检索 doc/analysis 与项目 wiki，最后检索代码 → story/<story>/analysis.md（现有实现、可行性、兼容性、待确认问题）
/tack spec <story>   # 需求规划（顶层设计与公共契约）：产出 story/<story>/spec.md
/tack plan <story>   # 开发计划（详细设计与施工图）：产出 story/<story>/plan.md + status.yaml 的 tasks 列表
/tack tech-design    # 技术评审文档（按需）：把目标 story 已确认的 spec/plan 重组为 doc/tech-design.md
```

一个工作区可承载多个研发 story；多轮追问与追加需求就地融合到同一 `story/<story>/analysis.md`，不同主题才新建 story 或落 `doc/analysis/`。分析过程检索项目 `wiki/` 公共知识；ask 提炼的稳定导航锚点（术语→检索词/代码入口、接口→业务场景）经人工审阅后由 record 沉淀至根 wiki，调用链等易变细节只留在工作区分析文档。`status.yaml` 随环节推进自动更新状态与进度。

需要从当前环节一路做到需求完成时，执行 `/tack auto`：开始前一次性补齐缺失信息并确认全流程，确认后连续执行到终态，结束时汇总关键决策与结果。

### 4.4 开发、修正与测试

```bash
/tack code         # 先判定涉及仓库并确保就绪（缺仓库转 repo、缺 worktree 转 worktree），再按 tasks 依赖关系连续/并行开发：复用已有逻辑，多方案自动取最优解；用户明确要求时仅交付代码片段
/tack fix          # 需求修正走 spec→plan→代码；代码修正走代码→同步文档，保持文档与代码一致
/tack testcode     # （按需触发，非必经）单测驱动的需求-代码一致性审查：对照 spec/plan 核对代码实现、识别缺陷与边界遗漏，用例暴露问题后修代码而非改测试；覆盖率 90% 是准出指标之一
/tack test         # （按需触发，非必经）系统测试：把测试描述转化为 doc/test.md 可落地方案，需脚本时落到 run/<指令>/
/tack run          # （按需触发，非必经）run 指令管理：run/run.md 只做识别、索引与编排；新增指令落 run/<指令>/（脚本+数据+local/），执行时校验并编排；敏感数据落各指令的 local/（gitignored）
```

`testcode` / `test` / `run` 均为**按需命令**：code 完成后可直接提交合并，AI 不主动询问"是否测试"；用户需要时直接触发（或以测试为目的时走 testing 工作流），不触发无需任何标记。

代码改动仅允许落在 `space/20261001-user-login/repo/` 的 worktree 内，主仓库 `repo/` 始终为只读基准。各环节加载上下文时先经 grep 定位再读取相关片段，避免整仓通读，以节约 token。

### 4.5 提交、合并与收尾

```bash
/tack fetch         # 拉取当前工作区各仓库最新代码
/tack commit        # 自动生成 Conventional Commits 提交信息后直接提交（无需二次确认）
/tack push          # 推送，未关联远端时先引导关联
/tack merge         # 纯分支合并：fetch 最新后把源分支合入目标分支（当前工作区为源分支时新建关联工作区执行），冲突转 /tack solve，完成后提交并推送
/tack close         # 交付检查 → 输出交付摘要 → 自动判定工作区归档（wiki/<project>/history/<workspace>/summary.md，登记 history/index.md，run/ 整体移入，标准产物外文件询问是否保留）→ 按分类与索引提炼 wiki（含技术决策与 ask 记录归档）→ 消费 guidance 自进化固化 → 移除 worktree、按登记簿安全清理分支 → 删除工作区目录、移除 tack.yaml 工作区登记（关联工作区级联关闭）
```

### 4.6 经验沉淀与复用

任务结束后，AI 自动调用 `/tack record` 沉淀经验：先扫描已有命令，可融合则融合修正；需新建命令时，仅需提供 `command`，简写、中英文触发词与命令正文自动生成 —— **扫描器即时识别，skill 无需任何改动**。

经验沉淀形成三条互补通路：

- **自动采集**：任务各环节凡用户对 AI 的做法有过引导、纠偏、补充约定，自动把原始事实追加到 `status.yaml` 的 `guidance` 列表（pending），`close` 时自动审查固化到 workflow/cmd/rule（applied）或标记不固化（rejected），落点在回写时直接校验；
- **向内自审**：`/tack evolution` 定期审查全部指令文件，识别可沉淀为 rule/reference/script 的候选，经人工确认后落盘；
- **向外学习**：`/tack study <skill 名|本地路径|Git 链接>` 通读外部 skill 或仓库，提炼可借鉴点并以新增/融合/优化方式落盘到 harness，统一预览确认后自动提交并触发一次 evolution。


## 5. 工作流模型

工作流由「状态机 + 命令编排」构成。AGENTS 收到指令后，先确认当前工作，再识别意图所属工作流，并按状态流转引导命令：

| 工作流 | 触发词 | 状态流转 |
| --- | --- | --- |
| development | 开发工作流 / 需求开发 / 功能开发 / development workflow / requirement development / feature development /dev | `initialized → planning → developing → reviewing → merged`，close 后工作区注销（目录与登记移除） |
| testing | 测试工作流 / 补测试 / 测试任务 / testing workflow / add tests / testing task /tst | `initialized → test-planning → testing → verifying → completed` |
| bugfix | 修bug / 修缺陷 / 排障 / fix bug / fix defect / troubleshoot /bug | `initialized → reproducing → diagnosing → fixing → verifying → completed` |
| merge-conflict | 合并冲突 / 冲突工作流 / merge conflict / conflict workflow /mc | `initialized → fetching → merging → resolving → verifying → pushing → completed` |
| branch-op | 分支操作 / branch operation /bop | `initialized → preparing → integrating（冲突时 resolving）→ pushing → completed`，临时分支与 worktree 在 close 时清理 |

任意环节受阻可进入 `blocked` 状态（在 `status.yaml` 中记录阻塞原因），解除后回到原状态。开发主链路如下：

```mermaid
flowchart LR
    A["/tack init"] --> B["/tack work 需求"]
    B --> B2["/tack analyze 需求分析"]
    B2 --> C["/tack spec"]
    C --> D["/tack plan"]
    D --> E["/tack tech-design"]
    E --> F["/tack code"]
    F --> H["/tack fetch"]
    H --> I["/tack commit"]
    I --> J["/tack push"]
    J --> K["/tack merge"]
    K --> L["/tack close"]
    B -. 需求明确前可选，落 doc/analysis .-> A1["/tack ask"]
    F -. 用户需要时触发，非必经 .-> G["/tack testcode"]
    F -. 用户需要时触发，非必经 .-> G2["/tack test"]
    F -. 用户需要时触发，非必经 .-> G3["/tack run"]
    C & D & E & F -. 发现偏差 .-> M["/tack fix"]
    M -. 需求修正回环 .-> C
    K -. 冲突 .-> N["/tack solve"]
    N -.-> K
```

> `testcode` / `test` / `run` 是**按需命令**：不在主链路上占位，不阻塞提交与合并，AI 不在 code 完成后主动询问或引导；用户需要单测审查、系统测试或执行脚本时直接触发（或以测试为目的时走 testing 工作流），不触发无需任何"跳过"标记。


## 6. 工作区结构

`space/<YYYYMMDD>-<branch>/`（如 `space/20261001-user-login/`；目录名带创建日期前缀，按名排序即按创建时间排序；分支名中的 `/` 在目录名中转为 `-`，如 `feature/login` → `20261001-feature-login`，worktree 内 git 分支名保留 `/` 且不带日期）根目录保持扁平，工作区文档按 `story/` 与 `doc/` 分层；建区只创建 `status.yaml` 与 `context.md`，`story/`、`doc/`、`run/`、`repo/` 等目录在首次产生文件或检出 worktree 时创建：

| 文件 | 产生时机 | 作用 |
| --- | --- | --- |
| `status.yaml` | 创建工作区 | 属性 + 日志 + 待办：记录当前处理任务、进度与下一步；`tasks` 任务清单（依赖/验收/状态，全工作区汇总）与 `deploy` 部署登记（泳道/路由/版本/状态）；`guidance` 列表采集用户引导（pending）并在 close 时固化为 harness 条目（applied/rejected）；唯一有状态文件，字段由 `work-status.sh` 确定性回写 |
| `context.md` | 创建工作区 | 工作区上下文：原始需求（可多条/分批追加）、参考链接、约束与需求理解；执行任何命令前先读 |
| `story/<story>/analysis.md` | `/tack analyze` | 需求分析：现有实现、可行性、与现有实现的兼容性、实现建议、待确认问题与讨论记录（按 story 一份） |
| `story/<story>/spec.md` | `/tack spec <story>` | 需求规划（顶层设计与公共契约）：做什么、为什么、边界与验收 |
| `story/<story>/plan.md` | `/tack plan <story>` | 开发计划（详细设计与施工图）：接口/SQL/验证/上线流程 + 任务清单 |
| `doc/tech-design.md` | `/tack tech-design` | 技术评审文档（多 story 分别评审时为 `doc/tech-design-<story>.md`） |
| `doc/test.md` | `/tack test`（按需） | 系统测试方案（可落地、可执行）；与 testcode（单测/覆盖率）区分，面向完整系统功能验证 |
| `doc/code-review.md` | `/tack code-review`（按需） | 合并前独立审查报告（逐函数双轴分析 + 影响面） |
| `doc/release-check.md` | `/tack release-check`（按需） | 上线检查清单（数据库/配置/接口权限/中间件申请） |
| `doc/analysis/` | `ask` / 需求分析前的问答 | 需求明确前的代码问答与分析记录，按主题一文件 |
| `run/` | `/tack test` / `/tack run`（按需） | run 指令目录：`run.md` 只做识别/索引/编排，每条指令落 `run/<指令>/`（脚本+数据）；该指令的 `local/` 存敏感数据（已被 .gitignore 忽略，不入版本库） |
| `repo/<name>/` | `code` 转 `worktree`（按需） | git worktree，唯一可写代码区；检索代码时先用主仓库 `repo/`，需要修改时才检出 |


## 7. 命令参考

所有命令支持中英文触发词与简写，格式为 `/tack <命令|简写|触发词> [参数]`（在已激活 tack 的对话中亦可省略 `/tack` 前缀，直接输入命令或自然语言）。完整清单以 `/tack help` 的实时扫描结果为准。

### 7.1 项目空间命令（cmd/base/）

| 命令 | 简写 | 触发词 | 作用 |
| --- | --- | --- | --- |
| `init` | i | 初始化 / 接入仓库 / 整理文档 / initialize / connect repo / organize docs /init | 提炼项目信息写入 `tack.yaml`，扫描软链或克隆仓库（自然语言「接入仓库」「整理文档」同样路由至此） |
| `work` | w | 工作区 / 新建工作区 / 切换工作区 / 分支合并 / 分支变基 / workspace / new workspace / switch workspace / merge branches / rebase branches /work | 新建 / 重命名 / 切换 / 列出工作区，自动推断服务；新建只创建 `status.yaml` 与 `context.md`，story/doc/repo 等目录与 worktree 按需创建；亦承接分支合并/变基意图，分流至 branch-op 工作流 |
| `help` | h | 帮助 / 命令 / help / commands /help | 扫描 harness，输出工作流与全部命令 |
| `update` | u | 更新 / 更新skill / update / update skill /update | 更新 harness 与空间根 .gitignore（点开头目录默认忽略，强制兜底）；cmd/ 只增补，`rule/` 变更逐文件交用户裁决（采用新版 / 保留本地 / 融合），`AGENTS.md` 与 `tack.yaml` 保留（老空间自动迁移登记区块） |
| `repo` | rp | 新建仓库 / 建仓 / 更新仓库 / 拉取仓库 / repo / repo fetch / create repo / new repository /createrepo /create-repo | 管理代码主仓库（`$root/repo/`）：新建并纳入项目空间管理，或更新全部/指定主仓库到远端最新 |
| `record` | r | 记录 / 记忆 / 沉淀 / record / remember / distill /record | 优先融合已有条目；可落命令 / 工作流 / 规则 / wiki / AGENTS.md 常驻约束，新建时仅需提供 command |
| `evolution` | evo | 进化 / 进化harness / evolve / evolve harness /evolution | 校准 `tack.yaml` 工作区登记与 `space/` 实际目录；检查各项目 wiki 索引完整性并补录未登记文件；结构自检（lint-harness + lint-shell-portability）并审查指令，提炼 rule/reference/script 候选、清理过时事实与非必要反向描述（cleanup 候选）；支持 tack 空间与源仓库两种运行模式；sh 脚本三平台兼容不符合项当场修正，其余人工确认后落盘 |
| `study` | st | 学习 / 研习 / 借鉴 / study / learn / learn from /study | 向外学习外部 skill 或仓库的设计，提炼可借鉴点并落盘到 harness 对应位置，统一预览确认后提交，随后自动执行一次 evolution |

### 7.2 需求开发命令（cmd/dev/）

| 命令 | 简写 | 触发词 | 作用 |
| --- | --- | --- | --- |
| `ask` | a | 问 / 提问 / 代码问答 / 分析代码 / 代码分析 / question / code qa / analyze code / code analysis /ask | 可选：按索引并发检索工作区文档与项目 wiki，再按需检索代码核实（工作区代码优先、主仓库兜底）；在 `$work/doc/analysis/` 产出分析文档或沉淀问答（按主题分文件） |
| `analyze` | an | 需求分析 / 分析需求 / 需求可行性 / 需求兼容性 / requirement analysis / analyze requirement / feasibility analysis /analyze | 建区后必经：前置为用户已提供需求内容或需求文档；先读需求内容，再检索 `doc/analysis/` 与项目 wiki，最后检索代码，按「完整闭环功能」拆研发 story 并产出 `story/<story>/analysis.md`（现有实现、可行性、兼容性、待确认问题）；需求可多条/分批追加，多轮讨论就地融合 |
| `spec` | sp | 需求规划 / 整体设计 / requirement planning / overall design /spec | 读 `context.md` 中本 story 需求、`story/<story>/analysis.md`、wiki（root/doc，按索引检索）+ 代码事实，grep 定位后产出 `story/<story>/spec.md`（顶层设计与公共契约；产品/测试决策在本环节关闭） |
| `plan` | p | 详细设计 / 开发计划 / 任务拆解 / detailed design / development plan / task breakdown /plan | 按 story：读已确认 spec 与 analysis，复杂任务先多方案对比与选定，再落到接口/SQL/验证方式/上线流程、模块划分与任务依赖（写入 `story/<story>/plan.md` + status.yaml tasks） |
| `tech-design` | td | 技术方案 / 技术评审 / technical design / tech doc / tech review /tech-design | 按需：仅在需要正式评审时，把目标 story 已确认的 spec/plan 按模板重组为 `doc/tech-design.md`，不新增设计决策 |
| `code` | c | 编码 / coding / develop / write code /code | 编码前判定仓库就绪（缺仓库转 repo、缺 worktree 转 worktree）；按 tasks 依赖连续/并行开发；用户明确要求时支持仅交付代码片段 |
| `fix` | fx | 修正 / 需求修正 / 修正代码 / requirement fix / fix requirement / code fix /fix | 需求修正（spec→plan→代码）或代码修正（代码→同步文档），保持文档与代码一致 |
| `testcode` | tc | 单测 / 单元测试 / unit test / unit testing /testcode | 按需触发，非必经：以单测为手段做需求-代码一致性审查与缺陷发现，对照 spec/plan 验收标准核对代码、识别边界遗漏，用例暴露问题后修代码而非改测试；覆盖率 90% 是准出指标之一 |
| `test` | t | 测试 / 系统测试 / 集成测试 / system test / integration test / end-to-end test /test | 按需触发，非必经：把测试描述转化为 `$work/doc/test.md` 可落地方案；需脚本时落到 `run/<指令>/` |
| `run` | rn | 运行 / 执行 / 跑脚本 / execute / run script /run | 按需触发，非必经：`run/run.md` 只做指令识别、索引与编排；按用户描述新增 `run/<指令>/`（脚本+数据+local/），执行时按索引识别、校验并编排；敏感数据落各指令的 `local/`（gitignored） |
| `code-review` | rv | 代码审查 / 审查报告 / code review / review report /code-review | 按需触发：以 story plan/tech-design 为规范、目标分支三点 diff 为事实，逐函数分析改动、正确性与危害，评估影响接口与场景，产出 `$work/doc/code-review.md` |
| `release-check` | rc | 上线检查 / 发布检查 / release check / go-live check /release-check | 按需触发：识别数据库变更（含变更语句）、配置变更（含模板）、新增接口调用（权限申请）、新增中间件（申请配置），产出 `$work/doc/release-check.md` |
| `close` | cl | 关闭工作区 / close workspace / finish /close | 交付检查与摘要、自动判定工作区归档（`wiki/<project>/history/<workspace>/summary.md`，`run/` 整体移入，标准产物外的文件询问是否保留）、提炼 wiki（含技术决策与 ask 记录归档）、消费 guidance 自进化固化 harness 并校验落点、移除 worktree、按 `branches` 登记簿经 `branch-clean.sh` 安全清理分支、删除工作区目录并移除 `tack.yaml` 工作区登记；关联工作区级联关闭 |
| `auto` | au | 自动执行 / 全自动 / 自动流转 / 自动开发 / auto / auto run / automatic execution / autopilot /auto | 自动执行当前工作流剩余环节到终态：开始前一次性补齐缺失信息并确认全流程，确认后连续执行不中断，结束时汇总关键决策与结果；默认到 merged / completed，可指定一并 close |

### 7.3 Git 命令（cmd/git/）

| 命令 | 简写 | 触发词 | 作用 |
| --- | --- | --- | --- |
| `fetch` | f | 拉取 / pull / pull code /fetch | 拉取当前工作区各仓库最新代码（仅 fetch，不 merge） |
| `worktree` | wt | 工作树 /worktree | 为指定仓库按需补建 worktree |
| `commit` | ci | 提交 / local commit /commit | 本地提交，非 git 目录先 init；提交信息自动生成后直接提交，无需二次确认 |
| `push` | ps | 推送 / push remote /push | 推送远端，未关联时引导关联 |
| `merge` | m | 合并 /merge | 纯分支合并：fetch 最新后把源分支合入目标分支；当前工作区为源分支时新建关联工作区（记录 `parent_workspace`，close 级联关闭），冲突转 solve，完成后提交并推送 |
| `solve` | s | 冲突 / 解决冲突 / conflict / resolve conflict /solve | 引导式逐文件解决冲突 |


## 8. 扩展机制

工作流与命令均为 Markdown 文件，文件头声明路由信息：

```yaml
---
command: spec          # 工作流文件用 workflow: development
short: sp
triggers: 需求规划, 整体设计, spec
summary: 产出需求规划文档
---
```

扫描器一次性扫描工作流与命令：

```bash
sh harness/script/scan-routes.sh list      harness   # 工作流表 + 命令表 + 可委派角色表
sh harness/script/scan-routes.sh workflows harness   # 仅工作流（意图识别）
sh harness/script/scan-routes.sh commands  harness   # 仅命令
sh harness/script/scan-routes.sh agents    harness   # 仅可委派角色（agents/ 不参与 resolve）
sh harness/script/scan-routes.sh resolve   harness 需求规划
sh harness/script/lint-harness.sh          harness   # 结构自检：frontmatter/四段/路由冲突/reference 孤儿
sh harness/script/lint-shell-portability.sh harness   # 三平台可移植性机检：裸 mktemp/GNU 专有选项/bashism/sed 块分号
```

扩展规则：

- 新增 Markdown 文件即注册新能力，即时生效；脚手架位于 `harness/template/cmd.md` 与 `workflow.md`；
- `_` 开头的文件不参与路由；支持新建自定义命令分组；
- `record` 可交互式融合或生成新命令、新工作流。

### 8.1 IDE Hook 可选加速层

`harness/script/hook/` 提供 TRAE / Claude Code 的 Hooks 集成，作为**可选加速层**而非控制流本身：事实源与判断权仍在 `AGENTS.md` + `scan-routes.sh`，Hook 只搬运确定性事实。初始化空间时自动生成 `.trae/hooks.json` 与 `.claude/settings.json`，需在 IDE「设置 > Hooks」中手动启用后才生效。

| 事件 | 作用 | 对会话影响 |
| --- | --- | --- |
| SessionStart | 预注入路由全表、`$root`/`$work` 路径与工作区快照（cwd 在工作区内则精确命中，否则取最近活跃并提示确认）；不写入任何路径类环境变量 | 省去首轮 `scan-routes list` 往返 |
| UserPromptSubmit | 以当次 cwd 实时解析空间根与工作区（cwd 在 `space/<name>/` 内精确命中，天然支持多项目窗口与同空间多工作区并行；之外回退最近活跃）；对用户输入执行 `scan-routes resolve`：唯一命中直接注入 cmd/workflow 正文与状态快照，多命中列候选，无命中给全表 | 省去路由解析往返与重复的空间/工作区扫描 |
| PreToolUse | 观察模式（默认）：命令执行类工具（RunCommand/Bash）的调用与 Git 双层边界、`--force`/`--no-verify` 等规则命中经统一日志记录；`TACK_HOOK_ENFORCE=1` 才输出 deny（**当前预留，默认不拦截**） | 默认零输出、零拦截 |

统一日志：设置环境变量 `TACK_HOOK_LOG=1` 后，三个 Hook 每次被调用都会把完整记录（时间、事件、pid、`$root`/`$work`、输入 payload、注入/拦截输出、退出码与耗时）追加到 `$root/.tack/log/hook.log`，并发调用按整块串行写入、互不交错；默认关闭，关闭时 Hook 输出逐字节不变。

关闭：删除空间根下的 `.trae/` 与 `.claude/` 目录即回到默认路径（AI 主动调用 `scan-routes.sh` 解析路由），框架能力不受影响。


## 9. 安全模型

| 机制 | 说明 |
| --- | --- |
| **worktree 隔离** | 代码改动仅限工作区 worktree，主仓库 `repo/` 只读 |
| **Git 双层边界** | 空间根仓库由框架自动提交托管（`space.sh`），用户不直接操作；用户 Git 命令仅作用于工作区代码仓库 |
| **命令准入准出** | 破坏性 Git 操作被禁用，命令执行受准入准出约束 |
| **人工审阅关口** | 分析结论、合并均需人工确认后方可生效；提交由用户主动发起 commit 命令触发（发起即确认意图，信息自动生成后直接提交） |
| **凭据明文拦截** | `scan-secrets.sh` 在空间文档（wiki/、space/）提交前做高置信凭据扫描，命中即阻断自动提交；支持 `tack:allow-secret` 豁免标记与占位值过滤 |
| **固化落点校验** | guidance 固化回写时校验落点文件存在，路径失效即阻断写入，防止固化证据链悬空 |
| **Hook 边界观察层** | `PreToolUse` Hook 观察 Git 双层边界、`--force`/`--no-verify` 等破坏性操作；默认仅记录不拦截，调用与命中详情随 `TACK_HOOK_LOG=1` 统一写入 `$root/.tack/log/hook.log`（三个 Hook 事件共用）；`TACK_HOOK_ENFORCE=1` 预留 deny 路径，启用前须先用日志校准误判 |
| **工作区删除门禁** | close 经 `work.sh purge` 删除工作区目录前三道校验：仅接受单层目录名（拒绝分隔符、空白与 `.`/`..`）、物理路径经 `pwd -P` 确认位于 `space/` 内（防 symlink 逃逸）、`repo/` 下无残留 worktree；任一不满足即拒绝删除 |
| **分支清理门禁** | close 经 `branch-clean.sh` 仅处理 `status.yaml` 登记的分支，默认 dry-run；未合并主分支、保护分支、被 worktree 占用的分支与主干不明项只列出、不删除，远端分支不自动删除 |


## 10. 常见问题

**Q：如何添加自定义命令或工作流？**

复制 `harness/template/cmd.md`（命令）或 `workflow.md`（工作流）至对应目录，修改文件名并补充文件头，扫描器即时识别；亦可直接调用 `/tack record`，该命令会先尝试与已有命令融合，新建时仅需提供 command。

**Q：`update` 会覆盖我的自定义内容吗？**

不会。`update` 仅刷新 `script/`、`template/`、`reference/`、`workflow/`；`cmd/` 只增补、不覆盖同名文件；`rule/` 下文件按差异正常分类，变更逐文件询问采用新版 / 保留本地 / 融合（未裁决保持原样，不静默跳过、不自动覆盖）；`AGENTS.md` 与 `tack.yaml` 保留，老空间的项目信息区块会自动迁移到 `tack.yaml`。

**Q：支持多仓库项目吗？**

支持。`work` 按目的推断涉及服务，新建时只创建 `status.yaml` 与 `context.md`（story/doc/repo 等目录按需创建）；需要修改代码时，每个仓库在 `space/<YYYYMMDD>-<branch>/repo/<repo-name>` 下按需创建独立 worktree，Git 命令逐仓库执行。

**Q：为什么项目信息放在 tack.yaml，而不是常驻的 AGENTS.md？**

为了把常驻上下文与登记数据分离。`AGENTS.md` 只保留路由入口、行为约束与数据来源；项目名、关键词、服务仓库映射、工作区列表等结构化登记放在空间根目录的 `tack.yaml`，由 `harness/script/project.sh` 维护，按需查询，避免每次会话都把这些数据塞进上下文。

**Q：为什么不按 project 组织目录？**

tack-harness 的一等公民是 harness、repo（代码）、space（工作区）、wiki（知识库），而不是 project。project 只是业务视角的划分，记录在 `tack.yaml` 里（业务归属与服务-仓库映射），不落到目录层级；目录以工作区为单位组织，让一次需求涉及的代码、文档与沉淀始终聚在一处。

**Q：Windows 上脚本能跑吗？**

脚本为 POSIX sh，Windows 统一经 `run.ps1` 启动器调用（自动定位 Git for Windows 的 bash.exe，未安装时首次运行自动通过 winget 安装）；不支持软链时可采用克隆方式接入仓库。Git Bash 中的 curl 若报 `CRYPT_E_NO_REVOCATION_CHECK`（schannel 证书吊销检查失败），在 curl 后加 `--ssl-no-revoke`，或改用方式三克隆安装。

**Q：`record` / `evolution` / `study` 三个"进化"类命令如何分工？**

`record` 沉淀用户明确给出的内容或 guidance 条目（人给素材）；`evolution` 向内自审，从现有 cmd 中提炼 rule/reference/script（无外部素材）；`study` 向外学习第三方 skill/仓库，借鉴其流程、命令、规则、脚本、模板与组织方式。


## 11. 贡献

欢迎提交新命令、新工作流、文档修正及 issue 反馈。

- 提交问题与建议：[GitHub Issues](https://github.com/frcoder-lh/tack-harness/issues)
- 参考现有命令模板：`harness/template/cmd.md`、`workflow.md`


## 12. 联系方式

欢迎加入 TackHarness 交流群（QQ群： **1128954501**，抖音群： **978398534393**）交流使用问题、实践经验与改进想法：

<p align="center">
  <img src="https://raw.githubusercontent.com/frcoder-lh/tack-harness/master/docs/contact.png" alt="TackHarness 交流群二维码">
</p>

问题反馈与功能建议也可以直接提 [GitHub Issues](https://github.com/frcoder-lh/tack-harness/issues)。


## 13. 致谢

部分研发方法论（harness/reference/）参考 [Matt Pocock 的 skills 仓库](https://github.com/mattpocock/skills) 翻译变体而来。

角色并行委派、方案对比门禁、审查分级与结构自检等设计，借鉴了 [anthropics/claude-code](https://github.com/anthropics/claude-code) 官方插件（feature-dev、code-review）与 Agent Skills/Subagents 文档中的工程实践。

记忆系统借鉴了 [hindsight](https://github.com/vectorize-io/hindsight)。


## 14. License

[MIT License](LICENSE) © frcoder-lh
