---
command: close
short: cl
triggers: 关闭工作区, 结束, close, close workspace, finish
params: 无
summary: 工作区收尾——状态判定与关闭确认、同步关闭关联工作区、交付检查、输出交付摘要、自动判定工作区归档（写入 wiki/<project>/history/<workspace>/summary.md、登记 history/index.md 并移入 run/）、提炼内容入 wiki（按分类与索引写入，含技术决策与 ask 记录归档）、消费 guidance 自进化固化 harness 并校验落点、移除 worktree、删除工作区目录并移除 tack.yaml work 条目
---

# close 关闭工作区

## 前置准入条件

- 已确定当前工作区 `$work` 与所属项目（`$work/status.yaml` 的 `project`）；项目为空或与 `tack.yaml` 的 `projects` 不一致时先向用户确认，再读取最新 status.yaml（上下文已有且未变化时复用）

## 指令内容

1. **状态判定与关闭确认**
   - 动作: 读取 `$work/status.yaml` 的 `status`、`progress`、`tasks`，并执行 `sh $root/harness/script/work-status.sh $work/status.yaml deploy list` 检查是否存在 `deploying` / `deployed` 未回收泳道（回收判定与处理见 `harness/rule/deploy.md`；status.yaml 已不存在时按下方中断续跑处理）
   - **完成态**（`status` 为 merged/completed，或 `progress.merged: true`，MR 已合并或用户已确认交付）：视为已到完成态，**不再追问，直接进入后续收尾流程**
   - **非完成态**（initialized/planning/developing/reviewing，或存在未完成 tasks、未推送提交、未合并 MR）：列出未完成项并说明风险，**请用户确认是否仍要关闭**
     - 输入: 用户确认 → 继续；用户不确认 → 中止关闭，引导回到对应环节（如 `merge`、`code`）
   - work 条目仍在即表示关闭未完成；若 worktree 已移除（上次收尾在删除目录前中断），直接续跑剩余收尾步骤；若工作区目录已删除而 work 条目残留（purge 与移除条目之间中断），直接执行第 9 步的 `work-remove` 后跳到收尾提交

