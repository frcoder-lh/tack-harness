# Tack

> 精简克制、人类可读、任意配置的编程工作流 Skill。通过 `/tack` 触发，覆盖从工作区初始化到代码上线的完整开发流程。

## ✨ 特性

- **🔄 全流程编排** — 工作区初始化 → 上下文 → 仓库 → 需求 → 分析 → 拆解 → 开发 → 单测
- **📝 人类可读** — 所有输出都是 Markdown，方便人和 AI 双向阅读
- **🔧 任意配置** — 项目级 `AGENTS.md` 可随时调整命令路由、目录结构、编码规范
- **🧩 可组合** — 各环节独立，可按顺序执行也可单独使用
- **🌐 中英双语** — 命令支持中英文关键词，团队协作无语言障碍
- **🛡️ 安全可控** — 每步有前置条件检查、代码审查必选、不篡改原始信息

## 🚀 快速上手

### 方式一：agent自行安装

在 TRAE 中输入下面的提示词：

```
安装这个skill：https://github.com/frcoder-lh/tack-harness
```

### 方式二：一键安装脚本

```bash
# 安装到 TRAE
curl -fsSL https://raw.githubusercontent.com/<user>/tack-harness/main/install.sh | sh -s -- --agent trae
```

### 方式三：克隆后，执行安装脚本

```bash
git clone git@github.com:frcoder-lh/tack-harness.git
cd tack-harness
sh install.sh --agent trae                 # 安装到 TRAE
sh install.sh --agent cursor              # 安装到 Cursor
sh install.sh --target ~/my-agent        # 自定义路径
sh install.sh --list                      # 查看所有支持的 agent
sh install.sh --agent trae --dry-run      # 预览安装
```

### 方式四：克隆后，手动复制到 TRAE 目录下

```bash
直接将tack目录复制到 ~/.trae/skills目录下
```

### 验证安装成功

在 TRAE 中输入 `/tack`，看到命令列表即安装成功。

```bash
# 初始化项目
/tack init-workspace ~/projects/my-app

# 输入业务上下文
/tack init-context business-prd.md architecture-doc.md

# 克隆代码仓库
/tack init-repos git@github.com:org/backend.git git@github.com:org/frontend.git

# 新建需求 → 输入 PRD → 分析 → 拆解 → 开发
/tack new-req feature/user-auth
/tack req-context prd.md
/tack analyze-req
/tack breakdown
/tack develop
```

## 📦 Skill 包里有什么

```
tack/                         # 安装到 ~/.trae/skills/tack/
├── SKILL.md                  # Skill 定义（AI 读取）
├── README.md                 # 本文件
├── resources/                # 12 个工作流执行指令
├── script/                   # 4 个自动化脚本
└── template/                 # 项目初始化模板
```

| 目录           | 内容                               | 数量   |
| ------------ | -------------------------------- | ---- |
| `resources/` | 每个环节一份详细执行指令                     | 12   |
| `script/`    | 目录骨架、仓库克隆、需求创建、worktree 辅助       | 4    |
| `template/`  | AGENTS.md、wiki 占位、文档模板、编码规范、脚本副本 | \~20 |

## 🛠️ 命令一览

所有命令支持中英双语关键词，格式：`/tack <关键词> [参数]`

| 阶段      | 中文           | 英文               | 参数       |
| ------- | ------------ | ---------------- | -------- |
| **初始化** | 初始化工作区 / 初始化 | `init-workspace` | 根目录路径    |
| <br />  | 初始化上下文       | `init-context`   | 文档路径(多个) |
| <br />  | 初始化仓库        | `init-repos`     | 仓库地址(多个) |
| **需求**  | 新建需求 / 新建    | `new-req`        | 分支名称     |
| <br />  | 输入需求 / 需求上下文 | `req-context`    | PRD 文档路径 |
| <br />  | 分析需求 / 分析    | `analyze-req`    | —        |
| <br />  | 任务拆解 / 拆解    | `breakdown`      | —        |
| **开发**  | 开发           | `develop`        | —        |
| <br />  | 需求修正 / 修正    | `fix-req`        | 修正说明     |
| <br />  | 单测           | `unit-test`      | —        |

