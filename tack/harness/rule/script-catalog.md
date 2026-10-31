# 固定流程脚本清单

> 常驻 AGENTS.md 只保留「`harness/script/` 固定流程脚本」一句，本文件在需要选脚本或核对调用时加载。
> 所有 `.sh` 均为 POSIX sh；Windows 经 `run.ps1` 启动器调用（见 `harness/rule/windows-env.md`）。

## 空间与路由

| 脚本 | 作用 |
|------|------|
| `init-tack.sh` | 确保 Git 可用、物化空间骨架、初始化空间仓库并首次提交 |
| `space.sh commit` | 空间根仓库的唯一自动提交入口：按调用方文件清单精确暂存并校验归属（含凭据扫描） |
| `space-lock.sh` | 空间级互斥锁：登记写入与空间提交串行（被 project.sh / space.sh / work.sh source） |
| `scan-routes.sh` | 扫描 workflow/cmd/agents；`list` 完整表、`index` 紧凑索引、`show` 单个定义、`resolve` 路由解析 |
| `common.sh` | 安装/升级/版本检查共享函数（分发清单、下载回退、版本提取） |
| `yamlib.awk` | YAML 标量与行内列表解析库（被多个脚本 source） |

## 登记与工作区

| 脚本 | 作用 |
|------|------|
| `project.sh` | 维护 `tack.yaml`（兼容旧 AGENTS 区块）：空间元信息、项目、服务映射、工作区登记与查询；`migrate` 迁出旧区块 |
| `work.sh` | 新建/重命名/删除工作区目录，创建 status.yaml 与 context.md |
| `work-status.sh` | 确定性回写工作区 status.yaml（状态、进度、任务、分支、guidance 等） |
| `repo.sh` | 主仓库扫描、软链、克隆与远端同步 |
| `workspace-archive.sh` | close 时列出非标准文件、把产物移入 history 归档目录 |
| `run-plan.sh` | run 指令清单只读检查（格式、依赖与必需文件） |
| `trigger-extract.sh` | 从工作区目的描述提取切换触发词 |

## Git 与分支

| 脚本 | 作用 |
|------|------|
| `git-facts.sh` | 采集仓库/分支/提交事实 |
| `git-fetch-helper.sh` | 单仓库 fetch/pull 与状态同步 |
| `git-commit-helper.sh` | 生成提交信息并提交代码仓库 |
| `git-push-helper.sh` | 推送代码仓库（拒绝 force 参数） |
| `git-worktree-helper.sh` | 工作区 worktree 创建与移除 |
| `git-diff-context.sh` | 汇总指定仓库的 diff 上下文 |
| `git-bug-trace.sh` | 缺陷引入 commit 溯源 |
| `branch-op.sh` | 分支级 merge/rebase 的临时分支与集成、清理 |
| `branch-clean.sh` | close 时按登记清理已合并/临时分支 |

## 质量、发布与备份

| 脚本 | 作用 |
|------|------|
| `lint-harness.sh` | harness 结构自检（frontmatter、四段契约、路由冲突） |
| `lint-shell-portability.sh` | sh 脚本三平台可移植性检查 |
| `lint-doc-scripts.sh` | 文档中的脚本调用签名与脚本用法核对 |
| `scan-secrets.sh` | 凭据明文扫描（空间提交前硬门禁） |
| `wiki-index.sh` | 项目 wiki 索引完整性检查 |
| `harness-diff.sh` | 本机 harness 与新版 skill 的差异分类 |
| `harness-backup.sh` | harness/AGENTS.md/tack.yaml 的备份、恢复与校验 |
| `harness-resync.sh` | 旧流程空间一次性重建 harness 与 AGENTS.md（备份、迁移旧登记后覆盖，随后切换新版 update 流程） |
| `skill-update.sh` | 更新本机已安装 skill |
| `check-update.sh` | 空间版本检查与更新提醒（close/evolution/record/help 挂载） |

## Hook（可选加速层）

| 脚本 | 作用 |
|------|------|
| `hook/install-hooks.sh` | 物化 TRAE/Claude Code hook 声明 |
| `hook/on-session-start.sh` | SessionStart：只注入空间位置 |
| `hook/on-prompt-submit.sh` | UserPromptSubmit：按路由结果注入索引或指令正文 |
| `hook/on-pre-tool-use.sh` | PreToolUse：Git 边界观察层（默认不拦截） |
| `hook/hook-common.sh` | Hook 公共函数（空间探测、payload 解析、日志） |
