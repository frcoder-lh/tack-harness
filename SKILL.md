---
name: "tack"
version: "V0.0.10"
description: "编程工作流 skill，本体只做引导：空目录执行即初始化 tack 空间（物化 AGENTS.md + harness 骨架），随后加载 AGENTS.md 完成命令路由。覆盖需求规划 spec/plan、编码 code、单测 testcode、改 bug、Git 提交/推送/合并/冲突、知识沉淀 record 等开发全流程；命令支持中英文触发词与简写，可省略 /tack 前缀或用自然语言描述意图。"
---

# tack —— 编程工作流引导器

skill 本体职责单一：**把 tack 安装进项目空间，并引导加载 AGENTS.md 完成命令路由**。工作流、命令、规则、脚本调用约定、核心纪律全部是空间内的文件（`AGENTS.md`、`harness/`），本文件不重复——进入 tack 空间后一切以 `$root/AGENTS.md` 为准。

## 调用方式

- `/tack <命令|简写|触发词> [参数]`（显式）
- 直接输入 `<命令|简写|触发词> [参数]`（省略 `/tack`）
- 自然语言描述意图（如「我要做需求规划」「提交代码」「解决合并冲突」），由 skill 语义识别后路由

## 启动流程

### 1. 判定 tack 空间（确定 `$root`）

从当前工作目录向上查找，第一个内容包含「本空间由tack harness驱动」的 `AGENTS.md` 所在目录即为 `$root`。

### 2. 按目录状态分流

- **空目录（无 AGENTS.md 且目录为空）**：执行 `init-tack <目录>`——自动确保 Git 可用、物化 tack 空间骨架（AGENTS.md、harness/、wiki/、space/ 等）、将该目录初始化为 Git 仓库并完成框架首次提交；随后按 `init` 命令引导项目信息与仓库接入。
- **非空且不是 tack 空间**：不改动任何文件，提示用户在空目录执行 `/tack`，或经用户显式确认后再初始化。
- **已是 tack 空间**：进入第 3 步。

`init-tack` 脚本位于 skill 安装目录（注意双层 `tack`：外层是 skill 名，内层是空间骨架目录名）：

| 平台 | TRAE 国内版 | TRAE 国际版 |
|------|------------|------------|
| Windows | `%USERPROFILE%\.trae-cn\skills\tack` | `%USERPROFILE%\.trae\skills\tack` |
| macOS/Linux | `~/.trae-cn/skills/tack` | `~/.trae/skills/tack` |

Windows（PowerShell；必须带 `-ExecutionPolicy Bypass`，路径参数一律用正斜杠；`run.ps1` 会自动定位 Git for Windows 的 bash.exe，缺失时通过 winget 自动安装）：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.trae-cn\skills\tack\tack\harness\script\run.ps1" init-tack "D:/path/to/workspace"
```

macOS / Linux：

```sh
sh ~/.trae-cn/skills/tack/tack/harness/script/init-tack.sh /path/to/workspace
```

### 3. 加载并遵从 AGENTS.md

读取 `$root/AGENTS.md`：若工作流与命令路由尚未加载，按其「加载 tack harness」一节执行 `scan-routes list`。此后的输入解析（`scan-routes resolve` 精确路由与语义识别兜底）、脚本跨平台调用约定、工作流状态引导与全部核心纪律，均以 `$root/AGENTS.md` 为唯一权威，本文件不再重复。
