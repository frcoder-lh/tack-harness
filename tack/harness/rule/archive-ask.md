# ask 记录归档规则

> 被 `close` 命令引用：`ask` 的分析与问答产物留在 `$work/wiki/`，关闭工作区时按本规则转化为可长期复用的业务与代码理解。只归档结论，不归档分析过程。

## 处理对象

- `$work/wiki/` 下的 `ask` 产物：`<repo>-analysis.md`、主题问答文档等
- 只处理有长期价值、且代码不应作为唯一载体的结论；无符合项时跳过，不生成空文件

## 归档方式：转化，不原样复制

- 不整段搬运原文，改写成通俗易懂的业务语言
- 简练准确、分条陈述，一条一个结论
- 合并同义结论，删除重复与过程性描述
- 结论必须能被工作区原始产物或代码证实；标记「待确认」、推测与未验证内容不归档

## 分流落点

| 内容 | 落点 |
|------|------|
| 业务名词/术语的解释（是什么、边界、别名/旧称） | `$root/wiki/<project>/business-understanding.md`「核心概念与术语」表 |
| 代码名词/标识的解释与导航（术语 → 检索关键词/代码入口、接口 → 业务场景） | `$root/wiki/<project>/code-understanding.md` 的两张映射表 |
| 稳定代码外事实（服务职责、环境/配置/平台入口等） | `$root/wiki/<project>/manifest.md` 对应小节 |
| 项目级技术决策与工程约定 | `$root/wiki/<project>/decisions.md` |
| 需求特定的「为什么这样做 / 是否设计如此」 | 该工作区的 `$root/wiki/<project>/history/<workspace>/summary.md`；本工作区已按 `harness/rule/archive-requirement.md` 归档时就地融合 |
| 其他跨工作区可复用的业务背景 | `$root/wiki/<project>/business-understanding.md` 对应小节 |

- 业务名词解释进 `business-understanding.md`，代码名词解释进 `code-understanding.md`，两类不混放
- 已有同义条目就地融合更新，不重复追加

## 不归档的内容

- 可行性分析、寻找 bug 的推理与排查过程
- 失败假设、临时验证脚本、执行日志、测试结果
- 代码实现细节、调用链、模块内部行为、文件/行号清单——代码是唯一真源
- 仅本次有效、随分支变化的临期结论
- 未经证实的线索与「待确认」内容
- 凭据、个人账号等敏感信息

## 审阅与来源

- 展示拟归档条目（内容 | 落点 | 来源），经用户确认后写入
- 来源标注：`space/<workspace>/wiki/<文件>#<章节>`，必要时附 `commit <short-hash>`
- 融合去重、矛盾演变与禁写凭据要求同 `harness/rule/record-wiki.md`
