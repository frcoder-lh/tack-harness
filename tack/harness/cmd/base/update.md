---
command: update
short: u
triggers: 更新, 更新skill, update, update skill
params: 无
summary: 对比版本并更新 harness 与 AGENTS.md；基于出厂原件做三方分类，批量采用纯上游变化、保留定制，真实冲突集中裁决
---

# update 更新 harness

## 前置准入条件

- 已是 tack 空间
- `tack.yaml`（旧空间为 AGENTS.md 项目信息区块）中 `skill_update_url` 为出厂固定值（`https://github.com/frcoder-lh/tack-harness`）；`skill_version` 由 init 自动填充，老空间为空时以本机已安装 skill 的 SKILL.md 版本号为准

## 指令内容

1. **检测版本**
   - 动作: 执行 `sh $root/harness/script/project.sh space-info $root` 读取 `SKILL_VERSION` 与 `SKILL_UPDATE_URL`（版本为空时取本机已安装 skill 的 SKILL.md front matter 版本号）
   - 动作: 复用 `harness/script/common.sh` 的 `tack_latest_release_tag` 解析最新 tag（已含 Windows `curl --ssl-no-revoke` 回退，禁止自写 curl/wget）：macOS/Linux 执行 `sh -c '. "$root/harness/script/common.sh"; tack_latest_release_tag "<skill_update_url>"'`；Windows 把同一内容写入 `$root/.tack/tmp/` 下的临时 `.sh` 后按 `windows-env.md` 用 Git for Windows `bash -l` 执行
   - 动作: 无网络或解析失败时以本机版本为准并提示
   - 动作: 远端有新版本时，先展示「本次更新内容」让用户了解变更再继续：同时拉取 `skill_update_url` 仓库的 `raw/master/CHANGELOG.md` 与 `CHANGELOG.en.md`，分别抽取「本机版本（不含）→ 最新版本」区间的全部版本段落，中英双语分段向用户展示（多版本升级展示区间所有段落；按用户语言可只转述对应语言段）；任一语言拉取失败或段落缺失时该语言提示变更说明不可得，不阻塞另一种语言与更新流程
   - 动作: 版本一致时跳过第 2 步，直接进入第 3 步；仅 SAME / LOCAL / LOCAL_ONLY 时说明上游内容已同步、本地定制保留并结束

2. **更新本机 skill**（远端有新版本时执行）
   - 动作: 执行固定流程脚本把本机已安装 skill 更新到最新版本（定位本机 skill 安装目录 → 下载该版本 release 源码 → 完整备份旧目录后按 `harness/script/common.sh` 的 `TACK_SKILL_FILES` 分发包清单整体清空覆盖（旧版残留文件一并清除）→ 校验版本号）：
     `sh $root/harness/script/skill-update.sh <skill_update_url> <最新tag> --tack-root $root/.tack`
   - 临时产物边界：下载解压目录落 `$root/.tack/tmp/` 下、脚本结束自动清理；旧版 skill 完整备份落 `$root/.tack/backup/skill-<时间戳>/`（回滚用，保留不自动删除，与第 6 步的 `update-<时间戳>/` 备份同级）
   - `--skill-root <path>` 可省略：脚本按 `harness/script/common.sh` 的 agent 预设路径自动探测；探测到多个或零个时脚本报错，向用户询问本机 tack skill 安装目录后以 `--skill-root` 重试
   - **失败即中止**：下载失败/无网络时提示可手动安装最新 skill 后重试，不继续后续步骤——本机 skill 未更新到最新版时，第 3 步的文件对比会拿到旧版内容
   - 版本一致时跳过本步

3. **检测本地改动**
   - `<skill>` 指本机 skill 安装目录：第 2 步输出的路径；第 2 步跳过时取自动探测结果或 `--skill-root` 指定值
   - 动作: `$root/tack.yaml` 不存在但 `$root/AGENTS.md` 含旧版项目信息区块时，先执行 `sh $root/harness/script/project.sh migrate $root --no-commit` 把登记迁出 AGENTS.md（迁移失败即中止），避免后续 AGENTS.md 裁决覆盖旧登记；旧版单项目区块（`project:`）无法用 migrate 迁移，按 README 用 `<skill>/tack/harness/script/harness-resync.sh $root` 一次性重建
   - 动作: 执行 `sh $root/harness/script/harness-baseline.sh classify $root <skill>/tack`，一次分类 harness/、AGENTS.md 与 .gitignore：
     - `ADDED`：上游新增；`UPSTREAM`：本地等于出厂原件、仅上游变化 → 批量采用
     - `LOCAL` / `LOCAL_ONLY`：本地定制或自建 → 保留
     - `SAME`：一致 → 跳过
     - `CONFLICT`：本地与上游均相对原件变化 → 三方 diff 后列入裁决清单
     - `CHANGED`：缺少出厂基线、两侧不同 → 保守列入裁决清单
     - `LOCAL_DELETED` / `UPSTREAM_DELETED`：一侧删除 → 单列删除影响与引用，交用户决定
   - 出厂原件位于 `$root/.tack/state/baseline/`，新空间由 init 自动保存。旧空间仅可为与已知上游内容相同的文件 seed；禁止用已定制本地内容充当原件。`tack.yaml`、wiki/、space/ 均不在本分类范围
   - 临时产物约束：本步对比/diff 产生的临时文件一律放 `$root/.tack/tmp/`，本步结束后及时清理，禁止写系统临时目录

