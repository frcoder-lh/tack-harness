---
command: merge
short: m
triggers: 合并, merge
params: [目标分支（默认主干）]
summary: 分支合并——fetch 最新后把源分支合入目标分支；当前工作区为源分支时新建关联工作区执行，冲突转 solve，提交并推送
---

# merge 合并分支

## 前置准入条件

- 已确定当前工作区 `$work`
- 源分支改动已 `commit`；未提交改动不进入合并范围
- **Git 作用域**：遵守 `harness/rule/git-boundary.md`——只允许在 `$work/repo/<repo-name>/` 工作区代码仓库内执行 Git 操作

## 指令内容

1. **拉取最新并确认合并方向**
   - 动作: 逐仓库执行 `sh $root/harness/script/git-fetch-helper.sh fetch "$work/repo/<repo-name>"` 拉取最新远端引用，再执行 `sh $root/harness/script/git-facts.sh status "$work/repo/<repo-name>"` 确认当前分支、upstream、ahead/behind
   - 源分支: 默认当前工作区分支（用户指定时以其为准）
   - 目标分支: 用户参数；缺省时执行 `sh $root/harness/script/git-facts.sh default-branch "$work/repo/<repo-name>"`（退出码 11 时由用户指定）
   - **确认合并哪一侧的源分支**:
     - 本地分支：以本地 `<源分支>` 为合并内容（含未推送提交）
     - 远程分支：以 fetch 后的 `origin/<源分支>` 为合并内容（仅已推送提交）
     - 按 ahead/behind 事实区分：本地 ahead > 0 时两侧内容不同，必须让用户明确选择；只有一侧存在时直接使用该侧；拿不准时展示事实并询问
   - 边界: 合并方向、源引用、目标分支三者须在动手前明确，不按上下文猜测

2. **确定执行位置**
   - 当前分支 = 目标分支：先逐仓库执行 `sh $root/harness/script/git-fetch-helper.sh sync "$work/repo/<repo-name>"` 把目标分支对齐远端最新（冲突转 `solve`），再执行 `git merge <本地源分支|origin/源分支>`
   - 当前分支 = 源分支，或当前分支既非源也非目标、目标已被其他 worktree 检出：交由 `work` 命令新建工作区执行（第 3 步），不在源工作区 checkout 目标分支
   - 多仓库时逐仓库判定，可能部分仓库就地合并、部分转新工作区

3. **新建合并工作区（需要时）**
   - 动作: 按 `work` 命令「分支操作（branch-op）」流程执行，分支操作意图为「把 <源分支> 合并到 <目标分支>」，源分支引用取第 1 步的选择（本地/远端）
   - 关联: 工作区创建后执行
     `sh $root/harness/script/work-status.sh $root/space/<WORKSPACE>/status.yaml set parent_workspace "<当前工作区目录名>"`
     把新工作区关联到当前工作区（`<当前工作区目录名>` = `basename "$work"`）；随后把 `$work` 切到新工作区执行第 4 步，完成后切回原工作区
   - 边界: 建区、prepare、临时分支命名与登记均由 work/branch-op 流程完成，本命令不重复；不自行拼工作区目录名，一律使用脚本输出的 `WORKSPACE`

4. **执行合并并处理冲突**
   - 新工作区: 逐仓库执行 `sh $root/harness/script/branch-op.sh integrate $root space/<WORKSPACE> <repo> merge <source-tmp> <target-tmp>`
   - 当前工作区就地合并: 逐仓库执行 `git merge <本地源分支|origin/源分支>`
   - 冲突: 退出码 10 或 `sh $root/harness/script/git-facts.sh conflicts "$work/repo/<repo-name>"` 退出码 10 时，停止自动处理并转 `solve`；解决后新工作区执行 `sh $root/harness/script/branch-op.sh continue $root space/<WORKSPACE> <repo> merge`，就地合并执行 `git merge --continue`；仍有冲突则重复 solve
   - 边界: 不静默取舍冲突内容，不使用强制操作绕过

5. **提交与推送**
   - 提交: `branch-op.sh integrate` 以 `--no-edit` 生成合并提交；就地合并的冲突解决后由 `git merge --continue` 生成合并提交；提交信息不符合规范时按 `harness/rule/git-standards.md` 修正后再继续
   - 推送: 新工作区逐仓库执行
     `sh $root/harness/script/branch-op.sh push $root space/<WORKSPACE> <repo> merge <源分支> <目标分支> <source-tmp> <target-tmp>`
     就地合并逐仓库执行 `sh $root/harness/script/git-push-helper.sh push "$work/repo/<repo-name>"`
   - 目标为保护分支、平台拒绝直接推送时: 按平台流程发起 MR/PR 合并，成功后回填 `mr_url`；不绕过保护规则
   - 只允许普通推送，禁止 force

6. **合并后回写**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set status merged stage merge progress.merged true`（就地合并时写当前工作区；新建工作区合并时写原工作区，新工作区按 branch-op 流程保持 `completed`）
   - 关联工作区保留到 `close`，由 `close` 随当前工作区一并关闭；本命令不删除合并工作区
   - 合并 ≠ 上线: 用户需要在 PPE/PROD 等环境继续验证或上线时，执行 `sh $root/harness/script/work-status.sh $work/status.yaml deploy upsert <repo> <env> <lane> <route> <build> <url> <status>` 登记各环境上线计划与泳道/版本事实；BOE 验证泳道不再使用时执行 `deploy mark <repo> <env> <lane> recycled`

## 后置完成检验

- [ ] 已 fetch 最新；源分支、目标分支、本地/远程源引用均有明确选择依据
- [ ] 执行位置明确：就地合并或新建关联工作区，未强行 checkout 被占用的分支
- [ ] 每个仓库合并结果明确（成功 / 冲突已转 solve 并继续 / 用户选择跳过）
- [ ] 合并提交已生成、普通推送成功（或平台 MR/PR 已发起并回填 mr_url）
- [ ] 新工作区 `status.yaml` 的 `parent_workspace` 指向原工作区
- [ ] 原工作区 `status` 置 `merged`、`progress.merged` 置 `true`
- [ ] `deploy` 区块已按需登记上线计划或泳道回收（无部署需求时向用户说明并跳过）

## 下一步建议

- 上线前需要检查清单时执行 `release-check`
- 合并并上线完成后执行 `close`；关联的合并工作区会随之关闭
