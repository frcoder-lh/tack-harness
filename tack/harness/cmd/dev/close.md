---
command: close
short: cl
triggers: 关闭工作区, 结束, close, close workspace, finish
params: 无
summary: 工作区收尾——状态判定与关闭确认、交付检查、输出交付摘要、提炼内容入 wiki（含技术决策）、消费 guidance 自进化固化 harness 并校验落点、移除 worktree、删除工作区目录并移除 AGENTS.md work 条目
---

# close 关闭工作区

## 前置准入条件

- 已确定当前工作区 `$work` 与所属项目（`$work/status.yaml` 的 `project`）；项目为空或与 AGENTS.md `projects` 不一致时先向用户确认，再读取最新 status.yaml，不相信上下文里的旧内容

## 指令内容

1. **状态判定与关闭确认**
   - 动作: 读取 `$work/status.yaml` 的 `status`、`progress`、`tasks`，并执行 `sh $root/harness/script/work-status.sh $work/status.yaml deploy list` 检查是否存在 `deploying` / `deployed` 未回收泳道（status.yaml 已不存在时按下方中断续跑处理）
   - **完成态**（`status` 为 merged/completed，或 `progress.merged: true`，MR 已合并或用户已确认交付）：视为已到完成态，**不再追问，直接进入后续收尾流程**
   - **非完成态**（initialized/planning/developing/reviewing，或存在未完成 tasks、未推送提交、未合并 MR）：列出未完成项并说明风险，**请用户确认是否仍要关闭**
     - 输入: 用户确认 → 继续；用户不确认 → 中止关闭，引导回到对应环节（如 `merge`、`code`）
   - work 条目仍在即表示关闭未完成；若 worktree 已移除（上次收尾在删除目录前中断），直接续跑剩余收尾步骤；若工作区目录已删除而 work 条目残留（purge 与移除条目之间中断），直接执行第 7 步的 `work-remove` 后跳到收尾提交

2. **交付检查**
   - 动作: 逐仓库检查：无未提交改动（或用户确认保留）、本地提交均已推送、MR 已合并或用户确认跳过；检查 `$work/status.yaml` 的 mr_url、tech_doc_url 是否需要补全；未推送提交需逐一告知用户并确认处理方式；执行 `work-status.sh $work/status.yaml deploy list`——存在 `deploying/deployed` 状态的泳道时提醒用户到部署平台回收（回收后执行 `deploy mark <repo> <env> <lane> recycled`），未回收不阻塞关闭但处理方式须经用户确认；检查 `$work/run/local/`——该目录被 .gitignore 忽略，仅本地存在、含密钥/账号或临时数据；工作区目录将在第 7 步整体删除，提醒用户其中若有需要保留的文件请先取走（不阻塞关闭）

3. **输出交付摘要**
   - 时机: worktree 移除前（仍可取到提交与文件清单），wiki 提炼前
   - **branch-op 工作流分流**（无 spec/plan）：输出简版摘要，事实只取 status.yaml 的 `branch_op` 区块与各仓库 git 记录：
     1. **操作内容**：op（merge/rebase）、源分支 A、目标分支 B、涉及仓库
     2. **执行结果**：逐仓库 pushed 状态、结果实际落入的原分支（merge→B，rebase→A）
     3. **建议后续**：提示关注目标分支状态；若有 abort/blocked 仓库在此列明
   - **其他工作流**：
     - 输入源: spec.md（交付故事）、plan.md（方案选定与决策记录）、status.yaml（done tasks、`follow_ups`、mr_url）、各仓库 `git log <目标分支>..HEAD --stat`
     - 动作: 向用户输出固定四段结构：
       1. **构建内容**：本次交付的功能点（对照 spec 故事与 done tasks）
       2. **关键决策**：plan 中选定的实现方案与重要决策记录
       3. **改动文件**：按仓库分组的提交与主要改动文件清单（来自 git 事实，附 MR 链接）
       4. **建议后续步骤**：merge 时登记的 follow_ups、遗留/跳过项、测试与上线建议
   - 边界: 只汇总工作区产物与 git 事实，不杜撰未做的内容；摘要当场呈现，不新建文件（用户要求留存时可写入 status.yaml 备注）

