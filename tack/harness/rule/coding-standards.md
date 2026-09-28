# 编码规范

> 团队代码风格与编程约束的挂载点，被 `code`（编码时加载）与 `agents/code-reviewer.md`（「约定与安全」视角）引用。
>
> 本文件随 harness 分发时只有骨架与少量默认基线（带「默认基线」标注）。其余内容由项目在实战中经 `record` 沉淀填充，沉淀规则见 `record-rule.md`；语言小节按项目技术栈增删。
>
> **没有实质条目的小节不构成任何约束**——未沉淀的维度，编码与评审一律以「严格模仿仓库中已有代码的模式」为默认基线（见 `code` 命令）。

## 通用规范

### 命名约定

（项目沉淀前为空）

### 代码风格

（项目沉淀前为空）

### 注释规范

（项目沉淀前为空）

## 语言特定规范

> 以下语言标题仅为沉淀入口，按项目实际技术栈增删；未列出的语言可新建同级标题。

### TypeScript/JavaScript

（项目沉淀前为空）

### Python

（项目沉淀前为空）

### Java

（项目沉淀前为空）

## Git 规范

> 以下为默认基线，项目可经 `record` 收紧或调整。空间仓库与工作区代码仓库的 Git 操作边界另见 `git-boundary.md`。

### 分支命名

```
<type>-<username>-<description>
```

- `type` 与 commit type 取同一枚举（见下）
- `username` 由用户自定义，建议使用 Git 用户名或昵称或缩写
- `description` 用简短的 kebab-case 英文或中文描述，如 `user-login`

### Commit 信息

```
<type>: <description>

[optional body]
```

type 采用 Conventional Commits 常用枚举：

| type | 用途 |
|------|------|
| `feat` | 新功能 |
| `fix` | 缺陷修复 |
| `docs` | 文档变更 |
| `style` | 格式/风格调整（不影响代码逻辑） |
| `refactor` | 重构（既非新功能也非修缺陷） |
| `perf` | 性能优化 |
| `test` | 测试相关 |
| `build` | 构建系统或外部依赖变更 |
| `ci` | CI 配置与脚本变更 |
| `chore` | 杂项（不影响源码与测试） |
| `revert` | 回滚历史提交 |

### Code Review 要求

- 至少一人 approved
- CI 通过
- 无 merge conflicts

## 禁止事项

> 默认基线，项目可经 `record` 调整。

- 禁止直接 push 到 main/master 分支
- 禁止绕过类型检查
- 禁止提交大型二进制文件
