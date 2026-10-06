---
command: study
short: st
triggers: 学习, 研习, 借鉴, study, learn, learn from
params: [skill 名称/本地目录路径或 Git 仓库链接]
summary: 学习外部 skill 或仓库的设计，提炼可借鉴点并直接优化 harness 各环节，统一预览确认后提交，随后自动执行一次 evolution
---

# study 学习借鉴

> 「向外学习」：把一个外部 skill 或仓库当作教材，通读其结构与设计，提炼对 tack harness 有价值的做法，
> 直接以**新增、融合、优化**的方式落到 harness 对应位置；中途不打断用户，只在全部落盘后给一次统一预览。
> 与邻近命令的分工：
> - `evolution`——**向内**自审，从现有 cmd 中提炼 rule/reference/script（无外部素材）
> - `record`——沉淀用户明确给出的内容或 guidance 条目
> - `update`——同 skill 新旧版本之间的升级融合
> - `study`——**向外**学习第三方 skill/仓库，借鉴其流程、命令、规则、脚本、模板与组织方式
>
> 纪律：所有结论必须来自素材中实际读到的文件，禁止臆测；尽量不删除已有内容；唯一确认点是第 6 步统一预览。

## 前置准入条件

- 已是 tack 空间（`$root/harness/cmd/` 存在）
- 必须携带一个参数：某个 skill 的名称/本地目录路径，或某个仓库的 Git 链接
- 参数无法定位到任何素材时，说明判定过程并停止，不得以想象内容替代

## 指令内容

