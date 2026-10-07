---
command: create-repo
short: cr
triggers: 新建仓库, 建仓, 新建代码仓库, create-repo, createrepo, create repo, new repository
params: [建仓目的]
summary: 在本地创建新的代码仓库并纳入项目空间管理
---

# create-repo 新建代码仓库

## 前置准入条件

- 已是 tack 项目
- `$root/repo/` 目录存在

## 指令内容

1. **明确建仓目的**
   - 输入: 建仓用途（承载什么服务、技术栈、与已有服务的关系）

2. **建议仓库名称**
   - 动作: 结合项目关键词与用途，给出 2-3 个英文 kebab-case 仓库名建议，用户选择或自行输入后确认

3. **创建仓库**
   - 动作: `mkdir -p $root/repo/<name>` 后在其中执行 `git init`；生成最小 README（仓库名 + 一句话用途）与合适的 .gitignore（按技术栈）

4. **关联远端（可选）**
   - 输入: 用户是否已有远端仓库地址
   - 动作: 有地址则执行 `git remote add origin <url>`；没有则提示先在代码平台建仓，稍后可补

5. **登记映射**
   - 动作: 执行 `sh $root/harness/script/project.sh service-repo $root "<服务名称>" "<repo 名>" "<repo_git，未关联远端则空串>" "repo/<name>"` 追加 AGENTS.md 项目信息区块的 `project.service_repo_mapping`，并按 init 第 6 步物化/更新 `wiki/manifest.md` 与 `wiki/code-understanding.md`：只渲染仓库/服务真实行；两张映射表（术语→检索词/代码入口、接口→业务场景）与环境事实章节有真实事实才填写，不臆造锚点；提示用户补全服务信息

## 框架自动提交（无需用户操作）

- 动作: 第 5 步 `project.sh service-repo` 执行时自动把 AGENTS.md 映射变更提交到 tack 空间根仓库（无变更自动跳过）；wiki 物化变更随后执行 `sh $root/harness/script/space.sh commit $root "chore(tack): register repo <name>"` 统一收尾
- 边界: 遵守 `harness/rule/git-boundary.md`；新代码仓库内的 README / .gitignore 首次提交由用户经 `commit` 命令发起，框架不代提

## 后置完成检验

- [ ] `repo/<name>/` 下 `git status` 正常
- [ ] README 已创建，远端（若提供）已关联
- [ ] AGENTS.md 项目信息区块的映射已登记

## 下一步建议

- 执行 `work` 创建工作区时即可勾选该仓库
