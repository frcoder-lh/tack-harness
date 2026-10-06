---
command: update
short: u
triggers: 更新, 更新skill, update, update skill
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
   - 动作: 远端有新版本时，先展示「本次更新内容」让用户了解变更再继续：同时拉取 `skill_update_url` 仓库的 `raw/master/CHANGELOG.md` 与 `CHANGELOG.en.md`，分别抽取「本机版本（不含）→ 最新版本」区间的全部版本段落，中英双语分段向用户展示（多版本升级展示区间所有段落；按用户语言可只转述对应语言段）；任一语言拉取失败或段落缺失时该语言提示变更说明不可得，不阻塞另一种语言与更新流程
   - 动作: 若版本一致且无本地差异（见第 3 步），提示"已是最新"并结束

2. **更新本机 skill**（远端有新版本时执行）
   - 动作: 执行固定流程脚本把本机已安装 skill 更新到最新版本（定位本机 skill 安装目录 → 下载该版本 release 源码 → 完整备份旧目录后整体清空覆盖（SKILL.md/README.md/README.en.md/CHANGELOG.md/CHANGELOG.en.md/contact.png/install.sh/tack/，旧版残留文件一并清除）→ 校验版本号）：
     `sh $root/harness/script/skill-update.sh <skill_update_url> <最新tag> --tack-root $root/.tack`（Windows 经 run.ps1 启动）
   - 临时产物边界：下载解压目录落 `$root/.tack/tmp/` 下、脚本结束自动清理；旧版 skill 完整备份落 `$root/.tack/backup/skill-<时间戳>/`（回滚用，保留不自动删除，与第 6 步的 `harness-<时间戳>/` 备份同级）
   - `--skill-root <path>` 可省略：脚本按 install.sh 的 agent 预设路径自动探测；探测到多个或零个时脚本报错，向用户询问本机 tack skill 安装目录后以 `--skill-root` 重试
   - **失败即中止**：下载失败/无网络时提示可手动安装最新 skill 后重试，不继续后续步骤——本机 skill 未更新到最新版时，第 3 步的文件对比会拿到旧版内容
   - 版本一致时跳过本步

3. **检测本地改动**
   - 动作: 对比 skill 安装目录的 `tack/harness/`（已更新到最新版，作为新版来源）与 `$root/harness/`，对待更新的目录（`script/`、`template/`、`reference/`、`workflow/`、`cmd/`）逐个文件分类：
     - **新增**: 远端有、本地无 → 直接列入新增清单
     - **本地已修改**: 同名文件内容不一致 → 列入融合候选清单（可能是用户本地改动，也可能是远端新版本变更，需结合版本号与 diff 判断）
     - **一致**: 内容相同 → 跳过
   - 动作: 空间根 `.gitignore` 单独对比：对比 `<skill>/tack/.gitignore`（新版模板）与 `$root/.gitignore`（用户当前），按同样的新增/本地已修改/一致分类；`.gitignore` 不在 `harness/` 下，故单独处理
   - 以下内容不参与对比，永不覆盖：`AGENTS.md`（含项目信息区块）、`cmd/` 中用户自建文件、`rule/`、`wiki/`、`space/`
   - 临时产物约束：本步对比/diff 产生的临时文件一律放 `$root/.tack/tmp/`，本步结束后及时清理，禁止写系统临时目录

4. **提炼融合点**
   - 动作: 对每个"本地已修改"的文件，阅读 diff 内容，将差异总结提炼为**功能点**（一句话描述该改动实现了什么，如"init-tack.sh 增加了 -n 防覆盖参数"、"plan 命令合并了 task 拆解能力"），形成融合点清单：
     ```
     文件: harness/script/xxx.sh
       - 本地功能点: <本地版本的改动描述>
       - 新版功能点: <远端新版本的改动描述>
       - 冲突情况: <是否修改了同一处逻辑>
     ```
   - 原则: 提炼必须基于 diff 实际内容，禁止臆测；冲突与可自动合并的改动要分开标注

