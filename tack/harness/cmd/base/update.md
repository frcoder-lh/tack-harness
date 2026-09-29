---
command: update
short: u
triggers: 更新, 更新skill, update
params: 无
summary: 对比版本并更新 harness（script/template/reference/workflow），检测本地改动并提炼功能点，经用户确认后融合
---

# update 更新 harness

## 前置准入条件

- 已是 tack 空间
- AGENTS.md 项目信息区块中 `skill_update_url` 为出厂固定值（`https://github.com/frcoder-lh/tack-harness`）；`skill_version` 由 init 自动填充，老空间为空时以本机已安装 skill 的 SKILL.md 版本号为准

## 指令内容

1. **检测版本**
   - 动作: 读取 AGENTS.md 项目信息区块的 `skill_version`（为空时取本机已安装 skill 的 SKILL.md front matter 版本号）；通过 `skill_update_url` 指向仓库的最新 release tag（`Vx.y.z`）获取最新版本进行对比；无网络时以本机版本为准并提示
   - 动作: 若版本一致且无本地差异（见第 2 步），提示"已是最新"并结束

2. **检测本地改动**
   - 动作: 对比 skill 安装目录的 `tack/harness/` 与 `$root/harness/`，对待更新的目录（`script/`、`template/`、`reference/`、`workflow/`、`cmd/`）逐个文件分类：
     - **新增**: 远端有、本地无 → 直接列入新增清单
     - **本地已修改**: 同名文件内容不一致 → 列入融合候选清单（可能是用户本地改动，也可能是远端新版本变更，需结合版本号与 diff 判断）
     - **一致**: 内容相同 → 跳过
   - 以下内容不参与对比，永不覆盖：`AGENTS.md`（含项目信息区块）、`cmd/` 中用户自建文件、`rule/`、`wiki/`、`space/`

3. **提炼融合点**
   - 动作: 对每个"本地已修改"的文件，阅读 diff 内容，将差异总结提炼为**功能点**（一句话描述该改动实现了什么，如"init-tack.sh 增加了 -n 防覆盖参数"、"plan 命令合并了 task 拆解能力"），形成融合点清单：
     ```
     文件: harness/script/xxx.sh
       - 本地功能点: <本地版本的改动描述>
       - 新版功能点: <远端新版本的改动描述>
       - 冲突情况: <是否修改了同一处逻辑>
     ```
   - 原则: 提炼必须基于 diff 实际内容，禁止臆测；冲突与可自动合并的改动要分开标注

4. **用户确认融合方案**
   - 动作: 展示新增清单 + 融合点清单，逐文件询问用户处理方式：
     - **采用新版**: 放弃本地改动，直接用新版覆盖（本地改动保留在备份中）
     - **保留本地**: 不更新该文件
     - **融合**: 以某一方为基础，将另一方功能点合并进来（由 AI 执行融合并展示结果，用户确认后落盘）
   - 输入: 用户逐文件确认，或给出一个统一的默认策略（如"全部融合"）
   - 约束: 每个融合点必须得到用户明确确认后才能写入文件，禁止未确认直接融合

5. **备份**
   - 动作: 将 `$root/harness` 备份到 `$root/.backup/harness-<timestamp>/`
   - 动作: 提示用户备份位置，说明放弃本地改动时可从备份找回

6. **执行更新**
   - 动作: 按用户确认的方案执行：
     - 新增文件直接复制
     - "采用新版"的文件用新版覆盖
     - "保留本地"的文件跳过
     - "融合"的文件写入经用户确认后的融合结果
     - `cmd/` 只增补新增命令文件，不覆盖同名文件
   - 文件覆盖阶段不触碰 AGENTS.md（项目信息区块仅由下一步 project.sh 单独写入 skill_version，其余字段一律不动）

7. **验证与收尾**
   - 动作: 执行 `sh $root/harness/script/scan-routes.sh list $root/harness` 确认工作流与命令路由正常
   - 动作: 对执行过"融合"的脚本文件执行 `sh -n` 语法校验，不通过则回滚该文件并提示用户
   - 动作: 调用 project.sh 把新版本写入 AGENTS.md 项目信息区块（禁止手工编辑 YAML）：
     `sh $root/harness/script/project.sh skill-version $root <新版本> --no-commit`（Windows 经 run.ps1 启动）；`--no-commit` 表示由下一步框架提交统一入库
   - 动作: 展示备份位置与本次更新摘要

## 框架自动提交（无需用户操作）

- 动作: 更新落盘并通过验证后，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): update harness"`，把 harness 更新结果与 skill_version 变更自动提交到 tack 空间根仓库；无变更自动跳过；`.backup/` 已被忽略不入库
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] scan-routes.sh list 正常输出工作流与全部命令
- [ ] 所有"本地已修改"文件均已按用户确认的方案处理，无遗漏
- [ ] 融合文件通过 `sh -n` 校验，融合结果经用户确认
- [ ] 用户自定义的 cmd、rule 未被改动；AGENTS.md 项目信息仅 skill_version 经 project.sh 更新，其余字段不变
- [ ] skill_version 已更新为最新版本号

## 下一步建议

- 执行 `help` 查看是否有新增工作流或命令