1. **定位并获取学习素材**
   - 输入: 用户参数，按以下顺序判定类型：
     - **Git 链接**（以 `http://`、`https://`、`git@`、`ssh://` 开头，或以 `.git` 结尾）: 浅克隆到**空间内临时目录**——先 `mkdir -p $root/.tack/tmp`，再执行 `git clone --depth 1 <链接> $root/.tack/tmp/study-clone-<时间戳>`；该目录仅用于本次分析，在第 7 步收尾删除，不使用系统临时目录
     - **本地目录路径**（路径存在且为目录）: 直接以该目录为素材目录，不复制、不改动
     - **skill 短名称**（其余情况）: 在本机已安装 skill 目录查找 `<名称>/`：
       - Windows: `%USERPROFILE%\.trae-cn\skills\`、`%USERPROFILE%\.trae\skills\`
       - macOS/Linux: `~/.trae-cn/skills/`、`~/.trae/skills/`
       - 命中即作为素材目录；多个命中时取最匹配项并在报告中注明
   - 识别素材形态: 含 `SKILL.md`（或等价入口如 `skill.md`、`plugin.json`）视为 **skill**，否则视为**通用仓库**；两种形态都按其真实目录结构分析，不套用固定假设
   - 记录来源标识（URL 用仓库地址，本地用绝对路径，skill 用名称），后续提交信息与变更报告都引用它

2. **通读与结构化分析**
   - 动作:
     - 先列目录树（忽略 `.git/`、`node_modules/`、构建产物等），识别其组织方式：入口文档、命令/指令、工作流/流程编排、脚本、规则/规范、模板、prompt/agent、参考资料、测试
     - 先读入口文件（`SKILL.md`/`README.md`/`AGENTS.md` 类），建立全貌后再按目录读其余文件；素材规模大时按「与 harness 设计的相关性」决定阅读深度，业务代码、无关示例不逐行通读
   - 产出: **可借鉴点清单**，每条记录：
     - 来源位置（相对路径 + 章节/行）
     - 内容摘要（它解决什么问题、怎么做的）
     - 借鉴类型：工作流设计 / 命令设计 / 规则规范 / 脚本自动化 / 模板骨架 / 提示词与路由机制 / 上下文与知识管理 / 其他
     - 对 tack 的价值（对应哪个环节、弥补什么短板）
   - 同时产出**排除清单**：与 tack 现有能力重复、技术栈不适用、或违背 tack 核心约定（如让用户直接操作 `$root` git、破坏性命令、强制逐环节确认等）的内容，逐条写明排除理由
   - 边界: 只做事实提炼，不把素材中的营销描述、版本声明当作可借鉴设计

3. **对照 tack 现状建立落点映射**
   - 动作: 重新读取 `$root/harness/` 下的 cmd/workflow/rule/reference/script/template 实际文件，以及 `$root/AGENTS.md`、`$root/SKILL.md`（不信任上下文中的旧内容），为每个可借鉴点确定落点：
     - 流程编排与状态机 → `harness/workflow/`
     - 可调用的命令能力 → `harness/cmd/<分组>/`
     - 跨命令复用的规则/判据/格式 → `harness/rule/`
     - 篇幅大、按需加载的方法论 → `harness/reference/`（由 cmd/workflow 引用后才加载）
     - 确定性机械步骤（文件生成、校验、状态回写等）→ `harness/script/`（POSIX sh，Windows 经 `run.ps1`；用退出码做硬门禁）
     - 文档骨架 → `harness/template/`
     - 必须常驻的约定 → `$root/AGENTS.md`（仅限「核心约束/沉淀约定」类；永不触碰项目信息 YAML 区块）
     - skill 入口级描述 → `$root/SKILL.md`
   - 每个落点标注处置方式：**新增**（确无对应条目）/ **融合**（并入已有文件的相关段落）/ **优化**（对现有表述的增强改写）；先扫描能融合则融合，不制造重复文件
   - 新增命令/工作流先做重名检查：候选名过 `scan-routes resolve` 不得命中现有命令，命名不带前导连字符、意图明确（禁止模糊命名）

4. **备份并直接落盘（中途不找用户确认）**
   - 备份: 落盘前将 `$root/harness` 复制到 `$root/.tack/backup/study-<timestamp>/`（`.tack/` 已被 gitignore 忽略）；如改动涉及 AGENTS.md/SKILL.md 一并复制原件进备份目录
   - 落盘原则:
     - **以新增、融合、优化为主，不删除既有内容**：不删除、不弱化任何现有命令、规则、脚本、模板与约定
     - 最小化修改：只动与借鉴点相关的段落，不重写无关内容；融合时保留原文有效表述
     - 借鉴内容与既有设计确实冲突时，**保留既有内容**，以「增补备选/补充说明」方式处理；若认为应以新设计替换，不在此步执行，记入第 6 步的「待裁决替换建议」由用户定夺
     - 新增 cmd/workflow 必须带完整 front matter（command 或 workflow、short、triggers、summary），并与模板 `harness/template/cmd.md`、`workflow.md` 结构一致
     - 大段方法论一律进 reference 并在 cmd 中一行引用，不把规则细节堆进 cmd（参照 evolution 的瘦身标准）
     - 发现机械性固定步骤同步沉淀为脚本：脚本风格与 `harness/script/` 现有脚本一致，头部写明输入参数、退出码语义，并附最小用例；AI 只保留语义判断职责
   - 动作: 按映射逐个落盘，同步记录「文件 | 处置方式（新增/融合/优化）| 变更摘要 | 对应借鉴点编号」

5. **自验证（失败立即修复，不留给用户）**
   - 执行 `sh $root/harness/script/scan-routes.sh list $root/harness`，确认全部既有命令与新增命令正常注册、无重名报错；新增触发词用 `scan-routes resolve` 抽查唯一命中（退出码 0）
   - 新增/修改的脚本执行 `sh -n` 语法校验；新脚本实跑一次最小用例，确认退出码语义正确
   - 检查所有新增的文件引用（reference/rule/script/template 路径）真实存在；front matter 字段完整
   - 确认既有命令文件未被删除、既有流程环节未缺失（与第 3 步读到的现状比对）

6. **统一预览（全程唯一确认点）**
   - 动作: 输出一份完整变更报告：
     - 学习来源（来源标识、素材形态：skill/仓库）
     - 可借鉴点清单（含类型与价值）
     - 排除清单（含排除理由）
     - 变更文件清单：文件路径 | 新增/融合/优化 | 变更摘要 | 对应借鉴点
     - **「待裁决替换建议」单列高亮**：凡涉及删除或替换既有内容的项，默认未执行，在此请用户选择
     - 自验证结果（路由表、脚本语法与最小用例、引用完整性）
     - 备份位置（供回退）
   - 边界: 分析与落盘阶段不得为候选取舍、命名、落点等问题中途询问用户；只有素材无法定位等硬缺口才停止
   - 用户反馈: 要求调整/回退部分文件时，按反馈修改，重新执行第 5 步自验证后再次给出预览，直到用户明确确认；用户明确否决的文件从备份恢复

7. **确认后提交（无需用户操作 git）**
   - 动作: 用户确认全部变更后，执行 `sh $root/harness/script/space.sh commit $root "chore(tack): study from <来源标识>"` 自动提交到 tack 空间根仓库；无变更自动跳过
   - 用户整体否决: 从 `.tack/backup/study-<timestamp>/` 恢复全部文件，不提交，并保留分析结论供用户参考
   - 收尾: 删除本次临时克隆目录（`$root/.tack/tmp/study-clone-<时间戳>`，仅删本次创建的目录）；`.tack/backup/study-<timestamp>/` 是回滚备份、保留不删；本地素材目录不删不动
   - 边界: 遵守 `harness/rule/git-boundary.md`

8. **自动执行一次 evolution**
   - 动作: 提交成功后，立即读取并严格按 `harness/cmd/base/evolution.md` 执行一次完整审查（枚举全部指令、识别 rule/reference/script/guidance 候选、输出候选清单）
   - 边界: study 不代行 evolution 的确认权——evolution 候选清单仍由用户挑选确认后才落盘；该次 evolution 的提交沿用其自身的框架自动提交约定

## 框架自动提交（无需用户操作）

- study 本体的 harness 改动：第 7 步用户统一确认后由 `space.sh commit` 提交，信息含学习来源标识
- 随后的 evolution 提交：按 evolution 命令自身的约定执行
- 边界: 遵守 `harness/rule/git-boundary.md`

## 后置完成检验

- [ ] 素材来源可追溯（URL/绝对路径/skill 名称），全部分析基于实际读到的文件内容
- [ ] 可借鉴点清单与排除清单完整，排除项均有理由
- [ ] 每个落盘变更都能对应到具体借鉴点；落点经过与现有文件的融合检查，无重复造文件
- [ ] 既有命令、规则、脚本、模板与约定无一被删除；替换性内容仅作为「待裁决建议」列出并经用户选择
- [ ] scan-routes 路由表完整、无重名；新增触发词唯一命中；脚本通过 `sh -n` 与最小用例；引用路径全部存在
- [ ] 变更仅在统一预览并经用户确认后提交；提交信息含来源标识；`.tack/tmp/` 下本次临时克隆目录已清理（回滚备份 `backup/study-<timestamp>/` 保留）
- [ ] 提交后已自动执行一次 evolution，其候选已经用户确认或按 evolution 规则保留 raw

## 下一步建议

- 根据 evolution 审查结果继续把新引入内容沉淀为 rule/reference/script
- 用 `help` 复查路由表，试用新增或优化后的命令
