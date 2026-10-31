# work 流程：分支操作（branch-op）

> 由 `cmd/base/work.md` 意图分流判定为分支操作时加载；「新建工作区」各步骤见主文件。

> 本流程只建区与准备，后续状态流转按 `harness/workflow/branch-op-workflow.md` 执行。
> 不录入需求、不做 ask/spec/plan、不做审查与测试（跳过项以工作流文件为准）。

1. **解析分支操作参数**
   - 动作: 从原始输入解析 op（「合并」→merge，「变基」→rebase）、源分支 A、目标分支 B，以及源分支引用（本地分支 / 远程分支）
   - 源分支引用: `local` 取本地 A（含未推送提交）、`remote` 取 `origin/A`（仅已推送提交）；未指定时用 `auto`（远端优先、本地兜底）。由 `merge` 命令派生时使用 merge 流程已确认的取值
   - 边界: 无法同时解析出两个分支、或操作词有歧义（如只说「处理一下 A 和 B」）时，追问补齐，不得带模糊参数建区

2. **确认涉及仓库**
   - 动作: 在 `$root/repo/` 各仓库内 `git fetch origin --prune`，检查 A、B 是否存在（远端优先、本地兜底）；逐仓库记录检查结果
   - 输入: 多个仓库同时具备这两个分支时，列出清单由用户多选确认；仅一个仓库满足时直接请用户确认；无仓库满足时回报事实并停止

3. **确定工作区名**
   - 动作: 直接取 `bop-<a>-to-<b>`（分支名中的 `/` 替换为 `-`，命名遵守 `harness/rule/naming.md`），随仓库确认一并告知，不生成候选；用户自行指定时采用用户输入；与已有工作区或登记冲突（`work-create` 报错）时追加 `-2` 等序号后重试并说明

4. **创建并登记工作区（只建上下文文件，不建默认 worktree）**
   - 动作: 按 `cmd/base/work.md`「新建工作区」的「确定所属项目」步骤确定项目后执行
     `sh $root/harness/script/command-batch.sh work-create $root <project> <branch> "branch-op: <op> <A> → <B>" "<repo1,repo2>" "<op>,branch-op,<A>,<B>" branch-op`
     一次生成 `space/<YYYYMMDD>-<branch>/` 下的 `status.yaml`（含 project、`workflow: branch-op`、services）与 `context.md`，并登记到 `tack.yaml`；`story/`、`doc/`、`repo/` 等目录按需创建
   - 解析输出: 取结果行 `WORKSPACE=<工作区目录名>`，为上下文赋值 `$work=$root/space/<WORKSPACE>`，后续步骤以该值为准

5. **prepare：临时分支与工作 worktree**
   - 动作: 逐仓库执行
     `sh $root/harness/script/branch-op.sh prepare $root space/<WORKSPACE> <repo> <op> <A> <B> [auto|local|remote]`
     fetch 后按源分支引用创建 `A-<时间戳>`、`B-<时间戳>` 临时分支，并为工作分支（merge 取 B-ts，rebase 取 A-ts）创建 worktree 到 `space/<WORKSPACE>/repo/<repo>`
   - 解析输出: `BRANCH_OP_TS`、`BRANCH_OP_SOURCE_TMP`、`BRANCH_OP_TARGET_TMP`、`BRANCH_OP_WORKING`

6. **register：一次写入状态与临时分支**
   - 动作: 全部仓库 prepare 成功后执行
     `sh $root/harness/script/branch-op.sh register $root space/<WORKSPACE> <op> <A> <B> <auto|local|remote> <repo1>:<source_tmp>:<target_tmp> [<repo2>:...]`
     脚本按 `harness/template/work-status.yaml` 结构写入 `branch_op` 区块（source_ref、每仓库临时分支与工作分支、`pushed: false`），置 `status: preparing`、`stage: prepare`，并把每仓库两个临时分支登记到 branches（role=tmp, source=branch-op，供 close 遍历清理）；输出 `BRANCH_OP_REGISTERED=<仓库数>`
   - **关联来源**: 由 `merge` 命令派生时，merge 流程另行执行 `sh $root/harness/script/work-status.sh $root/space/<WORKSPACE>/status.yaml set parent_workspace "<来源工作区目录名>"`，把新工作区关联到来源工作区；本命令不推断来源

7. **跳过常规开场动作**
   - 边界: 不输出 roster、不引导 context.md/analyze/spec；登记完成即按 branch-op 工作流进入 integrate 环节
