---
workflow: example
short: ex
triggers: 示例工作流, example
summary: 一句话说明这个工作流在什么场景下使用
---

# example 示例工作流

> 工作流 = **状态机 + 命令编排**：规定工作状态如何流转、每个环节引用哪条命令、环节前后如何回写 `$work/status.yaml`。
> 命令的准入准出仍以 `harness/cmd/` 下的命令文件为唯一权威，本文件不重复命令正文。
> 复杂独立能力引用 `harness/reference/` 中的文档（reference 必须被命令或工作流引用后才能加载）。
>
> 复制本文件到 `harness/workflow/` 并改名（`_` 开头不参与路由），即被 scan-routes.sh 注册为工作流。

## 适用场景

（收到什么意图时，AGENTS 应识别为本工作流；与其他工作流的边界）

## 状态流转

（状态机：这里的状态值就是 `$work/status.yaml` 中 `status` 的合法取值；异常可进入 blocked）

```
initialized → ... → completed
```

| 状态 | 含义 | 进入条件 |
|------|------|----------|
| initialized | 工作区已创建 | `work` 完成 |
| | | |
| completed | 工作完成并收尾 | 终态 |

## 各环节与命令映射

| # | 环节 | 命令 | 产物 | 完成后状态/进度 |
|---|------|------|------|----------------|
| 1 | 环节名 | `/tack <command>` | 文件或结果 | status / progress 字段 |

## 各环节说明

1. **环节名**
   - 输入：
   - 动作与引用命令：
   - 按需参考的 reference：

## 状态回写要求

- 每个环节开始前更新 `$work/status.yaml` 的 `current.stage` / `current.task` / `current.next` 与 `updated_at`
- 每个环节完成并经人工确认后，置 `progress` 对应开关为 true、推进 `status`
- 阻塞时置 `status: blocked` 并在 `current.next` 写明阻塞原因与等待项
