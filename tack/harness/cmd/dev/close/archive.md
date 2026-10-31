# close 流程：工作区归档与 wiki 提炼（第 5、6 步）

> 由 `cmd/dev/close.md` 在 branch-op 以外的工作流进入第 5 步时加载；步骤编号与主文件一致。

5. **工作区归档（自动判定 summary.md 与 run/ 的保存价值）**
   - 判定: 按 `harness/rule/archive-requirement.md`「归档判定」自动判断——
     - 不归档 summary: 无真实 context、无 story/spec/plan 且仅机械性/格式性改动的简单工作区
     - 应归档 summary: development / bugfix 等有需求背景与功能交付，且存在需要日后回忆的「为什么」（功能取舍、边界约定、关键讨论、设计决策）或对系统行为/接口/数据/配置/权限/依赖有影响
   - 归档目录: 固定为 `$root/wiki/<project>/history/<workspace>/`（`<workspace>` = `basename "$work"`，与工作区同名）；写 summary.md 前执行 `mkdir -p "$root/wiki/<project>/history/<workspace>"`（移动文件时由 `workspace-archive.sh` 自动创建）
   - summary.md: 应归档时按 `harness/template/wiki-history.md` 生成 `summary.md`（固定文件名）；内容为原始资料、实现的功能、关键讨论与决策、对系统的影响、排查索引，全部用业务语言分条陈述，不保留实现过程（编码步骤、文件/行号、调用链）、可行性分析与找 bug 过程；同目录已存在时就地融合更新，不覆盖
   - **登记历史索引**: 归档目录创建后，按 `harness/rule/wiki-write.md` 在 `$root/wiki/<project>/history/index.md` 登记本工作区目录（登记目录即覆盖 `summary.md` 与 `run/`）；索引文件不存在时按 `harness/template/wiki-category-index.md` 创建，项目总索引不存在时按 `harness/template/wiki-index.md` 创建并登记 `history/index.md`
   - run/ 归档: `$work/run/` 存在时执行 `sh $root/harness/script/workspace-archive.sh move $root <project> <workspace> run`，把整个 run 目录（指令索引、各指令脚本与数据、local/）原样移入归档目录；`run/*/local/` 仍被 .gitignore 忽略、不入库，提醒用户密钥只留在本地
   - 其他文件: 执行 `sh $root/harness/script/workspace-archive.sh list $root <workspace>` 取得标准产物之外的文件/目录清单（标准产物：status.yaml、context.md、story/、doc/、repo/、run/），逐项询问用户是否移入归档目录；用户选择移入的执行 `sh $root/harness/script/workspace-archive.sh move $root <project> <workspace> <相对路径>...`，其余随工作区删除
   - 输入: `$work/context.md`（含原始资料链接）、`story/*/analysis.md`（现有实现与兼容性）、`story/*/spec.md`（背景/目标/功能/边界）、`story/*/plan.md`（决策记录）、status.yaml（meego / mr_url / tech_doc_url）、各仓库 git 事实（交付功能与影响面）；`$work/doc/analysis/` 的 ask 产物按第 6 步处理
   - 边界: 不归档且无 run/、无用户选择移入的文件时，一句话说明判定结果并跳过本步；`repo/` 下代码不得移入归档；展示归档路径与 summary.md 摘要，经用户确认后生效，用户放弃则不写 summary.md

6. **提炼工作区内容，确认是否记入 wiki**
   - 输入源: 工作区**原始产物**——context.md、`story/*/analysis.md`、`story/*/spec.md`、`story/*/plan.md`（含决策记录）、`doc/tech-design.md`、`doc/analysis/`、status.yaml（mr_url、tech_doc_url、meego 等）；**已有项目 wiki 页面只用于确定融合位置，不作为事实来源**（防合成内容循环放大，见 `harness/rule/wiki-write.md` 边界）
   - 动作: 从中提炼**跨工作区复用、且代码不应作为真源**的候选知识，按 `harness/rule/wiki-write.md`「分类与落点」归入 `$root/wiki/<project>/` 对应分类（业务背景、代码锚点、项目规则、项目配置的具体落点见该规则）
   - **ask 记录归档**: 扫描 `$work/doc/analysis/` 目录下全部按主题命名的分析/问答文档（按目录与头部主题匹配，不假定 `-analysis` 后缀或固定文件名），按 `harness/rule/archive-ask.md` 转化后分流——业务名词解释进 `biz/glossary.md`、代码名词/导航进 `code/anchors.md` 与 `code/interfaces.md`、稳定代码外事实进 `config/`、项目级决策约定进 `rule/`、需求特定的「为什么/是否设计如此」融合进第 5 步的 `history/<workspace>/summary.md`；不原样复制，不保留可行性分析与找 bug 逻辑；无符合项时跳过
   - 边界: 易变的代码实现、调用链、模块内部行为**不进 wiki**（以代码为唯一真源）；工作区级参数（MR 地址、泳道、构建版本等）留在 `$work/status.yaml`，不写入项目 wiki；通用编码规范不进 `rule/decisions.md`（走第 7 步 rule）；来源不明、无法从工作区产物证实的内容不提炼
   - 询问: 以候选条目清单（含建议落点与**来源标注**）询问用户**是否记入项目 wiki**；用户可全部采纳、挑选部分或放弃
   - 落盘: 被采纳条目按 `harness/rule/wiki-write.md` 写入 `$root/wiki/<project>/` 对应分类文件——文件已存在则融合去重（不重复追加），不存在时按对应模板创建（`rule/decisions.md` 首条采纳时才创建）；每个新增文件同步登记分类索引与项目总索引；每条带来源（`space/<workspace>/<文件>`，`<workspace>` 即当前工作区目录名），与旧条目矛盾时按「矛盾与演变」规则保留轨迹；**必须经人工审阅确认后才生效**；用户放弃则跳过；落盘后执行 `sh $root/harness/script/wiki-index.sh check $root <project>` 确认退出码 0
