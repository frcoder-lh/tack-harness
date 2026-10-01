---
command: work
short: w
triggers: 工作区, 新建工作区, 切换工作区, 分支合并, 分支变基, 合并分支, 变基分支, work
params: [目的或分支名]
summary: 工作区管理——新建、重命名、切换、列出工作区（space/<YYYYMMDD>-<branch>/）；意图分流支持 branch-op 分支级 merge/rebase，自动推断服务并登记到 AGENTS.md
---

# work 工作区管理

> 工作区位于 `$root/space/<workspace>/`；**目录命名约定：`<workspace>` = `<YYYYMMDD>-<branch>`**（如 `20261001-user-login`），日期前缀使 `space/` 下按目录名排序即按创建时间排序；worktree 检出的 git 分支名仍为 `<branch>`（不含日期），`work_id` 默认与分支同名。项目信息（含 work 列表）维护在 AGENTS.md 项目信息区块。

## 前置准入条件

- 已是 tack 空间（`$root/AGENTS.md` 存在且含项目信息区块）
- 新建工作区前，`$root/repo/` 下建议至少有一个仓库（无仓库时创建占位工作区，稍后可用 worktree 补建）

## 指令内容

先做第一层意图分流：

- **分支操作（branch-op）**：输入明确指向「两个已存在分支之间的集成」，形如「把 A merge/合并 到 B」「将 A rebase/变基 到 B」，同时给出源分支、目标分支与操作词、且不含业务需求 → 走下文「分支操作（branch-op）」精简流程，完成后由 branch-op 工作流承接
- **工作区管理**：其余意图识别为四类之一：**新建 / 重命名 / 切换 / 列出**

判定边界：单独说「合并/merge」且指向当前工作区交付，是 development 收尾的 git 组 `merge` 命令；仅当输入给出「源分支 A → 目标分支 B」两个分支、目的纯为分支搬运时才判定为 branch-op。拿不准归属时先向用户确认。

### 新建工作区

1. **获取工作区目的**
   - 输入: 工作区目的描述（如「用户登录功能」）

2. **澄清具体意图**（目的已具体到能判断要解决的问题与改动范围时，跳过本步）
   - 判定: 描述宽泛、存在多种解读（如「优化下单」「修复支付问题」）即视为意图不明确，不得带着模糊目的直接命名
   - 动作: 结合 AGENTS.md 项目信息区块的 keywords、service_repo_mapping（`wiki/manifest.md` 存在时一并参考），给出 3 个左右可能的具体意图候选，每条一句话说明对应要解决的问题方向；用户可单选、组合多个候选或自行补充
   - 输入: 用户选定后固化为明确的目的描述；一次澄清仍不明确则继续追问，直到问题边界可判断

3. **生成并确认分支名**（澄清意图之后才进行命名）
   - 动作: 依据明确后的目的，生成 3 个英文 kebab-case 分支名候选
   - 输入: 用户选择候选或自行输入；展示最终名称并请用户确认

4. **自动推断需要的服务**
   - 输入: 工作区目的 + AGENTS.md 项目信息区块的 service_repo_mapping（主数据源，必然存在）
   - `wiki/manifest.md` 存在时一并读取，补充职责等上下文；不存在不影响推断（wiki 文件按需物化）
   - 动作: 根据目的关键词推断涉及的服务/仓库，列出推断结果由用户多选确认（可全部取消）

5. **创建工作区**
   - 动作: 执行
     `sh $root/harness/script/work.sh $root <branch> <已选仓库名...>`
     脚本自动取当天日期生成工作区目录 `space/<YYYYMMDD>-<branch>/` 扁平骨架（status.yaml、input.md、repo/），并为每个仓库创建 git worktree 到 `space/<YYYYMMDD>-<branch>/repo/<repo-name>`（worktree 检出分支仍为 `<branch>`）
   - 解析输出: 脚本末尾输出结果行 `WORKSPACE=<工作区目录名>` 与 `BRANCH=<安全化分支名>`（工作区已存在时同样输出），第 6 步一律使用 `WORKSPACE` 值拼路径，不得自行按分支名猜目录

