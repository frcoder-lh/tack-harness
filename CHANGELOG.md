# Changelog

本文件是 tack harness 变更说明的单一事实源：

- 每个发布版本一节，标题格式 `## Vx.y.z (YYYY-MM-DD)`，条目为面向用户的功能点（按 新增/优化/修复 标注），不堆 commit
- `release.sh` 发版时校验目标 tag 在本文件中有对应段落，缺失即中止
- CI 创建 GitHub Release 时抽取对应段落作为 Release body；`check-update.sh` 检查提醒与 `update` 命令展示「本次更新内容」均以本文件为来源

## V0.0.11 (2026-10-01)

- 新增: bugfix 工作流缺陷溯源环节——`harness/script/git-bug-trace.sh` 给定缺陷代码行，一键追溯引入缺陷的 commit、时间、作者、对应需求/工单 ID（`#123`/`MEEGO-456` 等）、commit 链接与合并到主干的 MR 链接（支持 GitHub/GitLab/Bitbucket）；结果写入 `status.yaml` 的 `bug_origin` 区块，诊断参考 `diagnosing-bugs.md` 新增对应阶段
- 新增: `test` 系统测试命令（把测试描述转化为 `$work/test.md` 可落地方案）与 `run` 脚本执行命令（`run/` 目录 + `run.md` 执行清单，敏感数据落 gitignored 的 `run/local/`）
- 新增: IDE Hook 可选加速层——`harness/script/hook/` 提供 SessionStart（预载路由表与工作区快照、导出 TACK_ROOT/TACK_WORK）、UserPromptSubmit（零往返 `scan-routes resolve` 注入 cmd/workflow 正文）、PreToolUse（边界观察：Git 双层边界/--force/--no-verify）三个事件；默认 observe 零拦截，`TACK_HOOK_LOG=1` 探针校准真实 payload，`TACK_HOOK_ENFORCE=1` 预留 deny 路径
- 新增: `install-hooks.sh` 初始化空间时自动生成 `.trae/hooks.json` 与 `.claude/settings.json`；需在 IDE「设置 > Hooks」手动启用后生效
- 优化: 工作区目录改为日期前缀命名 `space/<YYYYMMDD>-<branch>/`（如 `space/20261001-user-login/`），目录按名排序即按创建时间排序；git 分支名与 work_id 保持不带日期，`status.yaml` 新增 `work_dir` 字段，`work.sh` 末尾输出 `WORKSPACE`/`BRANCH` 结果行供调用方解析实际路径，`git-worktree-helper.sh` 与 `check-guidance.sh` 参数同步改为工作区目录名
- 优化: `testcode`/`test`/`run` 重定位为**按需命令**——移出 development 主链路环节映射，不占状态、不阻塞 commit/push/merge/close，AI 不在 code 完成后主动询问或引导；用户需要时直接触发或以 testing 工作流承接，不触发无需任何标记；删除 `testcode_skipped` 跳过机制与字段，三个命令的能力与产物保持不变
- 优化: 框架运行时数据统一收拢至 `.tack/`（log 日志 / backup 回滚备份 / tmp 临时文件 / state 本机状态），不入库、可随时清理
- 优化: skill 更新改为整体覆盖 `script/`、`template/`、`reference/`、`workflow/`（`cmd/` 只增补不覆盖、`rule/` 与 AGENTS.md 保留），临时产物统一落空间 .backup 并及时清理
- 优化: 修复空间标记探测的可靠性——`hook_grep_mark` 统一用 `LC_ALL=C grep` 纯字节匹配，规避 GNU grep 在 UTF-8 locale 下中文模式行为不稳定
- 修复: SKILL.md 与 hook 常量的空间标记文本与 AGENTS.md 实际文本不一致（缺空格），同步修正为「本空间由 tack harness 驱动」

## V0.0.10 (2026-09-30)

- 新增: check-update.sh 自动更新检查——close / evolution / record / help 命令收尾时静默检查新版本（7 天节流、同版本只提醒一次，不在会话开始时抢占任务），提醒附带「本机版本→最新版本」区间的全部更新内容
- 新增: release.sh 发版前校验 CHANGELOG 目标版本段落，缺失即中止；CI 创建 Release 时自动抽取对应段落作为 Release body
- 新增: 发版约定（根 AGENTS.md）——发版前由 AI 全仓扫描新增能力并融入 README（结构不动），覆盖 script/命令/工作流/核心特性四处落点
- 新增: git fetch 命令自动修复本地分支与远程同名分支的上游关联
- 修复: fetch 上游校验为同名分支，错名时自动纠正

## V0.0.9 (2026-09-30)

- 无功能性变更（发布流程维护）

## V0.0.8 (2026-09-29)

- 修复: update 命令补充本机 skill 更新步骤，修复更新后版本号不更新的设计缺口

## V0.0.7 (2026-09-29)

- 无功能性变更（发布流程维护）

## V0.0.6 (2026-09-29)

- 无功能性变更（发布流程维护）

## V0.0.5 (2026-09-29)

- 新增: install.sh 支持管道安装（`curl | sh` 免克隆一键安装，自动下载源码）
- 新增: 空间初始化时自动回填 skill_version 到 AGENTS.md 项目信息区块

## V0.0.4 (2026-09-29)

- 优化: 更新文档规范与配置，优化 wiki 内容定义

## V0.0.3 (2026-09-28)

- 无功能性变更（发布流程维护）

## V0.0.2 (2026-09-28)

- 新增: release.sh 发布脚本——自动压缩未推送提交、同步版本号、打 tag 并推送
- 优化: 重构 tack skill——workflow 状态机、依赖注入式路由与自进化机制
- 新增: workflow 约束——req-context 阶段禁改代码、develop 前置条件、worktree 内编辑

## V0.0.1 (2026-08-28)

- 新增: tack skill 初版——编程工作流引导、harness 骨架与安装脚本
- 新增: GitHub Actions release workflow（推 tag 自动打包发布）
