# 写入项目 wiki 规则（公共写入指令）

> 所有写入 `$root/wiki/<project>/` 的流程统一按本文件执行：`init`、`record`、`close`、`ask` 归档与 `evolution` 索引补录都引用本文件，不再各写一套。
> 读取按 `harness/rule/wiki-read.md`；命名按 `harness/rule/naming.md`；项目由 `$work/status.yaml` 的 `project` 确定，无工作区时用 `project.sh project-list` 从 `tack.yaml` 选择，不跨项目读写。

## 一、组织方式：索引 + 小文件

- 每个项目 wiki 有一份总索引 `wiki/<project>/index.md`，每个分类目录有一份分类索引 `wiki/<project>/<分类>/index.md`。
- 索引只做导航：记录本分类/本文件收录什么、什么问题该去哪个文件或目录查，不复制正文。
- 内容按主题拆成小文件：一个主题一个文件，高内聚、低耦合；文件变小后检索与阅读都更省 token。
- 分类目录按需创建，不预造空目录、不造空文件；首次写入某分类时才创建该目录、分类索引与内容文件。
- 分类内容变多或主题可再分时，可在分类下自主创建子目录（如 `biz/domains/`、`code/analysis/`）并按主题拆文件；子目录内可再放 `index.md`，并在父分类索引登记该子目录或子索引。
- 索引尽量指向**具体文件**；确实需要指向目录时，只指向低层目录（如 `history/<workspace>/`、`code/analysis/`），不用高层分类目录代替文件清单。
- 新建文件前先按 `wiki-read.md` 读索引并检索同主题文件：已有同主题文件就地融合，确无合适文件才新建；不按「每次记录新建一个文件」的方式堆积碎片。

## 二、分类与落点

| 分类 | 目录 | 收录内容 |
|------|------|----------|
| 业务理解 biz | `wiki/<project>/biz/` | 业务线概述与长期背景、业务术语的标准定义与边界、按业务领域的职责与不变量、业务状态与不变量、来源资料索引 |
| 代码理解 code | `wiki/<project>/code/` | 仓库概览、业务术语 → 检索关键词/代码入口、非显然的接口标识 → 业务场景 → 代码入口；确需长期保留的分析全文放 `code/analysis/` |
| 项目规则 rule | `wiki/<project>/rule/` | 代码外的项目级决策（ADR）、工程约定与偏好（舍入、重试、默认值、命名/评审偏好等看的见代码但看不出「为什么」的「就这么定」） |
| 项目配置 config | `wiki/<project>/config/` | 服务清单与职责、外部依赖与协作契约、部署环境与泳道、网关/发布地址、租户、角色与账号申请方式、关键配置语义、中间件与平台事实 |
| 历史归档 history | `wiki/<project>/history/` | 每个已关闭工作区一个 `<workspace>/` 目录，内含 `summary.md`（原始资料、实现的功能、关键讨论与决策、对系统的影响、排查索引）与移入的 `run/` |

推荐文件名（可按主题继续拆小文件，命名见 `harness/rule/naming.md`）：

| 分类 | 常用文件 |
|------|----------|
| biz | `background.md`、`glossary.md`、`domains.md` |
| code | `repos.md`、`anchors.md`、`interfaces.md`、`analysis/` |
| rule | `decisions.md`、`conventions.md` |
| config | `services.md`、`env.md`、`accounts.md`、`settings.md` |
| history | `<workspace>/summary.md`、`<workspace>/run/` |

落点判定：

- 业务背景、术语释义 → `biz/`
- 代码导航锚点、仓库概览、接口映射、长期分析 → `code/`
- 项目级决策与工程约定 → `rule/`
- 服务、环境、账号、配置、中间件等代码外参数 → `config/`
- 某个需求「为什么做、影响什么」→ `history/<workspace>/summary.md`

## 三、写入流程

1. **确定项目与分类**：确认目标项目；按上表把内容归入唯一分类；跨分类内容分别落盘，不在一处混放。
2. **先检索再新建**：读取总索引与目标分类索引，检索是否已有同主题文件；有则就地融合，无则新建。
3. **按需建目录与索引**：分类目录不存在时创建目录，并从 `harness/template/wiki-category-index.md` 物化 `index.md`；项目总索引不存在时从 `harness/template/wiki-index.md` 物化。
4. **写入内容**：目标文件不存在时按对应模板创建（见第七节）；已存在则追加或融合，去重，不覆盖既有有效结论。
5. **更新索引**：新增文件在分类索引登记；新增分类在总索引登记；文件改名、移动、删除时同步更新对应索引，不留悬空路径。
6. **校验完整性**：执行 `sh $root/harness/script/wiki-index.sh check $root <project>`；退出码 3（存在未登记文件）时补齐索引后重跑，直到退出码 0。
7. **人工审阅**：展示落盘内容、路径与索引变更，经用户确认后才生效。

## 四、索引写法

- 路径一律相对**所在索引文件**书写：总索引写 `biz/index.md`，分类索引写 `background.md`，历史索引写 `<workspace>/`（相对 `history/`）。
- 分类索引必须列出该分类下的内容文件与主题，不能只写「见本目录」。
- 目录覆盖仅用于低层目录：如历史索引登记 `20261001-user-login/` 即代表该工作区的 `summary.md` 与 `run/` 均已登记；不得用 `biz/`、`code/` 这类高层目录覆盖整类文件。
- 索引条目用表格：主题 | 文件/目录 | 收录内容（或一句话说明）；新增/删除文件时同步增删行。