5. **用户确认融合方案**
   - 动作: 展示新增清单 + 融合点清单，逐文件询问用户处理方式：
     - **采用新版**: 放弃本地改动，直接用新版覆盖（本地改动保留在备份中）
     - **保留本地**: 不更新该文件
     - **融合**: 以某一方为基础，将另一方功能点合并进来（由 AI 执行融合并展示结果，用户确认后落盘）
   - 输入: 用户逐文件确认，或给出一个统一的默认策略（如"全部融合"）
   - 约束: 每个融合点必须得到用户明确确认后才能写入文件，禁止未确认直接融合

6. **备份**
   - 动作: 将 `$root/harness` 备份到 `$root/.tack/backup/harness-<timestamp>/`
   - 动作: 提示用户备份位置，说明放弃本地改动时可从备份找回

7. **执行更新**
   - 动作: 按用户确认的方案执行：
     - 新增文件直接复制
     - "采用新版"的文件用新版覆盖
     - "保留本地"的文件跳过
     - "融合"的文件写入经用户确认后的融合结果
     - `cmd/` 只增补新增命令文件，不覆盖同名文件
     - `$root/.gitignore` 按同样的新增/覆盖/保留/融合流程处理（与 `harness/` 内文件一致，无特殊规则）
   - 文件覆盖阶段不触碰 AGENTS.md（项目信息区块仅由下一步 project.sh 单独写入 skill_version，其余字段一律不动）

8. **验证与收尾**
   - 动作: 执行 `sh $root/harness/script/scan-routes.sh list $root/harness` 确认工作流与命令路由正常
   - 动作: 对执行过"融合"的脚本文件执行 `sh -n` 语法校验，不通过则回滚该文件并提示用户
   - 动作: 调用 project.sh 把新版本写入 AGENTS.md 项目信息区块（禁止手工编辑 YAML）：
     `sh $root/harness/script/project.sh skill-version $root <新版本> --no-commit`（Windows 经 run.ps1 启动）；`--no-commit` 表示由下一步框架提交统一入库
   - 动作: 引导老空间接入自动更新检查（一次性，仅当以下任一缺失时执行；新空间经 init-tack 物化已自带）：
     - `close` / `evolution` / `record` / `help` 命令文件缺少「版本检查（更新提醒挂载点）」步骤时，经用户确认后按本机 skill 的 `tack/harness/cmd/` 同名文件同节内容增补（检查命令与输出协议）
     - `$root/.gitignore` 缺少 `.tack/` 条目时追加一行（tack 本地运行时数据根：log/backup/tmp/state，含 check-update.sh 的本机状态文件，不入库；本项为框架强制兜底——即便用户对 `.gitignore` 选择「保留本地」，`.tack/` 也必须被忽略，否则运行时数据会误入空间仓库）
   - 动作: 展示备份位置与本次更新摘要；摘要须含**实际落盘清单**（基于第 7 步执行事实：新增/覆盖/融合的文件逐个列出），禁止臆测

## 框架自动提交（无需用户操作）

- 动作: 更新落盘并通过验证后，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): update harness"`，把 harness 更新结果与 skill_version 变更自动提交到 tack 空间根仓库；无变更自动跳过；`.tack/` 已被忽略不入库
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] scan-routes.sh list 正常输出工作流与全部命令
- [ ] 本机 skill 的 SKILL.md version 已更新为最新版本号（第 2 步执行过时）
- [ ] 所有"本地已修改"文件均已按用户确认的方案处理，无遗漏
- [ ] 融合文件通过 `sh -n` 校验，融合结果经用户确认
- [ ] 用户自定义的 cmd、rule 未被改动；AGENTS.md 项目信息仅 skill_version 经 project.sh 更新，其余字段不变
- [ ] skill_version 已更新为最新版本号
- [ ] `close` / `evolution` / `record` / `help` 命令文件含版本检查步骤且 `.gitignore` 忽略 `.tack/`（老空间本次经确认补写，新空间已自带）

## 下一步建议

- 执行 `help` 查看是否有新增工作流或命令
