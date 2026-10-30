# 部署与泳道登记规则

> 被 `testcode`（部署验证登记）、`merge`（上线计划登记）、`release-check`（上线准备提示）、`close`（回收检查）按需加载。
> 动态事实落 `$work/status.yaml` 的 `deploy` 区块（字段结构见 `harness/template/work-status.yaml`），写入一律经 `work-status.sh`，不手改 YAML。

## 何时登记

- **testcode 部署验证**：外部平台完成部署后立即登记——`deploy upsert <repo> <env> <lane> <route> <build> <url> <status>`；本命令只登记事实，不代为部署。
- **merge 上线计划**：合并不等于上线；需要在 PPE/PROD 等环境继续验证或上线时，登记各环境上线计划与泳道/版本事实。
- **release-check**：生成上线检查清单时，有上线计划的提示用户登记同一区块。
- **close 回收检查**：关闭前用 `deploy list` 检查未回收泳道。

## 状态生命周期

- `deploying`（已部署待验证）→ `deployed`（已部署）→ `verified`（已验证）→ `recycled`（已回收），状态变化用 `deploy mark <repo> <env> <lane> <status>`。
- `deploying` / `deployed` 的泳道在 `close` 时必须提醒回收；未回收不阻塞关闭，但处理方式须经用户确认。
- BOE 等验证泳道不再使用时置 `recycled`。

## 字段与边界

- 复合键 `(repo, env, lane)`：已存在则覆盖，不存在则追加；`deploy list` 输出 `repo / env / lane / route / build / url / status`。
- `lane` 建议从 `work_id` 派生（如 `tack-<work_id>`），便于与部署平台对账；泳道是「需求分支代码部署到共享环境的隔离实例 + 流量路由（header/cookie/uid）」，不新增代码分支。
- 只登记事实与链接，不臆造环境信息。
- 环境拓扑、部署方式、平台入口、泳道申请流程等静态事实记在 `$root/wiki/<project>/config/env.md`，缺失时提示用户补充并经 `record` 沉淀（读取按 `harness/rule/wiki-read.md`）。

来源: 用户沉淀 2026-10-23（evolution：deploy 登记规则在 testcode / merge / close / release-check 四处重复，收敛为本规则）
