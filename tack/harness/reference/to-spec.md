# To Spec — 综合生成需求规划

当资料已经充分时，把当前对话上下文、wiki 与代码库理解**综合**为需求规划文档（对应 `/tack spec`，产出 `space/<workspace>/spec.md`）。**不要访谈用户**；只需组织你已知的内容。需要通过访谈补齐信息时改用 `grill-with-docs.md` / `grilling.md`。

## 过程

1. 如果尚未探索代码库，先去探索（可委派 `harness/agents/code-explorer.md`）。使用项目的领域术语，参考 `wiki/business-understanding.md`（如已物化）。
2. 从用户视角梳理**问题与目标**，划清系统与模块边界、关键交互与验收标准；优先复用现有边界，新增边界越少越好。
3. 按 `harness/template/spec.md` 的章节编写，保存到 `space/<workspace>/spec.md`。格式以模板为准，本文件不另立模板。

## 综合纪律

- 对原始需求只做格式整理与梳理，不篡改原始含义、不替用户做业务决策
- 不写数据结构、编码步骤等实现细节（属于 plan.md）
- 综合中发现信息缺口：列出「待澄清」问题交还 spec 命令的确认关口，不靠猜测补全
