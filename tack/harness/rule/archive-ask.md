# ask 记录归档规则

> 被 `close` 命令引用：`ask` 的分析与问答产物留在 `$work/doc/analysis/`，关闭工作区时按本规则转化为可长期复用的业务与代码理解。只归档结论，不归档分析过程。

## 处理对象

- `$work/doc/analysis/` 下的全部 `ask` 产物：按主题命名，文件名不限后缀；按目录扫描 `.md` 并按头部「主题」匹配，不假定 `<repo>-analysis.md` 等固定文件名
- `$work/story/*/analysis.md` 中的需求分析与讨论结论（只提炼其中可跨工作区复用的业务/代码结论）
- 只处理有长期价值、且代码不应作为唯一载体的结论；无符合项时跳过，不生成空文件

## 归档方式：转化，不原样复制

- 不整段搬运原文，改写成通俗易懂的业务语言
- 简练准确、分条陈述，一条一个结论
- 合并同义结论，删除重复与过程性描述
- 结论必须能被工作区原始产物或代码证实；标记「待确认」、推测与未验证内容不归档

## 分流落点

| 内容 | 落点 |
|------|------|
| 业务名词/术语的解释（是什么、边界、别名/旧称） | `$root/wiki/<project>/biz/glossary.md`「核心概念与术语」表 |
| 业务背景、领域职责与不变量 | `$root/wiki/<project>/biz/background.md`、`biz/domains.md` 对应小节 |
| 代码名词/标识的解释与导航（术语 → 检索关键词/代码入口、接口 → 业务场景） | `$root/wiki/<project>/code/anchors.md`、`code/interfaces.md` 的映射表 |
| 稳定代码外事实（服务职责、环境/配置/平台入口等） | `$root/wiki/<project>/config/` 对应文件（`services.md` / `env.md` / `accounts.md` / `settings.md`） |
| 项目级技术决策与工程约定 | `$root/wiki/<project>/rule/decisions.md`、`rule/conventions.md` |
| 需求特定的「为什么这样做 / 是否设计如此」 | 该工作区的 `$root/wiki/<project>/history/<workspace>/summary.md`；本工作区已按 `harness/rule/archive-requirement.md` 归档时就地融合 |

- 业务名词解释进 `biz/glossary.md`，代码名词解释进 `code/anchors.md`，两类不混放
- 已有同义条目就地融合更新，不重复追加
- 写入、分类与索引更新统一遵守 `harness/rule/wiki-write.md`；新增文件后同步更新对应分类索引与项目总索引

## 不归档的内容

- 可行性分析、寻找 bug 的推理与排查过程
- 失败假设、临时验证脚本、执行日志、测试结果
- 代码实现细节、调用链、模块内部行为、文件/行号清单——代码是唯一真源
- 仅本次有效、随分支变化的临期结论
- 未经证实的线索与「待确认」内容
- 凭据、个人账号等敏感信息

## 审阅与来源

- 展示拟归档条目（内容 | 落点 | 来源），经用户确认后写入
- 来源标注：`space/<workspace>/doc/analysis/<文件>#<章节>`（需求分析来源为 `space/<workspace>/story/<story>/analysis.md#<章节>`），代码与文件引用用 `仓库/路径#L12-L15`，必要时附 `commit <short-hash>`
- 融合去重、矛盾演变与禁写凭据要求同 `harness/rule/wiki-write.md`
