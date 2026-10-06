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
   - 动作: 在 AGENTS.md 项目信息区块的 `project.service_repo_mapping` 追加 service_name / repo_git / repo_path（直接编辑区块 YAML），并按 init 第 6 步物化/更新 `wiki/manifest.md` 与 `wiki/code-understanding.md`：只渲染仓库/服务真实行；两张映射表（术语→检索词/代码入口、接口→业务场景）与环境事实章节有真实事实才填写，不臆造锚点；提示用户补全服务信息

## 后置完成检验

- [ ] `repo/<name>/` 下 `git status` 正常
- [ ] README 已创建，远端（若提供）已关联
- [ ] AGENTS.md 项目信息区块的映射已登记

## 下一步建议

- 执行 `work` 创建工作区时即可勾选该仓库
