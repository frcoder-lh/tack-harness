# Changelog

本文件（中文）与 `CHANGELOG.en.md`（English）是 tack harness 变更说明的双语单一事实源：

- 每个发布版本一节，标题格式 `## Vx.y.z (YYYY-MM-DD)`，条目为面向用户的功能点（按 新增/优化/修复 标注），不堆 commit
- 中英两份文件同版本条目一一对应、同步维护；`release.sh` 发版时校验目标 tag 在两份文件中均有对应段落，任一缺失即中止
- CI 创建 GitHub Release 时分别抽取两份文件的对应段落拼接为双语 Release body；`check-update.sh` 检查提醒与 `update` 命令展示「本次更新内容」均同时以两份文件为来源

## V0.0.15 (未发布)

- 优化: README 联系方式二维码改用 GitHub raw 绝对链接（`https://raw.githubusercontent.com/frcoder-lh/tack-harness/master/contact.png`），安装包、本机升级与空间初始化不再分发或物化 `contact.png`——物化到 `harness/` 的 README 在任意目录阅读均可直接显示图片；`contact.png` 源文件保留在仓库根供链接引用

## V0.0.14 (2026-10-07)

- 优化: Hook 空间/工作区解析改为无状态的当次 cwd 实时判定，移除 SessionStart 经 ENV_FILE 写入的 `TACK_ROOT`/`TACK_WORK` 路径环境变量——会话级缓存在多项目窗口、同一空间多工作区并行时无法表达「当次调用归属哪个空间/工作区」，且缓存校验只验自身有效、不查与 cwd 的从属关系，错配时不会触发回退；现三个 Hook 一律从 payload cwd 向上探测空间根，工作区先按 cwd 是否位于 `space/<name>/` 内精确命中（多工作区并行互不串扰），cwd 在工作区外时 SessionStart/UserPromptSubmit 回退最近活跃并提示确认、PreToolUse 留空且不扫描；拼命令改用注入文本中的绝对路径，`TACK_HOOK_LOG`/`TACK_HOOK_ENFORCE` 两个模式开关不变
- 新增: 英文版 README `README.en.md`——中文 README 的完整英文对照，两版顶部互链；安装（install.sh）、本机升级（skill-update.sh）、空间初始化（init-tack.sh）链路同步分发与物化中英双版 README
- 新增: 路由英文触发词——26 个命令与 5 个工作流的 front matter triggers 在保留中文的同时增补对应英文触发词，英文输入可直接路由（如 `requirement planning` → `spec`、`fix bug` → bugfix 工作流），中英 README 同步列出双语触发词
- 新增: CHANGELOG 双语与发版链路双语支持——新增 `CHANGELOG.en.md` 与中文条目一一对应；`release.sh` 发版前同时校验中英两份 CHANGELOG 段落齐备；CI Release body 中英双语拼接；`check-update.sh` 与 `update` 命令同时拉取并展示中英「本次更新内容」；`install.sh`/`skill-update.sh` 分发清单纳入中英 CHANGELOG

## V0.0.13 (2026-10-03)

- 新增: `code-review` 代码审查命令（简写 `rv`，触发词「代码审查/审查报告」）——以 `plan.md`/`tech-design.md` 为规范、与目标分支的三点 diff 为事实，按「仓库→文件→函数」逐函数分析改动内容（附代码锚点）、逻辑正确性、明显 bug 与代码层面危害（安全/性能/兼容性），并评估受影响接口与涉及业务场景，产出独立报告 `$work/code-review.md`；跨模块大改动可委派 code-reviewer 三视角并行，审查基准一致时 `merge` 门禁可复用报告结论
- 新增: `release-check` 上线检查命令（简写 `rc`，触发词「上线检查/发布检查」）——逐项识别数据库变更（给出可执行变更与回滚语句、执行环境与时机）、配置变更（给出键/值示例/生效环境模板）、新增接口调用（需申请的权限与白名单）、新增中间件（需提前申请配置的资源），另覆盖定时任务、凭据、灰度与回滚预案等兜底项，产出 `$work/release-check.md` 逐项打勾清单与上线顺序建议
- 新增: 共享脚本 `git-diff-context.sh`——解析目标分支（本地优先、回退 origin/、自动探测 master/main）、计算 merge-base 并导出三点 diff 与统计，为审查类命令提供确定性事实；E2E 覆盖本地/仅远端/无差异/错误路径
- 新增: Hook 统一日志——设置 `TACK_HOOK_LOG=1` 后三个 Hook 每次调用完整记录时间、事件、pid、cwd、环境变量、输入 payload 全文、注入/拦截输出全文、退出码与耗时到 `.tack/log/hook.log`（互斥锁整块串行追加、并发不交错）；关闭时 Hook 输出逐字节不变
- 优化: `TACK_ROOT`/`TACK_WORK` 接入实际消费——环境变量仅作 SessionStart 缓存，消费前校验空间标记、路径归属、工作区状态（非 completed），失效自动回退实时探测；UserPromptSubmit/PreToolUse 省去重复的向上探测与 space 全量扫描

## V0.0.12 (2026-10-01)

- 优化: `commit` 命令取消二次确认——用户发起命令即确认提交意图，提交信息自动生成（用户参数优先，否则结合实际 diff 与 `current.task`，Conventional Commits 风格）后直接提交，完成后如实汇报 commit hash、提交信息与改动文件清单；`push` 等影响远端的操作仍需用户明确指令
- 优化: 空间根 `.gitignore` 显式忽略任意层级 `local/` 目录（`local/` → `**/local/`，覆盖 `run/local/`、`space/*/local/` 等所有位置的敏感数据目录）
- 优化: `update` 指令融合空间根 `.gitignore`——新版模板与用户本地文件按新增/已修改/一致分类对比，走与 harness 文件一致的新增/覆盖/保留/融合流程；`.tack/` 条目为框架强制兜底，即便用户选择保留本地 `.gitignore` 也必须追加，防止运行时数据误入空间仓库

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