## 五、来源链与可信状态

- 每条新增/更新条目必须可回溯，来源按素材类型标注其一：
  - 工作区产物：`space/<workspace>/<文件>#<环节或章节>`
  - 用户引导：guidance 条目 id（如 `space/20261001-login/status.yaml G-03`）
  - git history：`commit <short-hash>`（结论须能由该 commit message 证实）
  - 用户资料：文档链接或「用户口述 <日期>」
- 表格类条目在「来源/备注」列标注；ADR 条目填「来源」字段。
- 同一条目被后续工作区再次证实时，在来源处追加出处；多来源即可靠性证据，不重复建条目。
- 半衰期事实必须包含：权威事实源、负责人、最近核验日期、复核条件。
- 可信状态：`confirmed`（用户或权威资料确认）、`verified`（已与代码/平台交叉验证）、`reported`（单一来源陈述）、`candidate`（尚待确认）；默认只有 `confirmed` 与 `verified` 可作为后续任务上下文。
- 来源不明、无法证实的内容拒绝写入。

## 六、矛盾与演变（修正而非覆盖）

- 事实/锚点类与已有条目矛盾时，就地更新为当前结论，并在备注注明「此前为 X，于 <日期> 因 <来源> 修正」。
- decisions 的 ADR 保留完整旧决策，状态置「已被 DEC-00N 取代」；新条目注明取代关系与重新决策的原因。
- 工程约定废弃时标记废弃日期与替代条目，不直接删除。
- 普通表格只保留必要的修正轨迹；原始来源永远留在工作区产物中。

## 七、模板与文件映射

| 目标文件 | 模板 |
|----------|------|
| `index.md`（项目总索引） | `harness/template/wiki-index.md` |
| `<分类>/index.md` | `harness/template/wiki-category-index.md` |
| `biz/background.md` | `harness/template/wiki-biz-background.md` |
| `biz/glossary.md` | `harness/template/wiki-biz-glossary.md` |
| `biz/domains.md` | `harness/template/wiki-biz-domains.md` |
| `code/repos.md` | `harness/template/wiki-code-repos.md` |
| `code/anchors.md` | `harness/template/wiki-code-anchors.md` |
| `code/interfaces.md` | `harness/template/wiki-code-interfaces.md` |
| `rule/decisions.md` | `harness/template/wiki-rule-decisions.md` |
| `rule/conventions.md` | `harness/template/wiki-rule-conventions.md` |
| `config/services.md` | `harness/template/wiki-config-services.md` |
| `config/env.md` | `harness/template/wiki-config-env.md` |
| `config/accounts.md` | `harness/template/wiki-config-accounts.md` |
| `config/settings.md` | `harness/template/wiki-config-settings.md` |
| `history/<workspace>/summary.md` | `harness/template/wiki-history.md` |

- 模板只在具备真实事实时物化，不造空文件；`decisions.md` 在出现第一条经审阅的决策时创建。
- `code/analysis/` 默认不登记长期全文：分析文档先留在 `$work/doc/analysis/` 与 `story/<story>/analysis.md`，确需长期保存时经用户确认迁入并在 `code/index.md` 登记。

## 八、边界

- 易变的代码实现逻辑、调用链、模块内部行为不进 wiki（代码是唯一真源；临期分析放 `$work/doc/analysis/` 与 `story/<story>/analysis.md`）。
- 代码、IDL、配置平台或部署平台是权威事实源时，wiki 只记录业务语义、查询入口、使用方式与负责人，不复制动态当前值。
- **禁止以 wiki 作为 wiki 更新的事实来源**：事实只能取自工作区原始产物（`context.md`、`story/*/analysis.md`、`story/*/spec.md`、`story/*/plan.md`、`doc/tech-design.md`、status.yaml、用户原话、代码、git history、用户资料）；已有 wiki 页面只用于确定「往哪里融合」，防止合成内容层层放大。
- 工作区级参数（MR 地址、泳道、构建版本、需求链接等）留在 `$work/status.yaml`，不写入项目 wiki。
- 不写密码、密钥、token 等凭据明文；只记录存放位置或获取方式。项目 wiki 随空间仓库提交前由 `scan-secrets.sh` 扫描，命中即阻断。
- 不写未经用户审阅的 AI 推断；不写一次性过程信息。

## 九、写入时机

| # | 时机 | 触发命令 | 行为 |
|---|------|----------|------|
| 1 | 首次初始化项目上下文 | `init` | 确定项目后按事实物化分类文件与索引，主动询问补全 |
| 2 | 后续补充项目上下文 | `init`（再次执行） | 携带新材料追加融合，不覆盖已有内容 |
| 3 | 用户主动要求沉淀 | `record` | 按用户要求写入当前项目 wiki，融合去重 |
| 4 | 工作区关闭 | `close` | 自动提炼工作区原始产物形成候选清单，经用户确认后写入；按 `archive-requirement.md` 归档 summary 与 `run/`，按 `archive-ask.md` 转化 ask 记录 |
| 5 | 代码分析发现线索 | `ask` | 只形成候选清单，用户确认后转 `record` 落盘，本命令不直接写项目 wiki |
| 6 | 索引完整性校准 | `evolution` | 用 `wiki-index.sh check` 找出未登记文件，按本文件补录索引 |

- 除以上时机外不主动改写 wiki；任何时机的写入都遵守本文件。
