---
command: work
short: w
triggers: 工作区, 新建工作区, 切换工作区, 分支合并, 分支变基, 合并分支, 变基分支, work, workspace, new workspace, switch workspace, merge branches, rebase branches
params: [目的或分支名]
summary: 工作区管理——新建、重命名、切换、列出工作区（space/<YYYYMMDD>-<branch>/）；新建时只创建 status.yaml 与 context.md，story/doc/repo 等目录与 worktree 均按需懒加载；意图分流支持 branch-op 分支级 merge/rebase，按输入确定或推断服务并登记到 tack.yaml
---

# work 工作区管理

> 工作区位于 `$root/space/<workspace>/`；**目录命名约定：`<workspace>` = `<YYYYMMDD>-<branch>`**（如 `20261001-user-login`；分支名中的 `/` 在目录名中转为 `-`，如 `feature/login` → `20261023-feature-login`，保证 `space/` 下始终是单层目录），日期前缀使 `space/` 下按目录名排序即按创建时间排序；worktree 检出的 git 分支名仍为 `<branch>`（不含日期、保留 `/`），`work_id` 默认与分支同名。空间登记（`projects` 数组 + work 列表）存放在 `$root/tack.yaml`，每个工作区通过 `status.yaml` 的 `project` 归属一个项目。

## 前置准入条件

- 已是 tack 空间（`$root/tack.yaml` 存在，或 `$root/AGENTS.md` 含可用的旧版项目信息区块）
- 新建工作区只创建工作区目录、`status.yaml` 与 `context.md`，不预建 `story/`、`doc/`、`run/`、`repo/` 等目录、不检出 worktree；目录在首次产生文件或检出 worktree 时按需创建，检索代码直接使用 `$root/repo/`

## 指令内容

先做第一层意图分流：

- **分支操作（branch-op）**：输入明确指向「两个已存在分支之间的集成」，形如「把 A merge/合并 到 B」「将 A rebase/变基 到 B」，同时给出源分支、目标分支与操作词、且不含业务需求 → 走下文「分支操作（branch-op）」精简流程，完成后由 branch-op 工作流承接
- **工作区管理**：其余意图识别为四类之一：**新建 / 重命名 / 切换 / 列出**

判定边界：单独说「合并/merge」且指向当前工作区交付，是 development 收尾的 git 组 `merge` 命令；仅当输入给出「源分支 A → 目标分支 B」两个分支、目的纯为分支搬运时才判定为 branch-op。拿不准归属时先向用户确认。

### 新建工作区

> 确认原则：输入已明确给出的项目、分支、服务与目的直接采用，用一句话说明取值；只对缺失项、AI 推断项或冲突项发起确认。四项齐全时不生成候选、不重复确认，直接创建。

0. **确定所属项目**
   - 输入: 当前上下文（`$work` 已存在时取 `$work/status.yaml` 的 `project`）、`tack.yaml` 的 projects、用户输入中的项目线索
   - 动作: 输入已明确项目名且与 `tack.yaml` 的 projects 匹配时直接使用并说明，不再确认；未明确时，有当前项目且与工作区目的匹配则直接使用，否则执行 `sh $root/harness/script/project.sh project-list $root`——单项目直接使用，多项目请用户选择，无项目时引导先执行 `init` 新建项目
   - 边界: `project` 是工作区归属与项目 wiki 的依据，不得留空或自行编造

1. **获取工作区目的**
   - 输入: 工作区目的描述（如「用户登录功能」）

2. **澄清具体意图**（目的已具体到能判断要解决的问题与改动范围时，跳过本步）
   - 判定: 描述宽泛、存在多种解读（如「优化下单」「修复支付问题」）即视为意图不明确，不得带着模糊目的直接命名
   - 动作: 结合 `sh $root/harness/script/project.sh project-get $root <project>` 的 keywords、服务仓库映射（`$root/wiki/<project>/config/services.md` 存在时经 `harness/rule/wiki-read.md` 一并参考），给出 3 个左右可能的具体意图候选，每条一句话说明对应要解决的问题方向；用户可单选、组合多个候选或自行补充
   - 输入: 用户选定后固化为明确的目的描述；一次澄清仍不明确则继续追问，直到问题边界可判断

3. **提取触发词（从目的描述分词）**
   - 动作: 执行 `sh $root/harness/script/trigger-extract.sh "<目的描述>"` 取得候选触发词（逗号分隔，已去停用词与单字、中英文分别处理后合并去重），再按语义筛选并补充遗漏的核心词
   - 边界: 触发词用于切换匹配，宁多勿漏但不堆砌单字；最终以逗号分隔字符串形式传入 work-add

