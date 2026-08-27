# AGENTS.md — 常驻说明书

> 项目核心上下文。每个会话首先读取此文件。像新员工手册。

---

## 🔴 最高优先级约束

1. **不篡改原始信息**: AI 对输入文档只做格式整理和梳理，绝不修改原始内容
2. **人类审阅关口**: AI 生成的 wiki 内容必须经过人工审阅才能作为上下文使用
3. **依赖检查优先**: 执行任何命令前，先检查前置条件是否满足
4. **Git 操作安全**: 不执行 force push、reset --hard 等破坏性操作
5. **代码审查必选**: 每个开发任务完成后必须经过用户审核

---

## 📁 项目核心文件导航

| 文件 | 位置 | 用途 |
|------|------|------|
| AGENTS.md | 根目录 | 本文件，常驻说明书 |
| wiki/manifest.md | wiki/ | 服务与代码仓库映射关系 |
| wiki/business-understanding.md | wiki/ | 业务线、项目背景知识 |
| wiki/code-understanding.md | wiki/ | AI 生成的代码仓库理解 |
| harness/rule/coding-standards.md | harness/rule/ | 编码规范、代码风格 |
| harness/doc/prd-template.md | harness/doc/ | PRD 文档模板 |
| harness/doc/tech-design-template.md | harness/doc/ | 技术设计文档模板 |
| harness/doc/test-plan-template.md | harness/doc/ | 测试计划模板 |

---

## 🗂️ 项目目录结构

```
<project>/
├── AGENTS.md                    # 本文件 — 项目常驻说明书
├── wiki/                        # 全局上下文
├── harness/                     # 开发过程定义
│   ├── rule/                    #   编码规范
│   ├── doc/                     #   文档模板
│   └── script/                  #   自动化脚本
├── work/                        # 工作目录（每个分支一个文件夹）
│   └── <branch-name>/
│       ├── status.yaml          #   需求状态跟踪
│       ├── wiki/                #   需求上下文
│       ├── harness/             #   技术文档
│       ├── plan/                #   任务清单
│       └── repo/                #   git worktree 工作区
└── repo/                        # 代码主仓库
```

---

## ⚡ 命令触发路由

> 所有命令支持中英文关键词，格式: `/tack <关键词> [参数]`

### 关键词对照表

| 中文关键词 | 英文关键词 | 参数 |
|-----------|-----------|------|
| `初始化工作区` / `初始化` | `init-workspace` | 根目录路径 |
| `初始化上下文` | `init-context` | 文档路径(多个) |
| `初始化仓库` | `init-repos` | 代码仓库地址(多个) |
| `新建需求` / `新建` | `new-req` | 分支名称 |
| `输入需求` / `需求上下文` | `req-context` | PRD 文档路径 |
| `分析需求` / `分析` | `analyze-req` | (无参数) |
| `任务拆解` / `拆解` | `breakdown` | (无参数) |
| `开发` | `develop` | (无参数) |
| `需求修正` / `修正` | `fix-req` | 修正说明 |
| `单测` | `unit-test` | (无参数) |

### 各命令详情

#### `/tack 初始化工作区 <path>` 或 `/tack init-workspace <path>`
- **输入**: 根目录路径
- **前置条件**: 无
- **调用**: `sh harness/script/init-workspace.sh`
- **输出**: 完整目录骨架 + 占位文档

#### `/tack 初始化上下文 <doc1> <doc2> ...` 或 `/tack init-context <doc1> <doc2> ...`
- **输入**: 一个或多个文档路径
- **前置条件**: 已执行 `初始化工作区`
- **调用**: resource `grill-with-docs.md` → `domain-modeling.md`
- **输出**: `wiki/` 下的整理文档
- **约束**: AI 只做格式整理，不篡改原始内容

#### `/tack 初始化仓库 <repo1> <repo2> ...` 或 `/tack init-repos <repo1> <repo2> ...`
- **输入**: 一个或多个代码仓库地址
- **前置条件**: 已执行 `初始化工作区`
- **调用**: `sh harness/script/init-repos.sh` + resource `research.md` → `codebase-design.md`
- **输出**: `repo/` 下的代码副本 + `wiki/code-understanding.md`

#### `/tack 新建需求 <branch-name>` 或 `/tack new-req <branch-name>`
- **输入**: 分支名称
- **前置条件**: 已执行 `初始化工作区`
- **调用**: `sh harness/script/new-req.sh`
- **输出**: `work/<branch-name>/` 目录结构

#### `/tack 输入需求 <prd-path>` 或 `/tack req-context <prd-path>`
- **输入**: PRD 文档路径
- **前置条件**: 已执行 `新建需求`
- **调用**: resource `grill-with-docs.md`
- **输出**: `work/<branch-name>/wiki/` 下的需求上下文

#### `/tack 分析需求` 或 `/tack analyze-req`
- **输入**: 无
- **前置条件**: `work/<branch-name>/wiki/` 存在
- **调用**: resource `grilling.md` → `to-spec.md`
- **输出**: 技术设计文档

#### `/tack 任务拆解` 或 `/tack breakdown`
- **输入**: 无
- **前置条件**: 技术设计文档存在
- **调用**: resource `to-tickets.md`
- **输出**: 任务清单

#### `/tack 开发` 或 `/tack develop`
- **输入**: 无
- **前置条件**: 任务清单存在，repo/ 已初始化
- **调用**: resource `implement.md` → `tdd.md` → `code-review.md`
- **输出**: 按依赖顺序逐任务开发

#### `/tack 需求修正 <fix-description>` 或 `/tack fix-req <fix-description>`
- **输入**: 修正说明
- **前置条件**: 需求已开发或正在开发
- **调用**: resource `grilling.md`
- **输出**: 更新后的需求 + 代码修正

#### `/tack 单测` 或 `/tack unit-test`
- **输入**: 无
- **前置条件**: 开发完成
- **调用**: resource `tdd.md`
- **输出**: 单元测试代码

---

## 🛠️ 常用工具约定

### 内置 Resource 文件

| Resource | 用途 | 使用环节 |
|----------|------|----------|
| `grill-with-docs.md` | 带文档的深入访谈 | init-context, req-context |
| `grilling.md` | 深入访谈澄清 | analyze-req, fix-req |
| `domain-modeling.md` | 构建领域模型 | init-context |
| `research.md` | 代码仓库研究 | init-repos |
| `codebase-design.md` | 代码架构理解 | init-repos |
| `to-spec.md` | 生成技术设计 | analyze-req |
| `to-tickets.md` | 任务拆解 | breakdown |
| `implement.md` | 按 spec 构建 | develop |
| `tdd.md` | 测试驱动开发 | develop, unit-test |
| `code-review.md` | 代码审查 | develop（每任务后） |
| `diagnosing-bugs.md` | Bug 诊断 | 开发遇到问题时 |
| `handoff.md` | 会话交接 | 跨会话继续工作时 |

> Resource 文件位于 skill 安装目录的 `resources/` 子目录。

### 项目脚本（harness/script/）

| 脚本 | 用途 | 调用环节 |
|------|------|----------|
| `init-workspace.sh` | 创建目录骨架和占位文档 | init-workspace |
| `init-repos.sh` | 克隆/拉取代码仓库 | init-repos |
| `new-req.sh` | 创建需求工作目录 | new-req |
| `git-worktree-helper.sh` | git worktree 操作辅助 | develop |

---

## 📝 变更记录

| 日期 | 修改内容 | 修改人 |
|------|----------|--------|
| (初始) | 创建 AGENTS.md | (待填写) |