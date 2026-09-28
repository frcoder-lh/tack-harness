# Handoff — 会话交接

一项工作需要跨会话继续时（如冲突处理当天未完成），把当前现场压缩成交接文档，让下一个会话的 agent 能快速接手。

## 过程

1. 编写交接文档，保存到当前工作区 `$work/handoff.md`（随工作区文档留存，不写操作系统临时目录）
2. 以 `$work/status.yaml` 为状态主线：写明 `current.stage` / `current.task` / `current.next`、已完成与进行中的任务、blocked 原因与等待项
3. 包含「建议下一步」：命名下一个会话应执行的 tack 命令（如继续 `solve`、回 `fix`）与一句话理由
4. 不复制其他工件已捕获的内容（input/spec/plan/tech-design、提交、diff）——用相对 `$root` 的路径引用它们
5. 清理敏感信息（API 密钥、密码、个人身份信息）；凭据只记存放位置，空间提交另有 `scan-secrets.sh` 门禁

用户传递了参数时，将其作为下一个会话的焦点描述，并据此组织文档重点。
