# 工作区内部布局

> 常驻 AGENTS.md 只保留 `space/<workspace>/` 一句职责说明，本文件在创建、切换或检索工作区时加载。

## 目录命名

- `<workspace>` = `<YYYYMMDD>-<branch>`：日期前缀便于按创建时间排序；分支名中的 `/` 转为 `-`，保证 `space/` 下始终单层目录。
- git 分支名 `branch` 不含日期、保留 `/`；`work_id` 默认与分支同名。

## 布局（按需创建）

```
space/<YYYYMMDD>-<branch>/
├── status.yaml   # 工作区状态与进展（唯一有状态的文件）
├── context.md    # 工作区上下文（需求、背景、链接；执行任何命令前先读）
├── story/        # 每个研发 story 一个子目录：analysis.md / spec.md / plan.md
├── doc/          # 生成文档：tech-design / test / code-review / release-check
│   └── analysis/ # 需求前的代码问答与分析记录，按主题一文件
├── repo/         # 各仓库的 git worktree，需要修改代码时按需创建
└── run/          # run 指令索引 run.md 与各指令目录（含 local/ 敏感数据）
```

- 建区只创建 `status.yaml` 与 `context.md`；`story/`、`doc/`、`run/`、`repo/` 在首次产生文件或检出 worktree 时创建。
- `run/*/local/` 被 `.gitignore` 忽略，只留本地，不入库、不随归档提交。
- 代码检索优先 `$work/repo/<repo-name>/`，没有所需仓库时用 `$root/repo/<repo-name>/`（只读）。