6. **登记并切换上下文**
   - 动作: 用上一步的 `WORKSPACE` 值执行
     `sh $root/harness/script/project.sh work-add $root <branch> "<目的描述>" "$root/space/<WORKSPACE>" <branch> "<服务1,服务2>"`
     在 AGENTS.md 项目信息区块追加 work 条目（work_id/branch 为分支名，work_path 为带日期前缀的实际目录）；为上下文赋值 `$work=$root/space/<WORKSPACE>`

7. **输出开场知识清单（roster，只列不读）**
   - 动作: 上下文就绪后，给用户一份「一行一项」的知识清单，**不贴正文**，需要时再按路径读取：
     1. `$root/wiki/` 下已存在的页面（manifest / code-understanding / business-understanding / decisions，标注各自用途一句话）
     2. `$root/wiki/code-understanding.md`「工作区分析文档索引」中与本次已选仓库相关的分析文档（含基准 commit）；
        对每份文档取对应 worktree 当前 HEAD，与基准不一致时标注「可能已过时（偏离 N 提交），必要时先跑 ask 更新」
     3. **冷仓库提示**：已选仓库在索引中无任何分析记录时，提示「该仓库尚无分析文档，建议在 spec/plan 前执行 `ask <仓库名>` 整体分析」（仅建议，不自动执行）
   - 边界: 清单是可选读的导航，不把 wiki 全文塞入上下文；知识不足时按三级降级取用（wiki → `$work/wiki/` → 直接读代码，代码永远是真源，见 development 工作流「上下文加载原则」）

### 分支操作（branch-op）

> 本流程只建区与准备，后续状态流转按 `harness/workflow/branch-op-workflow.md` 执行。
> 不录入需求、不做 ask/spec/plan、不做审查与测试（跳过项以工作流文件为准）。

1. **解析分支操作参数**
   - 动作: 从原始输入解析 op（「合并」→merge，「变基」→rebase）、源分支 A、目标分支 B
   - 边界: 无法同时解析出两个分支、或操作词有歧义（如只说「处理一下 A 和 B」）时，追问补齐，不得带模糊参数建区

2. **确认涉及仓库**
   - 动作: 在 `$root/repo/` 各仓库内 `git fetch origin --prune`，检查 A、B 是否存在（远端优先、本地兜底）；逐仓库记录检查结果
   - 输入: 多个仓库同时具备这两个分支时，列出清单由用户多选确认；仅一个仓库满足时直接请用户确认；无仓库满足时回报事实并停止

3. **生成并确认工作区名**（意图明确之后才命名）
   - 动作: 生成 3 个英文 kebab-case 候选，如 `bop-<a>-to-<b>`（分支名中的 `/` 替换为 `-`）
   - 输入: 用户选择候选或自行输入，确认最终名称

4. **创建工作区骨架（不建默认 worktree）**
   - 动作: 执行
     `sh $root/harness/script/work.sh --no-worktree $root <branch>`
     只生成 `space/<YYYYMMDD>-<branch>/` 下的 status.yaml、input.md、wiki/ 与空 repo/ 占位
   - 解析输出: 取结果行 `WORKSPACE=<工作区目录名>`，后续步骤以该值为准

5. **prepare：临时分支与工作 worktree**
   - 动作: 逐仓库执行
     `sh $root/harness/script/branch-op.sh prepare $root space/<WORKSPACE> <repo> <op> <A> <B>`
     fetch 后创建 `A-<时间戳>`、`B-<时间戳>` 临时分支，并为工作分支（merge 取 B-ts，rebase 取 A-ts）创建 worktree 到 `space/<WORKSPACE>/repo/<repo>`
   - 解析输出: `BRANCH_OP_TS`、`BRANCH_OP_SOURCE_TMP`、`BRANCH_OP_TARGET_TMP`、`BRANCH_OP_WORKING`

