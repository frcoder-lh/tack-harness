---
command: analyze
short: an
triggers: 需求分析, 分析需求, 需求可行性, 需求兼容性, requirement analysis, analyze requirement, feasibility analysis
params: [需求描述或 story 目录名（可选）]
summary: 新建工作区后、spec 之前的需求分析——前置为用户已提供需求内容或需求文档；按「先读需求内容 → 检索 doc/analysis 与项目 wiki → 最后检索代码」的顺序，识别研发 story（一个完整闭环功能）并产出 story/<story>/analysis.md（现有实现、可行性、兼容性、待确认问题与讨论记录），为 spec/plan 提供代码侧依据
---

# analyze 需求分析

> 时机：`work` 建区之后、`spec` 之前。需求可以一次提供多条，也可以分先后追加；每条明确需求都要落到某个 story 的 `analysis.md`。
> **前置是用户已提供需求内容或需求文档**：没有需求内容不进入分析，先引导用户补充。
> **检索顺序固定为三步**：先读需求内容 → 再检索 `$work/doc/analysis/` 与项目 wiki → 最后才检索代码；代码只用于核实与定位，结论必须有代码依据（`仓库/路径#L12-L15`）。
> **story 是研发视角的完整闭环功能**——能独立开发、独立验证、独立交付；与产品文档里的 story 不要求一一对应，也不按单个接口或单张表切分。
> 只读代码，不改代码。需求明确前的泛代码问答走 `ask`，产物落 `$work/doc/analysis/`。

## 前置准入条件

- 已确定当前工作区 `$work`（`$root/space/<workspace>/`）与所属项目（`$work/status.yaml` 的 `project`）
- **用户已输入需求内容或提供需求文档**（已写入 `$work/context.md`，或本次对话直接给出需求/文档）；需求为空或只有模糊目的时先引导用户补充，不凭空编造需求；用户只是就现有代码提问时转 `ask`
- 执行前重新读取 `$work/status.yaml`、`$work/context.md`、已有 `story/*/analysis.md` 与 `$work/doc/analysis/`，尊重本地最新内容

## 指令内容

