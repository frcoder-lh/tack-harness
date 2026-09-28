---
command: work
short: w
triggers: 工作区, 新建工作区, 切换工作区, work
params: [目的或分支名]
summary: 工作区管理——新建、重命名、切换、列出工作区（space/<branch>/），自动推断服务并登记到 AGENTS.md
---

# work 工作区管理

> 工作区位于 `$root/space/<branch>/`；项目信息（含 work 列表）维护在 AGENTS.md 项目信息区块。

## 前置准入条件

- 已是 tack 空间（`$root/AGENTS.md` 存在且含项目信息区块）
- 新建工作区前，`$root/repo/` 下建议至少有一个仓库（无仓库时创建占位工作区，稍后可用 worktree 补建）

## 指令内容

先将用户意图识别为四类之一：**新建 / 重命名 / 切换 / 列出**。

### 新建工作区

1. **获取工作区目的**
   - 输入: 工作区目的描述（如「用户登录功能」）

2. **澄清具体意图**（目的已具体到能判断要解决的问题与改动范围时，跳过本步）
   - 判定: 描述宽泛、存在多种解读（如「优化下单」「修复支付问题」）即视为意图不明确，不得带着模糊目的直接命名
   - 动作: 结合 AGENTS.md 项目信息区块的 keywords、service_repo_mapping（`wiki/manifest.md` 存在时一并参考），给出 3 个左右可能的具体意图候选，每条一句话说明对应要解决的问题方向；用户可单选、组合多个候选或自行补充
   - 输入: 用户选定后固化为明确的目的描述；一次澄清仍不明确则继续追问，直到问题边界可判断

3. **生成并确认分支名**（澄清意图之后才进行命名）
   - 动作: 依据明确后的目的，生成 3 个英文 kebab-case 分支名候选
   - 输入: 用户选择候选或自行输入；展示最终名称并请用户确认

4. **自动推断需要的服务**
   - 输入: 工作区目的 + AGENTS.md 项目信息区块的 service_repo_mapping（主数据源，必然存在）
   - `wiki/manifest.md` 存在时一并读取，补充职责、部署地址等上下文；不存在不影响推断（wiki 文件按需物化）
   - 动作: 根据目的关键词推断涉及的服务/仓库，列出推断结果由用户多选确认（可全部取消）

5. **创建工作区**
   - 动作: 执行
     `sh $root/harness/script/work.sh $root <branch> <已选仓库名...>`
     自动创建 `space/<branch>/` 扁平骨架（status.yaml、input.md、repo/），并为每个仓库创建 git worktree 到 `space/<branch>/repo/<repo-name>`

6. **登记并切换上下文**
   - 动作: 执行
     `sh $root/harness/script/project.sh work-add $root <branch> "<目的描述>" "$root/space/<branch>" <branch> "<服务1,服务2>"`
     在 AGENTS.md 项目信息区块追加 work 条目；为上下文赋值 `$work=$root/space/<branch>`

7. **输出开场知识清单（roster，只列不读）**
   - 动作: 上下文就绪后，给用户一份「一行一项」的知识清单，**不贴正文**，需要时再按路径读取：
     1. `$root/wiki/` 下已存在的页面（manifest / code-understanding / business-understanding / decisions，标注各自用途一句话）
     2. `$root/wiki/code-understanding.md`「工作区分析文档索引」中与本次已选仓库相关的分析文档（含基准 commit）；
        对每份文档取对应 worktree 当前 HEAD，与基准不一致时标注「可能已过时（偏离 N 提交），必要时先跑 ask 更新」
     3. **冷仓库提示**：已选仓库在索引中无任何分析记录时，提示「该仓库尚无分析文档，建议在 spec/plan 前执行 `ask <仓库名>` 整体分析」（仅建议，不自动执行）
   - 边界: 清单是可选读的导航，不把 wiki 全文塞入上下文；知识不足时按三级降级取用（wiki → `$work/wiki/` → 直接读代码，代码永远是真源，见 development 工作流「上下文加载原则」）

### 重命名工作区

1. 输入新的目的描述；描述宽泛时按「新建工作区」第 2 步先澄清意图，再生成并确认新分支名
2. 重命名 `space/<old>/` 为 `space/<new>/`
3. 遍历该工作区每个仓库，在 worktree 内执行 `git branch -m <old> <new>`
4. 直接编辑 AGENTS.md 项目信息区块中该条目（work_id / work_path / branch）与 `$work/status.yaml`（work_id / branch）；若重命名的是当前工作区，更新 `$work`

### 切换工作区

1. 读取 AGENTS.md 项目信息区块的 work 列表（或扫描 `space/` 目录），高亮当前工作区
2. 输入目标工作区；目标不存在时询问是否新建
3. 为上下文赋值 `$work=$root/space/<target>/`，重新读取该工作区 status.yaml（不相信上下文里的旧内容）
4. 按「新建工作区」第 7 步输出该工作区的开场知识清单（wiki 页面 + 相关分析文档新鲜度 + 冷仓库建议），只列不读

### 列出工作区

1. 以表格展示全部工作区：work_id / 描述 / 状态 / 分支，当前工作区标记「（当前）」
2. 可接受用户序号或分支名输入，直接进入切换

## 框架自动提交（无需用户操作）

- 动作: 新建路径的提交已由 work.sh、project.sh 自动完成；重命名等直接编辑过 AGENTS.md / status.yaml 的路径，结束前执行 `sh $root/harness/script/space.sh commit $root "chore(tack): workspace <branch>"` 兜底（无变更自动跳过）
- 边界: 遵守 `harness/rule/git-boundary.md`；工作区内的分支重命名（`git branch -m`）作用于代码仓库，属用户仓库操作

## 后置完成检验

- [ ] `space/<branch>/status.yaml`、`input.md` 已生成
- [ ] 已选仓库在 `space/<branch>/repo/` 下有可用 worktree
- [ ] AGENTS.md 项目信息区块的 work 列表与磁盘一致
- [ ] 已输出开场知识清单（roster）：已列 wiki 页面与相关分析文档（含新鲜度），冷仓库已建议 ask；未向上下文塞入 wiki 全文

## 下一步建议

- 向 `$work/input.md` 录入原始需求，然后执行 `spec`