4. **提炼融合点**
   - 动作: 只对 `CONFLICT` / `CHANGED` 及删除候选读取必要 diff，提炼功能点并给出建议，形成融合点清单：
     ```
     文件: harness/script/xxx.sh
       - 本地功能点: <本地版本的改动描述>
       - 新版功能点: <远端新版本的改动描述>
       - 冲突情况: <是否修改了同一处逻辑>
     ```
   - 按「新版变更 / 本地增补」标注并保留来源，候选可按共同原因分组
   - 原则: 提炼必须基于 diff 实际内容，禁止臆测；冲突与可自动合并的改动要分开标注

5. **用户确认融合方案**
   - 动作: 展示批量采用清单及需要裁决的候选，一次请用户选择默认策略与例外：
     - **采用新版**: 放弃本地改动，直接用新版覆盖（本地改动保留在备份中）
     - **保留本地**: 不更新该文件
     - **融合**: 以某一方为基础，将另一方功能点合并进来（由 AI 执行融合并展示结果，用户确认后落盘）
   - 输入: 用户可统一授权或指定例外；已有明确策略直接复用。未经裁决的冲突和删除候选保持原样；真实定制不得被无冲突路径覆盖

6. **备份**
   - 动作: 执行 `sh $root/harness/script/harness-backup.sh backup $root update`，记录输出的 `BACKUP_DIR`（备份 `harness/`、`AGENTS.md`、`tack.yaml`、`.gitignore`）
   - 动作: 提示用户备份位置，说明放弃本地改动时可从备份找回；恢复用 `harness-backup.sh restore` + `verify`

7. **执行更新**
   - 动作: 执行 `sh $root/harness/script/harness-baseline.sh apply-clean $root <skill>/tack`，脚本持锁重分类，只复制 ADDED / UPSTREAM 并输出 APPLIED 清单；冲突按第 5 步已确认的策略融合/采用/保留，删除候选按明确裁决处理
   - `tack.yaml` 在文件覆盖阶段不触碰（空间登记仅由第 8 步 project.sh 单独写入 skill_version，其余字段一律不动）
   - 失败恢复: 任一文件覆盖或验证失败时执行 `sh $root/harness/script/harness-backup.sh restore $root <BACKUP_DIR>`，再 `verify` 确认逐文件一致后重新开始

8. **验证与收尾**
   - 动作: 执行 `sh $root/harness/script/scan-routes.sh list $root/harness` 确认工作流与命令路由正常
   - 动作: 对执行过"融合"的脚本文件执行 `sh -n` 语法校验，不通过则从备份回滚该文件并提示用户
   - 动作: 执行 `sh $root/harness/script/harness-backup.sh verify $root <BACKUP_DIR>` 辅助核对差异范围；恢复后该命令应输出 `VERIFY_RESULT=ok`
   - 动作: 调用 project.sh 把新版本写入 `tack.yaml`（禁止手工编辑 YAML）：
     `sh $root/harness/script/project.sh skill-version $root <新版本> --no-commit`；`--no-commit` 表示由下一步框架提交统一入库
   - 动作: 引导老空间接入自动更新检查（一次性，仅当以下任一缺失时执行；新空间经 init-tack 物化已自带）：
     - `close` / `evolution` / `record` / `help` 命令文件因「保留本地」仍缺少「版本检查（更新提醒挂载点）」步骤时，经用户确认后按本机 skill 的 `tack/harness/cmd/` 同名文件同节内容增补（检查命令与输出协议）
     - `$root/.gitignore` 既无 `.*/`（默认忽略所有点开头目录）也无 `.tack/` 条目时追加 `.*/`（`.tack/` 为框架运行时数据根：log/backup/tmp/state，含 check-update.sh 的本机状态文件，绝不能入库；本项为框架强制兜底——即便用户对 `.gitignore` 选择「保留本地」，运行时数据也必须被忽略）
   - 动作: 展示备份位置与本次更新摘要；摘要须含**实际落盘清单**（基于第 7 步执行事实：新增/覆盖/融合的文件逐个列出），禁止臆测
   - 动作: 全部文件与版本验证通过后，最后对实际已采用或融合的文件执行 `sh $root/harness/script/harness-baseline.sh record $root <skill>/tack <相对文件...>`，将对应上游原件记录为下次基线；保留本地且未吸收本次上游变化的文件保持旧基线。验证失败时先恢复文件，基线保持原值

## 框架自动提交（无需用户操作）

- 动作: 更新落盘并通过验证后，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): update harness" "$root/harness" "$root/AGENTS.md" "$root/tack.yaml" "$root/.gitignore"`，把 harness 更新结果与 skill_version 变更自动提交到 tack 空间根仓库；无变更自动跳过；`.tack/` 已被忽略不入库
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] scan-routes.sh list 正常输出工作流与全部命令
- [ ] 本机 skill 的 SKILL.md version 已更新为最新版本号（第 2 步已执行）
- [ ] 三方分类完整，纯上游变化已批量处理；冲突、无基线差异与删除候选按裁决处理，未裁决文件保持原样
- [ ] 融合文件通过 `sh -n` 校验，融合结果经用户确认
- [ ] 用户自建 cmd/rule 与 AGENTS.md 本地约束已保留；基线只推进已验证文件；`tack.yaml` 仅 skill_version 经 project.sh 更新；老空间已完成必要的 migrate
- [ ] skill_version 已更新为最新版本号
- [ ] `close` / `evolution` / `record` / `help` 命令文件含版本检查步骤且 `.gitignore` 含 `.*/` 或 `.tack/`（保留本地导致缺失时本次经确认补写，新空间已自带）

## 下一步建议

- 执行 `help` 查看是否有新增工作流或命令
