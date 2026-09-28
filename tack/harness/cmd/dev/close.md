---
command: close
short: cl
triggers: 关闭工作区, 结束, close
params: 无
summary: 工作区收尾——状态判定与关闭确认、交付检查、输出交付摘要、提炼内容入 wiki（含技术决策）、消费 guidance 自进化固化 harness 并校验落点、移除 worktree、更新状态
---

# close 关闭工作区

## 前置准入条件

- 已确定当前工作区 `$work`；重新读取 `$work/status.yaml`，不相信上下文里的旧内容

## 指令内容

1. **状态判定与关闭确认**
   - 动作: 读取 `$work/status.yaml` 的 `status`、`progress`、`tasks`
   - **完成态**（`status` 为 merged/completed，或 `progress.merged: true`，MR 已合并或用户已确认交付）：视为已到完成态，**不再追问，直接进入后续收尾流程**
   - **非完成态**（initialized/planning/developing/reviewing，或存在未完成 tasks、未推送提交、未合并 MR）：列出未完成项并说明风险，**请用户确认是否仍要关闭**
     - 输入: 用户确认 → 继续；用户不确认 → 中止关闭，引导回到对应环节（如 `merge`、`code`）
   - 已是 completed 但 worktree 仍存在（上次收尾中断）：直接续跑剩余收尾步骤

2. **交付检查**
   - 动作: 逐仓库检查：无未提交改动（或用户确认保留）、本地提交均已推送、MR 已合并或用户确认跳过；检查 `$work/status.yaml` 的 mr_url、tech_doc_url 是否需要补全；未推送提交需逐一告知用户并确认处理方式

3. **输出交付摘要**
   - 时机: worktree 移除前（仍可取到提交与文件清单），wiki 提炼前
   - 输入源: spec.md（交付故事）、plan.md（方案选定与决策记录）、status.yaml（done tasks、`follow_ups`、mr_url）、各仓库 `git log <目标分支>..HEAD --stat`
   - 动作: 向用户输出固定四段结构：
     1. **构建内容**：本次交付的功能点（对照 spec 故事与 done tasks）
     2. **关键决策**：plan 中选定的实现方案与重要决策记录
     3. **改动文件**：按仓库分组的提交与主要改动文件清单（来自 git 事实，附 MR 链接）
     4. **建议后续步骤**：merge 时登记的 follow_ups、遗留/跳过项、测试与上线建议
   - 边界: 只汇总工作区产物与 git 事实，不杜撰未做的内容；摘要当场呈现，不新建文件（用户要求留存时可写入 status.yaml 备注）

4. **提炼工作区内容，确认是否记入 wiki**
   - 输入源: 工作区**原始产物**——input.md、spec.md、plan.md（含决策记录）、tech-design.md、`$work/wiki/`、status.yaml（mr_url、tech_doc_url、meego 等）；**已有根 wiki 页面只用于确定融合位置，不作为事实来源**（防合成内容循环放大，见 `harness/rule/record-wiki.md` 边界）
   - 动作: 从中提炼**跨工作区复用、且代码不应作为真源**的候选知识，按分工归类：
     - **代码外事实**（环境配置、中间件/平台地址、部署地址、负责人、不含凭据的账号）→ `$root/wiki/manifest.md`
     - **稳定导航锚点**（业务术语 ↔ 检索关键词/代码入口、接口标识 ↔ 业务场景 ↔ 代码入口）→ `$root/wiki/code-understanding.md`
     - **业务背景知识**（业务线背景、术语的业务释义、原始业务资料）→ `$root/wiki/business-understanding.md`
     - **技术决策与工程约定**（plan.md「决策记录」中的选型取舍、代码外的项目规则如重试/舍入/默认值约定）→ `$root/wiki/decisions.md`
   - 边界: 易变的代码实现、调用链、模块内部行为**不进 wiki**（以代码为唯一真源）；通用编码规范不进 decisions（走第 5 步 rule）；来源不明、无法从工作区产物证实的内容不提炼
   - 询问: 以候选条目清单（含建议落点与**来源标注**）询问用户**是否记入 wiki**；用户可全部采纳、挑选部分或放弃
   - 落盘: 被采纳条目按 `harness/rule/record-wiki.md` 写入 `$root/wiki/` 对应文件——文件已存在则融合去重（不重复追加），不存在时按 `harness/template/wiki-*.md` 模板创建（decisions.md 首条采纳时才创建）；每条带来源（`space/<branch>/<文件>`），与旧条目矛盾时按「矛盾与演变」规则保留轨迹；**必须经人工审阅确认后才生效**；用户放弃则跳过

