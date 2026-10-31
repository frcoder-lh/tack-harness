---
command: repo
short: rp
triggers: 新建仓库, 建仓, 新建代码仓库, 仓库更新, 更新仓库, 拉取仓库, 拉取主仓库, create-repo, createrepo, create repo, new repository, repo fetch, update repo
params: [建仓目的 | fetch [仓库名...]]
summary: 管理代码主仓库（$root/repo/）——新建并纳入项目空间管理，或更新全部/指定主仓库到远端最新
---

# repo 代码主仓库管理

> 本命令管理 `$root/repo/` 下的代码主仓库（worktree 的只读基准）。
> 当前工作区 worktree（`$work/repo/`）的拉取与同步走 `fetch` 命令。

## 前置准入条件

- 已是 tack 项目，`$root/repo/` 目录存在
- 动作已判定：无参数或意图不明时先确认是「新建仓库」还是「更新仓库（fetch）」
- 更新动作遵守 `harness/rule/git-boundary.md`——主仓库只读基准，接入与远端同步只经 `harness/script/repo.sh` 执行

## 指令内容

### 新建仓库

1. **确定所属项目与建仓目的**
   - 项目: 按当前工作区的 `project`，或执行 `sh $root/harness/script/project.sh project-list $root` 选择；项目不明确时先向用户确认
   - 输入: 建仓用途（承载什么服务、技术栈、与已有服务的关系）

2. **建议仓库名称**
   - 动作: 结合项目关键词与用途，给出 2-3 个英文 kebab-case 仓库名建议（命名遵守 `harness/rule/naming.md`），用户选择或自行输入后确认

3. **创建仓库**
   - 动作: `mkdir -p $root/repo/<name>` 后在其中执行 `git init`；生成最小 README（仓库名 + 一句话用途）与合适的 .gitignore（按技术栈）

4. **关联远端（可选）**
   - 输入: 用户是否已有远端仓库地址
   - 动作: 有地址则执行 `git remote add origin <url>`；没有则提示先在代码平台建仓，稍后可补

5. **登记映射**
   - 动作: 执行 `sh $root/harness/script/project.sh project-service-repo $root "<项目名>" "<服务名称>" "<repo 名>" "<repo_git，未关联远端则空串>" "repo/<name>"` 追加当前项目的 `service_repo_mapping`，并按 `harness/rule/wiki-write.md` 物化/更新 `wiki/<project>/config/services.md` 与 `wiki/<project>/code/repos.md` 的仓库/服务真实行，同步登记分类索引；环境、账号、配置等事实有真实来源才填写，不臆造锚点；提示用户补全服务信息

### 更新仓库（fetch）

1. **确定更新范围**
   - 输入: 参数中的仓库名（可多个）；未给出仓库名时默认全部已接入主仓库
   - 动作: 指定仓库须存在于 `$root/repo/<name>/`，否则列出可用仓库并请用户重新选择

2. **同步主仓库**
   - 动作:
     - 全部仓库: `sh $root/harness/script/repo.sh fetch $root`
     - 指定仓库: `sh $root/harness/script/repo.sh fetch $root <repo-name...>`
   - 脚本职责（逐仓库复用 `harness/script/git-fetch-helper.sh sync`）：`git fetch --all --prune` → 校正上游为 `origin/<当前分支>` → `git pull` → 汇报 `git status -sb`，输出 `FETCH_RESULT=` 结果行
   - 结果行与退出码: `ok`（0）/ `conflict`（10）/ `detached`（11）/ `no-remote`（11）/ `no-upstream`（11）/ `failed`（1）

3. **结果汇总**
   - 动作: 按仓库列出 ok / detached / no-remote / no-upstream / conflict / failed；主仓库出现冲突说明只读基准被本地改动破坏，停止自动处理并提示用户确认改动来源后处理，不做静默取舍

## 框架自动提交（无需用户操作）

- 新建仓库: 第 5 步 `project.sh project-service-repo` 执行时自动把 `tack.yaml` 映射变更提交到 tack 空间根仓库（无变更自动跳过）；wiki 物化变更随后执行 `sh $root/harness/script/space.sh commit $root "chore(tack): register repo <name>"` 统一收尾
- 更新仓库: `repo/` 已被 .gitignore 忽略，同步不产生空间仓库变更，无需提交
- 边界: 遵守 `harness/rule/git-boundary.md`；新代码仓库内的 README / .gitignore 首次提交由用户经 `commit` 命令发起，框架不代提

## 后置完成检验

- 新建仓库:
  - [ ] `repo/<name>/` 下 `git status` 正常
  - [ ] README 已创建，远端（若提供）已关联
  - [ ] `tack.yaml` 的服务仓库映射已登记
- 更新仓库:
  - [ ] 每个目标仓库的 `FETCH_RESULT` 明确，失败与需人工介入项已逐条列出
  - [ ] 主仓库工作区无冲突残留；出现冲突时已提示用户确认改动来源

## 下一步建议

- 新建后: 执行 `work` 创建工作区时即可勾选该仓库
- 更新后: 使用最新基准继续 `work` / `code`；工作区 worktree 需要同步时执行 `fetch`