4. **提炼工作区内容，确认是否记入 wiki**
   - **branch-op 工作流分流**：工作区无 spec/plan/tech-design 与 wiki 产物，input.md 为空；`branch_op` 区块只是本次过程记录，不属于跨工作区知识。动作: 检查其中是否夹带代码外事实（一般没有），无候选时一句话说明并跳过本步，不展示空清单
   - 输入源: 工作区**原始产物**——input.md、spec.md、plan.md（含决策记录）、tech-design.md、`$work/wiki/`、status.yaml（mr_url、tech_doc_url、meego 等）；**已有项目 wiki 页面只用于确定融合位置，不作为事实来源**（防合成内容循环放大，见 `harness/rule/record-wiki.md` 边界）
   - 动作: 从中提炼**跨工作区复用、且代码不应作为真源**的候选知识，按 `harness/rule/record-wiki.md`「文件分工」归入 `$root/wiki/<project>/` 对应文件（代码外事实、项目级参数、稳定导航锚点、业务背景知识、技术决策与工程约定的具体落点见该规则）
   - 边界: 易变的代码实现、调用链、模块内部行为**不进 wiki**（以代码为唯一真源）；工作区级参数（MR 地址、泳道、构建版本等）留在 `$work/status.yaml`，不写入项目 wiki；通用编码规范不进 decisions（走第 5 步 rule）；来源不明、无法从工作区产物证实的内容不提炼
   - 询问: 以候选条目清单（含建议落点与**来源标注**）询问用户**是否记入项目 wiki**；用户可全部采纳、挑选部分或放弃
   - 落盘: 被采纳条目按 `harness/rule/record-wiki.md` 写入 `$root/wiki/<project>/` 对应文件——文件已存在则融合去重（不重复追加），不存在时按 `harness/template/wiki-*.md` 模板创建（decisions.md 首条采纳时才创建）；每条带来源（`space/<workspace>/<文件>`，`<workspace>` 即当前工作区目录名），与旧条目矛盾时按「矛盾与演变」规则保留轨迹；**必须经人工审阅确认后才生效**；用户放弃则跳过