1. **回写环节状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set status planning stage analyze next "识别 story 并生成或更新 story/<story>/analysis.md"`（自动刷新 updated_at）

2. **读取需求内容（第一步）**
   - 输入: `$work/context.md` 全文（含用户本次追加的需求）；用户提供需求文档时先读该文档
   - 动作: 提炼需求目标、触发条件、输入输出、边界与不做的事；用户本次给出、尚未落到 `context.md` 的需求，原样整理进 `context.md`（只做格式整理，不改写原意）
   - 边界: 需求不足以判断问题边界时先追问补齐，不带着模糊需求进入后续检索

3. **检索工作区分析与项目 wiki（第二步，不检索代码）**
   - 输入: `$work/story/*/analysis.md` 的头部与结论区；`$work/doc/analysis/` 下与本需求相关的问答文档；`$root/wiki/<project>/` 按 `harness/rule/wiki-read.md` 走索引检索；`status.yaml` 的 tasks 与服务登记
   - 动作: 先 grep/glob 与索引定位，再读命中片段，记录可复用的既有结论与导航锚点
   - 加载纪律: 遵守 `harness/rule/context-loading.md`，不整仓通读；本步只收集既有知识，代码检索留到第 5 步

4. **识别或更新 story**
   - 动作: 把 `context.md` 中尚未落到 story 的需求，按「完整闭环功能」拆成 story；已存在的 story 与新需求相关时更新该 story 的 analysis，不重复新建
   - 判定: 一个 story 应能独立完成「入口 → 处理 → 结果」的闭环，并能有独立的验收方式；把同一闭环内的多个接口/页面/表归入同一 story，不按技术单元切分
   - 输出: story 清单（目录名 | 功能边界一句话 | 来源 context.md 小节 | 新建/更新），目录名用英文 kebab-case（`harness/rule/naming.md`，如 `login-validation`）
   - 输入: 用户确认 story 拆分与目录名；确认后 `mkdir -p $work/story/<story>`；用户要求合并或拆分时先调整清单再建目录

5. **逐 story 检索代码并生成 analysis.md（第三步，代码最后检索）**
   - 输入: 本 story 对应的需求内容（第 2 步）、`$work/doc/analysis/` 与 `$root/wiki/<project>/` 命中内容（第 3 步）、代码事实、近期 git history 线索
   - 代码检索顺序: 优先 `$work/repo/<repo-name>/`（已有 worktree，当前分支），没有所需仓库时用 `$root/repo/<repo-name>/`（只读基准）；本命令不创建 worktree；只检索前两步未覆盖、确需代码核实与定位的部分
   - 动作: 按 `$root/harness/template/analysis.md` 在 `$work/story/<story>/analysis.md` 输出：
     1. **需求理解**：触发条件、输入输出、边界与不做的事
     2. **现有实现**：入口、调用链、数据模型、配置与关键分支，逐条附 `仓库/路径#L12-L15` 锚点
     3. **可行性判断**：可实现 / 需改造 / 不可行，写明依据的模块与前置依赖
     4. **兼容性评估**：接口、数据结构、配置、上下游与既有行为的影响面
     5. **实现建议与风险**：路线级建议，不写详细设计与编码步骤
     6. **待确认问题**：逐条列出，多轮讨论后关闭并写结论
     7. **讨论记录**：`Q<n>` 问答追加
   - 头部固定记录 `需求来源`、`涉及仓库`、`基准 commit`、`最近更新` 与 `状态`（analyzing / analyzed），供后续新鲜度判断
   - 纪律: 不臆测未读代码的行为；无法确认的部分标「待确认」；引用文件或代码用 `仓库/路径#L12-L15`，代码片段上方标注同格式锚点，每个关键判断对应直接证据；本文档是绑定当前分支的临期分析，不写入项目 wiki

6. **多轮追加与讨论**
   - 动作: 用户追加需求或继续追问时，重读 `context.md` 增量与对应 story 的 analysis.md，在同主题文档中追加 `Q<n>` 与结论，融合更新上方结论区、待确认问题、基准 commit 与最近更新
   - 分流: 与明确需求无关的代码逻辑问答转 `ask`，落到 `$work/doc/analysis/<主题>.md`；不同需求主题才新建 story；同一 story 的多轮讨论不新建文件
   - 边界: 需求变更影响 story 边界时，先在清单中说明调整并请用户确认，再改写 analysis

7. **汇总与审阅**
   - 动作: 列出本次新建/更新的 story 目录、analysis 摘要与待确认问题；提示用户逐份审阅
   - 边界: 用户可直接修改文档；分析有误时重查对应章节并据实更新

8. **回写完成状态**
   - 动作: 执行 `sh $root/harness/script/work-status.sh $work/status.yaml set progress.analyze true stage analyze next "逐 story 执行 spec"`

## 框架自动提交（无需用户操作）

- 动作: 执行 `sh $root/harness/script/space.sh commit $root "chore(tack): requirement analysis <branch>"`，把 `context.md`、`story/*/analysis.md` 与 status.yaml 的变更自动提交到 tack 空间根仓库；无变更自动跳过
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] 前置需求已具备：需求内容或需求文档已读，并已与 `context.md` 对齐（原意未改写）
- [ ] 分析按「需求内容 → `doc/analysis/` 与项目 wiki → 代码」三步执行，代码检索仅用于核实与定位
- [ ] `context.md` 中的每条明确需求都已归属某个 story，或有明确的待确认说明
- [ ] story 按完整闭环功能拆分，目录名为英文 kebab-case，已创建 `$work/story/<story>/`
- [ ] 每份 `analysis.md` 覆盖现有实现（含 `仓库/路径#L12-L15` 锚点）、可行性、兼容性、实现建议与待确认问题
- [ ] 文档头部记录需求来源与基准 commit；多轮讨论已就地融合，未重复建文件
- [ ] 需求无关的代码问答已转 `ask` 落 `doc/analysis/`；本命令未修改任何代码文件
- [ ] `status.yaml` 已同步（stage=analyze；确认后 progress.analyze=true）

## 下一步建议

- 对每个 story 执行 `spec <story>` 生成顶层设计与公共契约；需求仍有疑问时继续在本 story 的 `analysis.md` 中讨论
- 需求明确前的代码理解问题执行 `ask`，产物留在 `$work/doc/analysis/`，供后续分析引用
