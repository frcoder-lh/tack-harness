# Hook 可选加速层

> 由 `AGENTS.md` 目录概览的 Hook 行引用后按需加载，适用于 TRAE / Claude Code。
> `harness/script/hook/` 提供三个 IDE Hook，**仅做确定性事实搬运，不承载语义判断**，`AGENTS.md` 与 `scan-routes.sh` 始终是唯一事实源。

## 启用与降级

- 需在 IDE「设置 > Hooks」中手动启用后才生效；不启用或删除整个目录，框架行为不变。
- 降级：删除 `$root/.trae/hooks.json` 与 `$root/.claude/settings.json` 即完全回退到「AI 主动调用 `scan-routes.sh`」的路径。

## 事件与加速内容

| 事件 | 加速内容 | 对会话的影响 |
|------|----------|--------------|
| SessionStart | 只注入空间位置（`$root`、当前 cwd 所属工作区），不预载路由表 | 省去会话启动时扫描；收到请求后再按需加载 |
| UserPromptSubmit | 以当次 cwd 实时解析空间根与工作区；对输入做 `scan-routes resolve`，唯一命中时注入路由元信息、参数原文、状态快照与指令正文，多命中列候选，无命中注入 `scan-routes index` 紧凑索引 | 省去路由解析往返与重复的空间/工作区扫描；上下文已有正文或索引时直接复用 |
| PreToolUse | 观察模式：命令执行类工具（RunCommand/Bash）调用与 Git 双层边界、`--force`/`--no-verify` 等规则命中情况经统一日志记录；`TACK_HOOK_ENFORCE=1` 才输出 deny（**当前预留，默认不拦截**） | 默认零输出、零拦截 |

## 统一日志

- 设置环境变量 `TACK_HOOK_LOG=1` 后，三个 Hook **每次被调用**都把一条完整记录追加到 `$root/.tack/log/hook.log`——时间、事件名、pid、`$root`/`$work`、cwd、环境变量、输入 payload 全文、注入/拦截输出全文、退出码与耗时（并发调用按整块串行写入、互不交错）；非 tack 空间回退系统临时目录。
- 默认关闭；关闭时 Hook 的 stdout 与不启用日志时逐字节一致。`.tack/` 不入库、日志可随时清理。

## 路径解析

- Hook 不向会话环境写入任何路径变量（无 `TACK_ROOT`/`TACK_WORK`）：三个 Hook 一律以当次调用 payload 的 cwd 实时解析空间根与工作区，多个项目窗口、同一空间多个工作区并行互不串扰；AI 拼命令时直接使用 Hook 注入文本中的绝对路径，不要假定存在路径类环境变量（仅 `TACK_HOOK_LOG`/`TACK_HOOK_ENFORCE` 两个模式开关走环境变量）。