4. **确定分支名**（澄清意图之后才进行命名）
   - 动作: 用户已给出分支名时，按 `harness/rule/git-standards.md` 与 `harness/rule/naming.md` 校验格式及工作区冲突；通过则直接采用并说明，不生成候选、不追加确认；不通过时说明原因并请用户改名
   - 未给出时，依据明确后的目的生成 3 个英文 kebab-case 分支名候选；用户选择候选即视为确认（也可自行输入），不再单独确认最终名称
   - 边界: 分支命名遵循 `harness/rule/git-standards.md` 的分支命名约定（`<type>-<username>-<description>`）与 `harness/rule/naming.md`

5. **确定需要的服务**
   - 输入: 工作区目的 + 用户给出的服务线索 + `sh $root/harness/script/project.sh repo-list $root <project>` 的服务仓库映射（主数据源，必然存在）
   - `$root/wiki/<project>/config/services.md` 存在时一并读取，补充职责等上下文；不存在不影响推断（wiki 文件按需物化）
   - 动作: 用户已给出服务清单（如「只涉及 user-service」）时，与 `repo-list` 映射核对后直接登记，不再多选确认；未给出或指定了映射中不存在的服务时，按目的关键词推断并列出结果由用户多选确认（可全部取消或补充）；登记结果只写入工作区与 `tack.yaml`，**不建 worktree**

6. **创建、登记并切换上下文（只建上下文文件，其余目录懒加载）**
   - `<workflow>` 取值: 按目的语义选择工作流——缺陷修复取 `bugfix`、补测试取 `testing`、分支冲突解决取 `merge-conflict`，其余（含拿不准时）取 `development`；用户明确指定时直接采用。取值连同项目、分支、服务在一句话说明中给出，不单独确认；脚本经 `scan-routes.sh show` 校验工作流存在
   - 动作: 执行
     `sh $root/harness/script/command-batch.sh work-create $root <project> <branch> "<目的描述>" "<服务1,服务2>" "<触发词1,触发词2>" <workflow>`
     一次创建 status/context、登记 work、同步服务与工作流，目录保持懒加载；目的写入 context 后再补充本次原始资料
   - 解析输出: 使用 `WORKSPACE` 与 `BRANCH` 结果行确定实际路径并为上下文赋值 `$work=$root/space/<WORKSPACE>`；登记冲突时核对原条目，禁止自行猜目录覆盖

7. **输出开场知识清单（roster，只列不读）**
   - 动作: 执行 `sh $root/harness/script/command-context.sh roster $root <WORKSPACE>` 一次取回事实，据此给用户一份「一行一项」的知识清单，**不贴正文**，需要时再经 `harness/rule/wiki-read.md` 按路径读取：
     1. `WIKI` 行：项目 wiki 已存在的索引与文件（history 只列 `history/index.md`），各标一句话用途
     2. `COLD` 行（冷仓库）：已选仓库在 `code/anchors.md` 中无锚点，提示「该仓库尚无分析锚点，建议在 spec/plan 前执行 `ask <仓库名>` 整体分析」（仅建议，不自动执行）
     3. `STORY` / `DOC` / `BASE` 行：已有 story 与分析文档（主题、最近更新），`BASE` 为 `stale` 的文档标注「基于旧代码，落后 N 个提交」；新建工作区通常为空，切换工作区时用于快速续接上下文
   - 边界: 清单是可选读的导航，不把 wiki 全文塞入上下文；知识不足时按三级降级取用（项目 wiki → `$work/doc/analysis/` 与 `$work/story/*/analysis.md` → 直接读代码，代码永远是真源，见 development 工作流「上下文加载原则」）

### 分支操作（branch-op）

读取 `cmd/base/work/branch-op.md` 按其步骤执行：解析 op 与源/目标分支、确认仓库、命名、`work-create` 建区登记、`branch-op.sh prepare`、`branch-op.sh register` 写入状态与临时分支；完成后由 branch-op 工作流承接，不输出 roster。

### 重命名工作区

1. 输入新的目的描述；描述宽泛时按「新建工作区」第 2 步先澄清意图，再生成并确认新分支名（命名遵循 `harness/rule/git-standards.md`）
2. **dry-run 展示完整变更计划**：
   `sh $root/harness/script/work.sh rename $root <old-work-id> <new-work-id> [new-branch] --dry-run`
   计划含目录（保留原创建日期前缀）、work_id、分支、各仓库 worktree 分支、status.yaml、tack.yaml 工作条目、branches[] 与全部子工作区 parent_workspace；新 ID/目录/分支冲突由脚本以退出码 4 拦截
3. **用户确认后 apply**：
   `sh $root/harness/script/work.sh rename $root <old-work-id> <new-work-id> [new-branch] --apply`
   脚本按「分支 → worktree 目录 → 工作区文件 → status.yaml → tack.yaml → branches[] → 子工作区关联」顺序执行；子区状态备份、回滚与提交均纳入事务；中途失败输出 `ROLLBACK=complete|incomplete`，完整回滚可重试，不完整时按脚本列出的残留项人工处理
