# Git 规范

> 分支命名与提交信息的默认基线，项目可经 `record` 收紧或调整。
> Git 操作边界与安全禁令见 `git-boundary.md`。
> 加载时机：`work` 新建/重命名工作区生成分支名、`worktree` 补建分支、`commit` 生成提交信息、`merge` 合并提交。

## 分支命名

```
<type>-<username>-<description>
```

- `type` 与 commit type 取同一枚举（见下）
- `username` 由用户自定义，建议使用 Git 用户名或昵称或缩写
- `description` 用简短的 kebab-case 英文或中文描述，如 `user-login`

## Commit 信息

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

## Code Review 要求

- 至少一人 approved
- CI 通过
- 无 merge conflicts

## 禁止事项

- 禁止直接 push 到 main/master 分支
- 禁止提交大型二进制文件