6. **登记并切换上下文**
   - 动作: 执行
     `sh $root/harness/script/project.sh work-add $root <branch> "branch-op: <op> <A> → <B>" "$root/space/<WORKSPACE>" <branch> "<repo1,repo2>"`
     并直接编辑 `$work/status.yaml`：`workflow` 改为 `branch-op`、`status` 置 `preparing`、`services` 写入选定仓库，且按 `harness/template/work-status.yaml` 的结构写入 `branch_op` 区块（每仓库的临时分支名与 pushed: false）
   - 为上下文赋值 `$work=$root/space/<WORKSPACE>`

7. **跳过常规开场动作**
   - 边界: 不输出 roster、不引导 input.md/spec；登记完成即按 branch-op 工作流进入 integrate 环节

### 重命名工作区

1. 输入新的目的描述；描述宽泛时按「新建工作区」第 2 步先澄清意图，再生成并确认新分支名
2. 重命名工作区目录：`space/<原日期>-<old>/` 改为 `space/<原日期>-<new>/`——**保留原创建日期前缀**（排序位置与创建事实不变），只替换分支名部分
3. 遍历该工作区每个仓库，在 worktree 内执行 `git branch -m <old> <new>`
4. 直接编辑 AGENTS.md 项目信息区块中该条目（work_id / work_path / branch）与 `$work/status.yaml`（work_id / work_dir / branch）；若重命名的是当前工作区，更新 `$work`

### 切换工作区

1. 读取 AGENTS.md 项目信息区块的 work 列表（或扫描 `space/` 目录），高亮当前工作区
2. 输入目标工作区；目标不存在时询问是否新建
3. 以目标 work 条目的 `work_path`（即 `$root/space/<YYYYMMDD>-<branch>`）为上下文赋值 `$work`，重新读取该工作区 status.yaml（不相信上下文里的旧内容）；不要凭分支名自行拼目录
4. 按「新建工作区」第 7 步输出该工作区的开场知识清单（wiki 页面 + 相关分析文档新鲜度 + 冷仓库建议），只列不读

### 列出工作区

1. 以表格展示全部工作区：work_id / 描述 / 状态 / 分支（可附工作区目录名），当前工作区标记「（当前）」；按工作区目录名排序即按创建时间排序
2. 可接受用户序号或分支名输入，直接进入切换

## 框架自动提交（无需用户操作）

- 动作: 新建路径的提交已由 work.sh、project.sh 自动完成；重命名等直接编辑过 AGENTS.md / status.yaml 的路径，结束前执行 `sh $root/harness/script/space.sh commit $root "chore(tack): workspace <branch>"` 兜底（无变更自动跳过）
- 边界: 遵守 `harness/rule/git-boundary.md`；工作区内的分支重命名（`git branch -m`）作用于代码仓库，属用户仓库操作

## 后置完成检验

- [ ] `space/<YYYYMMDD>-<branch>/status.yaml`（含正确的 work_dir、branch）、`input.md` 已生成
- [ ] 已选仓库在 `space/<YYYYMMDD>-<branch>/repo/` 下有可用 worktree（检出分支为 `<branch>`）
- [ ] AGENTS.md 项目信息区块的 work 列表与磁盘一致
- [ ] 常规建区：已输出开场知识清单（roster）——wiki 页面与相关分析文档（含新鲜度），冷仓库已建议 ask；未向上下文塞入 wiki 全文
- [ ] branch-op：op/A/B 已解析且仓库经用户确认；prepare 成功，status.yaml 已置 `workflow: branch-op`、`status: preparing` 并写入 `branch_op` 区块（临时分支名齐全）

## 下一步建议

- 常规建区：向 `$work/input.md` 录入原始需求，然后执行 `spec`
- branch-op：执行 `branch-op.sh integrate` 进入集成环节，冲突转 `solve` 后 `continue`；完成后 `push`（rebase 须先取得用户当次授权），收尾在 `close`