4. 成功后脚本输出 `RENAME_RESULT=applied`、`RECONCILE=ok` 并自动提交空间仓库；若重命名的是当前工作区，把 `$work` 更新为计划中的新目录

### 切换工作区

1. 执行 `sh $root/harness/script/project.sh work-resolve $root "<查询词>"`，一次返回最高优先级候选（work_id/branch 精确 → trigger 精确 → trigger 子串 → 描述包含）
2. 返回 0 表示唯一候选，进入第 3 步；2 表示多候选，进入第 4 步；1 表示未命中，先做语义关键词匹配，仍无候选时进入第 5 步；登记与目录偏差由 evolution 校准
3. 以目标 work 条目的 `work_path`（即 `$root/space/<YYYYMMDD>-<branch>`）为上下文赋值 `$work`，读取该工作区 status.yaml（上下文已有且未变化时复用，否则读取最新），并以其 `project` 作为当前项目；不要凭分支名自行拼目录
4. **多候选选择**：以表格列出候选（work_id / 描述 / 触发词 / 状态），请用户选择；用户选中后，把本次输入的查询词（及其分词）通过 `work-trigger` 追加到选中工作区的 `trigger_words`（`sh $root/harness/script/project.sh work-trigger $root <work_id> "<词1,词2>"`，脚本自动去重并跳过等于 work_id/branch 的词），使下次相同输入直接命中；随后进入第 3 步
5. **无命中**：询问是否新建工作区
6. 按「新建工作区」的「输出开场知识清单」步骤输出该工作区的 roster（wiki 页面 + 分析文档新鲜度 + 冷仓库建议），只列不读

### 列出工作区

1. 执行 `sh $root/harness/script/project.sh work-list $root` 读取工作区登记（不扫描 `space/` 磁盘；close 后条目随目录一并移除，`evolution` 负责校准登记与磁盘的偏差），以表格展示：work_id / 项目 / 描述（含触发词，格式 `用户登录功能 [触发词: 登录, user login]`） / 状态 / 分支（附工作区目录名，取 work_path 末段），当前工作区标记「（当前）」；按工作区目录名排序即按创建时间排序
2. 可接受用户序号或分支名输入，直接进入切换

## 框架自动提交（无需用户操作）

- 动作: 新建工作区（含 branch-op）补齐 context 与状态后，一次执行 `sh $root/harness/script/space.sh commit $root "chore(tack): workspace <branch>" "$root/tack.yaml" "$work/status.yaml" "$work/context.md"`；重命名由原事务脚本提交；查询无需提交
- 边界: 遵守 `harness/rule/git-boundary.md`；重命名同时作用于工作区目录与各代码仓库的分支，目录与 worktree 迁移由 work.sh 事务完成

## 后置完成检验

- [ ] `space/<YYYYMMDD>-<branch>/status.yaml`（含正确的 project、work_dir、branch）与 `context.md` 已生成
- [ ] 新建工作区为懒加载模式：仅创建工作区目录、`status.yaml` 与 `context.md`，`story/`、`doc/`、`run/`、`repo/` 等目录未预建、未创建任何 worktree；首次产生文件或检出时由对应命令创建（代码修改由 `code` 转 `worktree`）
- [ ] `tack.yaml` 的 work 列表与磁盘一致，且每条 work 条目的 `project` 与 status.yaml 一致
- [ ] 常规建区：`<workflow>` 已按目的确定并在说明中给出；已按 `command-context.sh roster` 输出开场知识清单——wiki 文件、已有 story 与 `doc/analysis/` 文档（含新鲜度），冷仓库已建议 ask；未向上下文塞入 wiki 全文
- [ ] branch-op：op/A/B 与源分支引用（本地/远端）已解析且仓库经用户确认；prepare 成功，status.yaml 已置 `workflow: branch-op`、`status: preparing` 并写入 `branch_op` 区块（临时分支名齐全），两个临时分支已登记到 branches 列表（role=tmp, source=branch-op）
- [ ] 重命名：dry-run 计划经用户确认；apply 输出 `RENAME_RESULT=applied` 且 `RECONCILE=ok`（失败时 `ROLLBACK=complete|incomplete` 已如实汇报）

## 下一步建议

- 常规建区：向 `$work/context.md` 录入需求，先执行 `ask`（需求明确前的代码问答）或 `analyze`（按 story 生成 analysis.md），再逐 story 执行 `spec`；所有命令执行前先读 context.md
- branch-op：执行 `branch-op.sh integrate` 进入集成环节，冲突由 `solve` 负责解决与 continue；返回后核验 operation 和完成结果，再 `push`（rebase 须先取得用户当次授权），收尾在 `close`