2. **同步关闭关联工作区**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $root related children <workspace>`（`<workspace>` = `basename "$work"`），取得 `parent_workspace` 指向当前工作区的关联工作区（每行 `目录名<TAB>status<TAB>workflow`）
     - 无输出: 一句话说明无关联工作区，继续第 3 步
     - 有输出: 逐个（先子后父、递归）执行本命令第 1~9 步关闭关联工作区：
       1. 记录当前 `$work` 与状态，切换 `$work=$root/space/<关联目录>`，重新读取其 status.yaml
       2. 关联工作区为非完成态时按第 1 步规则请用户确认；用户拒绝则中止当前工作区关闭并保留现状
       3. 按其 workflow 分流行事（branch-op 用第 4 步简版摘要、第 8 步 `branch-op.sh cleanup`），走完交付检查、worktree 移除、目录 purge 与 `work-remove`
       4. 恢复 `$work` 为当前工作区，继续处理下一个关联工作区
   - 边界: 关联关系以子工作区 status.yaml 的 `parent_workspace` 为唯一依据，不按目录名或分支名推断；先关闭关联工作区再关闭当前工作区，任一关联工作区收尾失败即中止当前关闭并如实报告；子工作区收尾不单独提交，由当前工作区收尾的框架自动提交统一记录

3. **交付检查**
   - 动作: 逐仓库检查：无未提交改动（或用户确认保留）、本地提交均已推送、MR 已合并或用户确认跳过；检查 `$work/status.yaml` 的 mr_url、tech_doc_url 是否需要补全；未推送提交需逐一告知用户并确认处理方式；执行 `work-status.sh $work/status.yaml deploy list`，存在 `deploying`/`deployed` 泳道时按 `harness/rule/deploy.md` 提醒用户回收，未回收不阻塞关闭但处理方式须经用户确认；检查 `$work/run/*/local/`——该目录被 .gitignore 忽略，仅本地存在、含密钥/账号或临时数据，第 5 步随 `run/` 整体移入归档目录后仍不入库，提醒用户自行管理（不阻塞关闭）

4. **输出交付摘要**
   - 时机: worktree 移除前（仍可取到提交与文件清单），工作区归档与 wiki 提炼前
   - **branch-op 工作流分流**（无 story/spec/plan）：输出简版摘要，事实只取 status.yaml 的 `branch_op` 区块与各仓库 git 记录：
     1. **操作内容**：op（merge/rebase）、源分支 A、目标分支 B、涉及仓库
     2. **执行结果**：逐仓库 pushed 状态、结果实际落入的原分支（merge→B，rebase→A）
     3. **建议后续**：提示关注目标分支状态；若有 abort/blocked 仓库在此列明
   - **其他工作流**：
     - 输入源: `story/*/spec.md`（交付故事）、`story/*/plan.md`（方案选定与决策记录）、`story/*/analysis.md`（现有实现与兼容事实）、status.yaml（done tasks、`follow_ups`、mr_url）、各仓库 `git log <目标分支>..HEAD --stat`
     - 动作: 向用户输出固定四段结构：
       1. **构建内容**：本次交付的功能点（对照 spec 功能场景与 done tasks）
       2. **关键决策**：plan 中选定的实现方案与重要决策记录
       3. **改动文件**：按仓库分组的提交与主要改动文件清单（来自 git 事实，附 MR 链接）
       4. **建议后续步骤**：merge 时登记的 follow_ups、遗留/跳过项、测试与上线建议
   - 边界: 只汇总工作区产物与 git 事实，不杜撰未做的内容；摘要当场呈现，不新建文件（用户要求留存时可写入 status.yaml 备注）

5. **工作区归档（自动判定 summary.md 与 run/ 的保存价值）**
   - 判定: 按 `harness/rule/archive-requirement.md`「归档判定」自动判断——
     - 不归档 summary: `workflow: branch-op` 等纯分支搬运；无真实 context、无 story/spec/plan 且仅机械性/格式性改动的简单工作区
     - 应归档 summary: development / bugfix 等有需求背景与功能交付，且存在需要日后回忆的「为什么」（功能取舍、边界约定、关键讨论、设计决策）或对系统行为/接口/数据/配置/权限/依赖有影响
   - 归档目录: 固定为 `$root/wiki/<project>/history/<workspace>/`（`<workspace>` = `basename "$work"`，与工作区同名）；写 summary.md 前执行 `mkdir -p "$root/wiki/<project>/history/<workspace>"`（移动文件时由 `workspace-archive.sh` 自动创建）
   - summary.md: 应归档时按 `harness/template/wiki-history.md` 生成 `summary.md`（固定文件名）；内容为原始资料、实现的功能、关键讨论与决策、对系统的影响、排查索引，全部用业务语言分条陈述，不保留实现过程（编码步骤、文件/行号、调用链）、可行性分析与找 bug 过程；同目录已存在时就地融合更新，不覆盖
   - **登记历史索引**: 归档目录创建后，按 `harness/rule/wiki-write.md` 在 `$root/wiki/<project>/history/index.md` 登记本工作区目录（登记目录即覆盖 `summary.md` 与 `run/`）；索引文件不存在时按 `harness/template/wiki-category-index.md` 创建，项目总索引不存在时按 `harness/template/wiki-index.md` 创建并登记 `history/index.md`
   - run/ 归档: `$work/run/` 存在时执行 `sh $root/harness/script/workspace-archive.sh move $root <project> <workspace> run`，把整个 run 目录（指令索引、各指令脚本与数据、local/）原样移入归档目录；`run/*/local/` 仍被 .gitignore 忽略、不入库，提醒用户密钥只留在本地
   - 其他文件: 执行 `sh $root/harness/script/workspace-archive.sh list $root <workspace>` 取得标准产物之外的文件/目录清单（标准产物：status.yaml、context.md、story/、doc/、repo/、run/），逐项询问用户是否移入归档目录；用户选择移入的执行 `sh $root/harness/script/workspace-archive.sh move $root <project> <workspace> <相对路径>...`，其余随工作区删除
   - 输入: `$work/context.md`（含原始资料链接）、`story/*/analysis.md`（现有实现与兼容性）、`story/*/spec.md`（背景/目标/功能/边界）、`story/*/plan.md`（决策记录）、status.yaml（meego / mr_url / tech_doc_url）、各仓库 git 事实（交付功能与影响面）；`$work/doc/analysis/` 的 ask 产物按第 6 步处理
   - 边界: 不归档且无 run/、无用户选择移入的文件时，一句话说明判定结果并跳过本步；`repo/` 下代码不得移入归档；展示归档路径与 summary.md 摘要，经用户确认后生效，用户放弃则不写 summary.md

6. **提炼工作区内容，确认是否记入 wiki**
   - **branch-op 工作流分流**：工作区无 story/spec/plan/tech-design 与 doc 产物，context.md 为空；`branch_op` 区块只是本次过程记录，不属于跨工作区知识。动作: 检查其中是否夹带代码外事实（一般没有），无候选时一句话说明并跳过本步，不展示空清单
   - 输入源: 工作区**原始产物**——context.md、`story/*/analysis.md`、`story/*/spec.md`、`story/*/plan.md`（含决策记录）、`doc/tech-design.md`、`doc/analysis/`、status.yaml（mr_url、tech_doc_url、meego 等）；**已有项目 wiki 页面只用于确定融合位置，不作为事实来源**（防合成内容循环放大，见 `harness/rule/wiki-write.md` 边界）
   - 动作: 从中提炼**跨工作区复用、且代码不应作为真源**的候选知识，按 `harness/rule/wiki-write.md`「分类与落点」归入 `$root/wiki/<project>/` 对应分类（业务背景、代码锚点、项目规则、项目配置的具体落点见该规则）
   - **ask 记录归档**: 扫描 `$work/doc/analysis/` 目录下全部按主题命名的分析/问答文档（按目录与头部主题匹配，不假定 `-analysis` 后缀或固定文件名），按 `harness/rule/archive-ask.md` 转化后分流——业务名词解释进 `biz/glossary.md`、代码名词/导航进 `code/anchors.md` 与 `code/interfaces.md`、稳定代码外事实进 `config/`、项目级决策约定进 `rule/`、需求特定的「为什么/是否设计如此」融合进第 5 步的 `history/<workspace>/summary.md`；不原样复制，不保留可行性分析与找 bug 逻辑；无符合项时跳过
   - 边界: 易变的代码实现、调用链、模块内部行为**不进 wiki**（以代码为唯一真源）；工作区级参数（MR 地址、泳道、构建版本等）留在 `$work/status.yaml`，不写入项目 wiki；通用编码规范不进 `rule/decisions.md`（走第 7 步 rule）；来源不明、无法从工作区产物证实的内容不提炼
   - 询问: 以候选条目清单（含建议落点与**来源标注**）询问用户**是否记入项目 wiki**；用户可全部采纳、挑选部分或放弃
   - 落盘: 被采纳条目按 `harness/rule/wiki-write.md` 写入 `$root/wiki/<project>/` 对应分类文件——文件已存在则融合去重（不重复追加），不存在时按对应模板创建（`rule/decisions.md` 首条采纳时才创建）；每个新增文件同步登记分类索引与项目总索引；每条带来源（`space/<workspace>/<文件>`，`<workspace>` 即当前工作区目录名），与旧条目矛盾时按「矛盾与演变」规则保留轨迹；**必须经人工审阅确认后才生效**；用户放弃则跳过；落盘后执行 `sh $root/harness/script/wiki-index.sh check $root <project>` 确认退出码 0

7. **自进化：消费 guidance，固化操作习惯到 harness**
   - 输入: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml guidance list pending` 取得本工作区全部 pending 条目（无 pending 条目则向用户一句话说明并跳过本步）
   - 动作: 逐条按 `harness/rule/record-classification.md` 判据评估——筛出**跨工作区可复用的操作习惯/流程修正**（应固化为 workflow/cmd/rule 的内容），一次性过程信息标记为不固化；汇总为候选清单：来源条目 id | 场景与用户引导 | 建议落点（workflow/cmd/rule 及具体文件）| 融合或新建
   - 询问: 向用户展示候选清单，可全部采纳、挑选部分或放弃（**落盘必须经用户确认**，本步不擅自改 harness）
   - 落盘: 采纳项走 `record` 流程——先扫描对应 workflow/cmd/rule，**能融合则融合**，确无合适条目才新建；同时按「沉淀生命周期」的固化门槛检查，发现确定性固定步骤一并提议固化为 script
   - 回写: 落盘完成的条目执行 `sh $root/harness/script/work-status.sh $work/status.yaml guidance <id> applied <相对 $root 的落点路径...>`（多落点空格分隔，脚本校验落点文件存在后只置 `status: applied`），路径不存在时按报错修复后重试；放弃或评估为不固化的执行 `sh $root/harness/script/work-status.sh $work/status.yaml guidance <id> rejected`；用户暂缓决断的保留 `pending`（不阻塞关闭，可日后手动 `evolution`/`record` 处理）
   - 边界: guidance 只作为候选素材，事实存疑、无法从工作区过程证实的不固化；wiki 类知识已在第 6 步处理，本步只面向 workflow/cmd/rule

8. **移除 worktree 并清理分支**
   - **branch-op 工作流**：从 status.yaml 的 `branch_op.repos` 逐仓库读取临时分支名，执行
     `sh $root/harness/script/branch-op.sh cleanup $root space/<workspace> <repo> <source_tmp> <target_tmp>`（`<workspace>` 取 `basename "$work"`）
     一次性移除工作 worktree 并删除 `A-ts`、`B-ts` 两个临时分支；worktree 存在未提交改动时脚本停止，报告事实并经用户确认后追加 `force` 参数
   - **其他工作流**：先执行 `sh $root/harness/script/git-worktree-helper.sh remove $root <workspace>`（`<workspace>` 取 `basename "$work"`），移除各仓库在 `$work/repo/` 下的 worktree；再执行
     `sh $root/harness/script/branch-clean.sh $root <workspace> --apply`
     清理 `status.yaml` 中登记的分支——脚本自动 fetch 后按主干判断，已合并的 main 分支与 tmp 分支删除；未合并主分支、保护分支、被 worktree 占用的分支与主干无法确定的条目只列出并以退出码 3 阻断，原样告知用户由其手动处理，不阻塞关闭
   - 幂等: `branch-clean.sh` 对已不存在的分支自动跳过，收尾中断后重跑本步安全——工作区目录将在第 9 步删除，清理状态不回写 status.yaml
   - 边界: 只清理 `status.yaml` branches 列表登记的分支；用户在工作区期间手动 `checkout -b` 创建的分支未登记，框架不自动删除（可提示用户检查工作区是否有未登记分支）；远端分支不由脚本删除，输出中的远端提示需用户人工确认后处理

9. **删除工作区并移除登记**
   - 前置: 第 5 步工作区归档（summary.md 与 run/ 移入）、第 6 步 wiki 提炼（含 ask 记录归档）、第 7 步 guidance 固化均已落盘（跨工作区知识已进入 `$root/wiki/<project>/`，能力固化进入 `harness/`），交付摘要已在第 4 步当场呈现；工作区剩余文件（context.md、story/、doc/ 等）随目录一并删除
   - 动作: 取 `<workspace>` = `basename "$work"`、`<work_id>` = status.yaml 的 `work_id`，先执行
     `sh $root/harness/script/work.sh purge $root <workspace>`
     删除整个 `$work` 目录（脚本内置三道安全门禁：workspace 为单层目录名、物理路径位于 `$root/space/` 内、`repo/` 下无残留 worktree；`run/` 已在第 5 步移入归档，剩余文件一并删除）；再执行
     `sh $root/harness/script/project.sh work-remove $root <work_id> --no-commit`
     移除 `tack.yaml` 的 work 列表中的该条目（目录删除由收尾的框架自动提交统一记录）
   - 边界: purge 报告残留 worktree 时回到第 8 步清理，不得绕过脚本手工删目录；归档目录位于 `$root/wiki/<project>/history/` 下，不受 purge 影响；`work-remove` 报条目不存在（中断续跑场景）视为成功继续

10. **清理上下文**
   - 动作: 清空 `$work` 上下文变量，输出当前剩余工作区列表（执行 `sh $root/harness/script/project.sh work-list $root`，不扫描磁盘）

11. **版本检查（更新提醒挂载点）**
   - 动作: 按 `harness/rule/update-check.md` 执行 `sh $root/harness/script/check-update.sh $root`；有新版本时在下一步建议中原样转述，并告知「说『更新』即可升级」

## 框架自动提交（无需用户操作）

- 动作: 上述收尾完成后，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): close workspace <branch>" "$root/wiki" "$root/harness" "$root/AGENTS.md" "$root/tack.yaml" "$work"`，把工作区归档（summary.md、`history/<workspace>/run/` 与用户选择移入的文件）与 wiki 沉淀、第 7 步自进化对 harness（workflow/cmd/rule/script）的固化改动、tack.yaml work 条目移除与 `space/<workspace>/` 目录删除自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；移除 worktree、清理分支与删除工作区目录均由框架脚本（`git-worktree-helper.sh` / `branch-op.sh` / `branch-clean.sh` / `work.sh purge`）完成（属框架管理，不需用户操作）；代码仓库的提交/推送状态在第 3 步交付检查中确认，本步骤不代为操作

## 后置完成检验

- [ ] 非完成态关闭已有用户明确确认；完成态未做多余追问
- [ ] `parent_workspace` 指向本工作区的关联工作区已全部同步关闭；无关联时已说明
- [ ] 已按四段结构（构建内容/关键决策/改动文件/建议后续步骤）输出交付摘要，内容均有工作区产物或 git 事实来源
- [ ] 已按 `harness/rule/archive-requirement.md` 自动判定归档价值：应归档的已写入 `wiki/<project>/history/<workspace>/summary.md` 并经用户确认；不归档的已说明理由，未生成空 summary.md
- [ ] `$work/run/` 存在时已整体移入 `wiki/<project>/history/<workspace>/run/`（`workspace-archive.sh move` 成功），`run/*/local/` 未入库
- [ ] 标准产物之外的文件/目录已列清单询问用户，选择移入的已移入归档目录，其余随工作区删除
- [ ] ask 记录已按 `harness/rule/archive-ask.md` 转化归档（来源 `doc/analysis/`）：业务名词进 `biz/glossary.md`、代码名词/导航进 `code/anchors.md` 与 `code/interfaces.md`，未保留可行性分析与找 bug 逻辑
- [ ] 归档工作区已在 `history/index.md` 登记；新增/更新的 wiki 文件已登记到对应分类索引与项目总索引，`wiki-index.sh check` 退出码为 0
- [ ] `git worktree list` 中不再有该工作区的 worktree
- [ ] branch-op：`A-ts`、`B-ts` 两个临时分支均已删除
- [ ] 其他工作流：`branch-clean.sh` 已执行，SUMMARY 无 failed；blocked 项（未合并主分支/保护分支/占用分支/主干不明）已原样告知用户并保留
- [ ] `$root/space/<workspace>/` 目录已删除（`work.sh purge` 成功），`tack.yaml` 的 work 列表中已无该条目
- [ ] 记入 `wiki/<project>/` 的内容符合 `harness/rule/wiki-write.md` 的分类、边界、来源链与索引要求，且经人工审阅；工作区归档符合 `archive-requirement.md` 与 `archive-ask.md`；工作区级参数未误写项目 wiki，用户放弃时未强行写入
- [ ] guidance 的 pending 条目已逐条处理：固化项经用户确认落盘并置 applied，不固化项置 rejected；未确认落盘的条目保留 pending 且不阻塞关闭
- [ ] `deploy` 区块无未回收泳道（deploying/deployed），或用户已确认处理方式
- [ ] `run/*/local/` 中的敏感数据已提醒用户自行管理；该目录随 run/ 移入归档且不入库
- [ ] 版本检查已执行；有新版本时已原样转述提醒与更新内容，并建议执行 `update`

## 下一步建议

- 需要新需求时执行 `work` 创建新工作区
