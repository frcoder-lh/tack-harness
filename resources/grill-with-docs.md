# Grill with Docs — 带文档的深入访谈

一个结合**深入访谈**和**领域建模**的会话。在访谈过程中同时创建文档（ADR 和术语表）。

## 过程

本资源组合了两个核心能力：

### 第一部分：深入访谈（参考 grilling.md）

按照 `resources/grilling.md` 中的流程进行持续深入的访谈，直达成共识。

### 第二部分：领域建模（参考 domain-modeling.md）

在访谈过程中，按照 `resources/domain-modeling.md` 的流程：

- 当术语被澄清时，即时更新 `wiki/business-understanding.md`
- 当架构决策被确认时，即时记录技术决策到 `work/<branch>/harness/tech-design.md`
- 挑战模糊术语，提出精确的 canonical 术语
- 用具体场景压力测试领域关系
- 与代码库交叉验证陈述

## 约束

本阶段仅记录和澄清需求，不修改任何代码文件。

## 输出

会话结束时，你应该有：
- 澄清的需求描述
- 更新的业务术语表
- 已确认的技术决策记录
- 设计树的每个分支都已访问，没有默默假设的内容