5. **自进化：消费 guidance，固化操作习惯到 harness**
   - 输入: 读取 `$work/status.yaml` 的 `guidance` 列表中所有 `status: raw` 条目（无 raw 条目则向用户一句话说明并跳过本步）
   - 动作: 逐条按 `harness/rule/record-classification.md` 判据评估——筛出**跨工作区可复用的操作习惯/流程修正**（应固化为 workflow/cmd/rule 的内容），一次性过程信息标记为不固化；汇总为候选清单：来源条目 id | 场景与用户引导 | 建议落点（workflow/cmd/rule 及具体文件）| 融合或新建
   - 询问: 向用户展示候选清单，可全部采纳、挑选部分或放弃（**落盘必须经用户确认**，本步不擅自改 harness）
   - 落盘: 采纳项走 `record` 流程——先扫描对应 workflow/cmd/rule，**能融合则融合**，确无合适条目才新建；同时遵守核心约束第 8 条，发现确定性固定步骤一并提议固化为 script
   - 回写: 落盘完成的条目的 `status` 置 `distilled`，并在条目内另起一行按固定格式注明落点：`落点: <相对 $root 的路径>`（如 `落点: harness/cmd/dev/code.md`，多落点空格分隔；格式见 `harness/template/work-status.yaml`）；放弃或评估为不固化的置 `dismissed`；用户暂缓决断的保留 `raw`（不阻塞关闭，可日后手动 `evolution`/`record` 处理）
   - 校验: 回写后执行 `sh $root/harness/script/check-guidance.sh $root <work_id>`，确认本工作区 distilled 条目引用的落点文件均存在；报失效时先修复（补回文件或更正落点路径）再继续，不删除来源条目
   - 边界: guidance 只作为候选素材，事实存疑、无法从工作区过程证实的不固化；wiki 类知识已在第 4 步处理，本步只面向 workflow/cmd/rule

6. **移除 worktree**
   - 动作: 执行 `sh $root/harness/script/git-worktree-helper.sh remove $root <branch>`，移除各仓库在 `$work/repo/` 下的 worktree

7. **归档工作区**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set status completed progress.merged true`（自动刷新 updated_at），并执行
     `sh $root/harness/script/project.sh work-set $root <work_id> completed`
     更新 AGENTS.md 项目信息区块中的 work 条目；询问用户保留 `$work` 文档（spec.md、plan.md、tech-design.md、status.yaml）还是一并归档清理

8. **清理上下文**
   - 动作: 清空 `$work` 上下文变量，输出当前剩余工作区列表（读 AGENTS.md 项目信息区块）

## 框架自动提交（无需用户操作）

- 动作: 上述收尾完成后，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): close workspace <branch>"`，把 wiki 沉淀、第 5 步自进化对 harness（workflow/cmd/rule/script）的固化改动、status.yaml（含 guidance 回写）、AGENTS.md work 条目及文档保留/清理的结果自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`；移除 worktree 由框架脚本 `git-worktree-helper.sh` 完成（属框架管理，不需用户操作）；代码仓库的提交/推送状态在第 2 步交付检查中确认，本步骤不代为操作

## 后置完成检验

- [ ] 非完成态关闭已有用户明确确认；完成态未做多余追问
- [ ] 已按四段结构（构建内容/关键决策/改动文件/建议后续步骤）输出交付摘要，内容均有工作区产物或 git 事实来源
- [ ] `git worktree list` 中不再有该工作区的 worktree
- [ ] 工作区 status.yaml 与 AGENTS.md work 条目状态均为 completed
- [ ] 记入 wiki 的内容符合边界（无易变代码逻辑、均有来源、无凭据明文）、四类分工归类正确且经人工审阅；用户放弃时未强行写入
- [ ] guidance 的 raw 条目已逐条处理：固化项经用户确认落盘并置 distilled（按 `落点: <相对 $root 路径>` 注明），不固化项置 dismissed；未确认落盘的条目保留 raw 且不阻塞关闭
- [ ] `check-guidance.sh` 校验通过：本工作区 distilled 条目无失效落点
- [ ] 文档保留/清理符合用户选择

## 下一步建议

- 需要新需求时执行 `work` 创建新工作区