## 🔀 工作流

```
init-workspace ──► init-context ──► init-repos
       │
       ▼
   new-req ──► req-context ──► analyze-req ──► breakdown
                                                    │
                                                    ▼
                                                 develop ⇄ fix-req
                                                    │
                                                    ▼
                                                 unit-test
```

## ⚙️ 配置

### 项目级：`AGENTS.md`

每个项目独立的"常驻说明书"。`init-workspace` 时自动生成，定义：

- 最高优先级约束（不篡改、代码审查必选、Git 安全等）
- 项目目录结构与文件导航
- **命令路由覆盖** — 可以新增命令、修改 resource 调用链
- 编码规范、文档模板、脚本路径

### Skill 级：`SKILL.md`

通用能力定义，换项目不变。定义命令路由、资源索引、执行约定。

### 两者分工

| <br /> | SKILL.md | AGENTS.md   |
| ------ | -------- | ----------- |
| 角色     | 通用能力工具箱  | 项目常驻说明书     |
| 定义     | "能做什么"   | "在这个项目里怎么做" |
| 优先级    | 默认行为     | 可覆盖默认路由     |

### 定制示例

```markdown
## 在 AGENTS.md 中修改命令路由

#### `/tack 开发` 或 `/tack develop`
- 调用: `implement.md` + `tdd.md` + `code-review.md` + `script/git-worktree-helper.sh`
- 新增: 先执行 `my-custom-check.md`（业务特有的质量门禁）
```

## 📂 目录结构

### Skill 安装目录

```
tack/
├── resources/          # 执行指令（grilling、to-spec、implement...）
├── script/             # 自动化脚本（init-workspace、init-repos...）
└── template/           # 项目模板（init-workspace 时复制）
    ├── AGENTS.md
    ├── wiki/           # manifest / business / code-understanding
    ├── work/           # status.yaml、repo_readme.md
    └── harness/        # doc / rule / script 副本
```

### 项目运行时

```
<project>/
├── AGENTS.md           # 项目常驻说明书
├── harness/            # 流程定义（从 template 复制）
│   ├── rule/           # coding-standards、development-workflow
│   ├── doc/            # PRD / 技术设计 / 测试计划模板
│   ├── script/         # 项目级脚本副本
│   └── template/work/  # status.yaml、repo_readme.md
├── wiki/               # 全局上下文
├── work/<branch>/      # 每个需求一个文件夹
│   ├── status.yaml     # 进度跟踪
│   ├── wiki/           # 需求上下文
│   ├── harness/        # 技术设计
│   ├── plan/           # 任务清单
│   └── repo/           # git worktree
└── repo/               # 代码主仓库
```

## ❓ 常见问题

**Q: Skill 与 AGENTS.md 的关系？**
A: SKILL.md 定义通用能力（"能做什么"），AGENTS.md 定义项目专属行为（"怎么做"）。每个项目独立维护 AGENTS.md，SKILL.md 升级不受影响。

**Q: 如何升级 Skill？**
A: 替换 `~/.trae/skills/tack/` 下的文件即可。项目级 `AGENTS.md` 和 `harness/` 配置保持不变。

**Q: 支持哪些编程语言？**
A: Skill 本身与语言无关。编码规范、文档模板通过 `harness/rule/` 和 `harness/doc/` 定制。

**Q: Windows 下能用吗？**
A: 可以。脚本需要 Git Bash 或 WSL 环境。原生 Windows 下部分脚本可能需要适配。

**Q: 遇到 Bug 怎么办？**
A: Skill 会自动加载 `diagnosing-bugs.md` 的诊断流程。需要跨会话延续时读取 `handoff.md` 创建交接文档。

**Q: 不想用某个环节？**
A: 各环节独立，可跳过任何一步。在 `AGENTS.md` 的命令路由中删除对应命令即可。

## 🙏 致谢

本 Skill 的局部研发节点由 [Matt Pocock 的 skills 仓库 ](https://github.com/mattpocock/skills)中的 Skill 翻译变体而来。

## 📄 License

MIT License
