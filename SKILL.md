---
name: "tack"
version: "V0.0.1"
description: "编程工作流 skill。当用户需要初始化工作区、管理代码仓库、输入/分析需求、任务拆解、按 spec 开发、单元测试、代码审查、Bug 诊断、会话交接时触发。Invoke when user wants to init workspace, manage repos, handle requirement/PRD, break down tasks, develop by spec, unit-test, code-review, debug bugs, or handoff sessions."
---

# Tack Harness

精简克制、人类可读、任意配置的编程工作流 skill。通过 `/tack` 触发，内置 12 个 resource，覆盖从初始化到上线的完整开发流程。

## 加载时执行

1. 读取项目根目录 `AGENTS.md`，加载项目级约束与路由覆盖
2. 若 `AGENTS.md` 不存在，使用 skill 默认路由

## Skill 内置文件

### Resource（resources/）— 执行指令

| 文件 | 用途 | 触发环节 |
|------|------|----------|
| `grill-with-docs.md` | 带文档的深入访谈 | init-context, req-context |
| `grilling.md` | 澄清设计的深入访谈 | analyze-req, fix-req |
| `domain-modeling.md` | 构建领域模型与术语表 | init-context, req-context |
| `research.md` | 代码库后台研究 | init-repos |
| `codebase-design.md` | 代码架构理解 | init-repos |
| `to-spec.md` | 生成技术设计文档 | analyze-req |
| `to-tickets.md` | 任务拆解 | breakdown |
| `implement.md` | 按 spec/tickets 构建 | develop |
| `tdd.md` | 测试驱动开发 | develop, unit-test |
| `code-review.md` | 双轴代码审查 | develop（每任务后） |
| `diagnosing-bugs.md` | Bug 诊断流程 | 遇到问题时 |
| `handoff.md` | 会话交接 | 跨会话继续时 |

### 脚本（script/）— 自动化操作

| 文件 | 用途 |
|------|------|
| `init-workspace.sh` | 创建项目目录骨架与占位文档 |
| `init-repos.sh` | 克隆/拉取代码仓库 |
| `new-req.sh` | 创建需求工作目录 |
| `git-worktree-helper.sh` | Git worktree 辅助 |

### 模板（template/）— 项目初始化时复制

| 路径 | 用途 |
|------|------|
| `template/AGENTS.md` | 项目常驻说明书模板 |
| `template/wiki/` | 全局上下文占位文档 |
| `template/work/` | 需求工作区模板（含 status.yaml、repo_readme.md） |
| `template/harness/doc/` | PRD / 技术设计 / 测试计划模板 |
| `template/harness/rule/` | 编码规范、开发流程说明 |
| `template/harness/script/` | 项目级脚本副本 |

> **规则**: 执行任何环节前，必须**先读取**对应的 resource 文件获取详细指令。

## 命令路由

格式: `/tack <关键词> [参数]`

| 中文关键词 | 英文关键词 | 参数 | 调用链 |
|-----------|-----------|------|--------|
| `初始化工作区` / `初始化` | `init-workspace` | 根目录路径 | `script/init-workspace.sh` |
| `初始化上下文` | `init-context` | 文档路径(多个) | `grill-with-docs.md` → `domain-modeling.md` |
| `初始化仓库` | `init-repos` | 仓库地址(多个) | `research.md` → `codebase-design.md` + `script/init-repos.sh` |
| `新建需求` / `新建` | `new-req` | 分支名称 | `script/new-req.sh` |
| `输入需求` / `需求上下文` | `req-context` | PRD 文档路径 | `grill-with-docs.md` |
| `分析需求` / `分析` | `analyze-req` | — | `grilling.md` → `to-spec.md` |
| `任务拆解` / `拆解` | `breakdown` | — | `to-tickets.md` |
| `开发` | `develop` | — | `implement.md` + `tdd.md` + `code-review.md` + `script/git-worktree-helper.sh` |
| `需求修正` / `修正` | `fix-req` | 修正说明 | `grilling.md` |
| `单测` | `unit-test` | — | `tdd.md` |

### 匹配规则

1. 先精确匹配中文 → 2. 精确匹配英文 → 3. 部分匹配（列出候选项供用户选择）
2. 仅输入 `/tack` 时，展示命令选项列表

## 执行约定

- **前置检查**: 执行命令前先验证前置条件（如 `init-context` 需先 `init-workspace`）
- **Resource 优先**: 每个环节的详细流程由 resource 文件定义，必须先读取再执行
- **脚本调用**: 需调用脚本时，读取 skill 自带脚本内容，在项目中执行
- **状态管理**: 每个需求的进度通过 `work/<branch>/status.yaml` 跟踪，`new-req.sh` 基于 `template/work/status.yaml` 生成
- **故障处理**: 开发遇阻时读取 `diagnosing-bugs.md`；需跨会话延续时读取 `handoff.md`
- **Worktree 约束**: 代码改动仅限 `work/<branch>/repo/` worktree，禁止修改根目录 `repo/`

## Skill 与 AGENTS.md 的分工

| | SKILL.md | AGENTS.md |
|---|----------|-----------|
| 角色 | 通用能力工具箱 | 项目常驻说明书 |
| 定义 | "能做什么"（所有项目通用） | "在这个项目里怎么做"（项目专属） |
| 内容 | 命令路由、资源索引、执行约定 | 目录结构、编码规范、路由覆盖 |
| 优先级 | 默认行为 | 可覆盖 skill 默认路由 |
