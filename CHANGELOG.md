# Changelog

本文件是 tack harness 变更说明的单一事实源：

- 每个发布版本一节，标题格式 `## Vx.y.z (YYYY-MM-DD)`，条目为面向用户的功能点（按 新增/优化/修复 标注），不堆 commit
- `release.sh` 发版时校验目标 tag 在本文件中有对应段落，缺失即中止
- CI 创建 GitHub Release 时抽取对应段落作为 Release body；`check-update.sh` 检查提醒与 `update` 命令展示「本次更新内容」均以本文件为来源

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