5. **自进化：消费 guidance，固化操作习惯到 harness**
   - 输入: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml guidance list pending` 取得本工作区全部 pending 条目（无 pending 条目则向用户一句话说明并跳过本步）
   - 动作: 逐条按 `harness/rule/record-classification.md` 判据评估——筛出**跨工作区可复用的操作习惯/流程修正**（应固化为 workflow/cmd/rule 的内容），一次性过程信息标记为不固化；汇总为候选清单：来源条目 id | 场景与用户引导 | 建议落点（workflow/cmd/rule 及具体文件）| 融合或新建
   - 询问: 向用户展示候选清单，可全部采纳、挑选部分或放弃（**落盘必须经用户确认**，本步不擅自改 harness）
   - 落盘: 采纳项走 `record` 流程——先扫描对应 workflow/cmd/rule，**能融合则融合**，确无合适条目才新建；同时遵守核心约束第 10 条，发现确定性固定步骤一并提议固化为 script
   - 回写: 落盘完成的条目执行 `sh $root/harness/script/work-status.sh $work/status.yaml guidance <id> applied <相对 $root 的落点路径...>`（多落点空格分隔，脚本校验落点文件存在后只置 `status: applied`），路径不存在时按报错修复后重试；放弃或评估为不固化的执行 `sh $root/harness/script/work-status.sh $work/status.yaml guidance <id> rejected`；用户暂缓决断的保留 `pending`（不阻塞关闭，可日后手动 `evolution`/`record` 处理）
   - 边界: guidance 只作为候选素材，事实存疑、无法从工作区过程证实的不固化；wiki 类知识已在第 4 步处理，本步只面向 workflow/cmd/rule

6. **移除 worktree 并清理分支**
   - **branch-op 工作流**：从 status.yaml 的 `branch_op.repos` 逐仓库读取临时分支名，执行
     `sh $root/harness/script/branch-op.sh cleanup $root space/<workspace> <repo> <source_tmp> <target_tmp>`（`<workspace>` 取 `basename "$work"`）
     一次性移除工作 worktree 并删除 `A-ts`、`B-ts` 两个临时分支；worktree 存在未提交改动时脚本停止，报告事实并经用户确认后追加 `force` 参数
   - **其他工作流**：先执行 `sh $root/harness/script/git-worktree-helper.sh remove $root <workspace>`（`<workspace>` 取 `basename "$work"`），移除各仓库在 `$work/repo/` 下的 worktree；再执行
     `sh $root/harness/script/branch-clean.sh $root <workspace> --apply`
     清理 `status.yaml` 中登记的分支——脚本自动 fetch 后按主干判断，已合并的 main 分支与 tmp 分支删除；未合并主分支、保护分支、被 worktree 占用的分支与主干无法确定的条目只列出并以退出码 3 阻断，原样告知用户由其手动处理，不阻塞关闭
   - 幂等: `branch-clean.sh` 对已不存在的分支自动跳过，收尾中断后重跑本步安全——工作区目录将在第 7 步删除，清理状态不回写 status.yaml
   - 边界: 只清理 `status.yaml` branches 列表登记的分支；用户在工作区期间手动 `checkout -b` 创建的分支未登记，框架不自动删除（可提示用户检查工作区是否有未登记分支）；远端分支不由脚本删除，输出中的远端提示需用户人工确认后处理

7. **删除工作区并移除登记**
   - 前置: 第 4 步 wiki 提炼、第 5 步 guidance 固化均已落盘（跨工作区知识已进入 `$root/wiki/<project>/`，能力固化进入 `harness/`），交付摘要已在第 3 步当场呈现；工作区目录内的 spec/plan/status/run 等过程产物不再保留
   - 动作: 取 `<workspace>` = `basename "$work"`、`<work_id>` = status.yaml 的 `work_id`，先执行
     `sh $root/harness/script/work.sh purge $root <workspace>`
     删除整个 `$work` 目录（脚本内置三道安全门禁：workspace 为单层目录名、物理路径位于 `$root/space/` 内、`repo/` 下无残留 worktree；含 `run/local/` 在内的全部工作区文件一并删除）；再执行
     `sh $root/harness/script/project.sh work-remove $root <work_id> --no-commit`
     移除 AGENTS.md 项目信息区块中的 work 条目（目录删除由收尾的框架自动提交统一记录）
   - 边界: purge 报告残留 worktree 时回到第 6 步清理，不得绕过脚本手工删目录；`work-remove` 报条目不存在（中断续跑场景）视为成功继续

8. **清理上下文**
   - 动作: 清空 `$work` 上下文变量，输出当前剩余工作区列表（直接读 AGENTS.md 项目信息区块的 work 条目，不扫描磁盘）

9. **版本检查（更新提醒挂载点）**
   - 动作: 按 `harness/rule/update-check.md` 执行 `sh $root/harness/script/check-update.sh $root`；有新版本时在下一步建议中原样转述，并告知「说『更新』即可升级」

## 框架自动提交（无需用户操作）

- 动作: 上述收尾完成后，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): close workspace <branch>"`，把 wiki 沉淀、第 5 步自进化对 harness（workflow/cmd/rule/script）的固化改动、AGENTS.md work 条目移除与 `space/<workspace>/` 目录删除自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；移除 worktree、清理分支与删除工作区目录均由框架脚本（`git-worktree-helper.sh` / `branch-op.sh` / `branch-clean.sh` / `work.sh purge`）完成（属框架管理，不需用户操作）；代码仓库的提交/推送状态在第 2 步交付检查中确认，本步骤不代为操作

## 后置完成检验

- [ ] 非完成态关闭已有用户明确确认；完成态未做多余追问
- [ ] 已按四段结构（构建内容/关键决策/改动文件/建议后续步骤）输出交付摘要，内容均有工作区产物或 git 事实来源
- [ ] `git worktree list` 中不再有该工作区的 worktree
- [ ] branch-op：`A-ts`、`B-ts` 两个临时分支均已删除
- [ ] 其他工作流：`branch-clean.sh` 已执行，SUMMARY 无 failed；blocked 项（未合并主分支/保护分支/占用分支/主干不明）已原样告知用户并保留
- [ ] `$root/space/<workspace>/` 目录已删除（`work.sh purge` 成功），AGENTS.md 项目信息区块中已无该 work 条目
- [ ] 记入 `wiki/<project>/` 的内容符合 `harness/rule/record-wiki.md` 的边界、文件分工与来源链，且经人工审阅；工作区级参数未误写项目 wiki，用户放弃时未强行写入
- [ ] guidance 的 pending 条目已逐条处理：固化项经用户确认落盘并置 applied，不固化项置 rejected；未确认落盘的条目保留 pending 且不阻塞关闭
- [ ] `deploy` 区块无未回收泳道（deploying/deployed），或用户已确认处理方式
- [ ] `run/local/` 中需保留的本地文件删除前已提醒用户取走；该目录随工作区一并删除
- [ ] 版本检查已执行；有新版本时已原样转述提醒与更新内容，并建议执行 `update`

## 下一步建议

- 需要新需求时执行 `work` 创建新工作区
