# Windows 环境执行纪律

> 适用：AI 在 Windows（PowerShell 宿主）执行 shell 命令、创建文件时遵守。macOS / Linux 不适用。
> 引用方式：AGENTS.md「脚本调用约定」指向本文件；涉及 shell 执行或文件创建的命令可按需引用。

## Shell 调用

- **bash 脚本禁止内联在 PowerShell 命令行**：多行脚本会被逐行解析、引号截断；**单行命令只要含 `$`、双引号、正则等特殊字符，也会被 PowerShell 先解析破坏**（实战：sed 正则 `\(.*\)` 被截断后当成命令名执行）。一律先写入临时 `.sh` 文件，再 `bash -l <file>` 执行
- **PowerShell 不支持 heredoc**（`<<EOF`）：多行字符串用 here-string `@"..."@`
- **PowerShell 不支持 `&&` / `||`**：用 `;` 分隔，或写入脚本文件
- **`bash` / `sed` 等 GNU 工具不在 PowerShell PATH**：经 `& "C:\Program Files\Git\bin\bash.exe" -c "<cmd>"` 调用；文件读写改优先用内置 Read/Write/Edit 工具
- **PATH 里的 `bash` 可能是 WSL 的（`C:\Windows\System32\bash.exe`）**：它不能解析 Windows 盘符路径（如 `D:/...`），跑 `sh -n` / 执行脚本会报 "No such file or directory"。须用 Git for Windows 的 `sh.exe`（`C:\Program Files\Git\bin\sh.exe`，可从 `(Get-Command git).Source` 同目录 `bin\sh.exe` 推断）；跑 `harness/script/` 脚本走 `run.ps1` 即可（已内置正确 bash 定位）
- `harness/script/` 脚本一律走 `run.ps1` 启动器（见 AGENTS.md「脚本调用约定」）

## 输出噪音识别

PowerShell 会把外部程序的 stderr 包装成 Error 记录，以下输出**不是失败信号**，判断成败以退出码与预期产物（如 git 的 ref 更新行）为准，不要据此类噪音中止或误报：

- PowerShell profile 的 `PSSecurityException` / `UnauthorizedAccess`（执行策略禁止加载 profile，不影响完整路径调用 bash）
- Git 的 `LF will be replaced by CRLF the next time Git touches it` 警告
- git push/pull 成功时 stderr 中的远端 banner、trace 信息（PowerShell 5 下显示为 `NativeCommandError`）

## 文件换行约定

- `.gitattributes` 声明 `*.sh text eol=lf`、`*.md text eol=lf`：新建/覆写这两类文件**必须是 LF 换行**
- Windows 下编辑器与部分写入方式会引入 CRLF，导致 git 整文件脏 diff、sh 脚本执行异常
- 落地后用 `file <路径>` 或 git diff 抽查；发现 CRLF 时用 bash 执行 `sed -i 's/\r$//' <file>` 修复
- 新建 `.sh` 后必须 `sh -n` 语法检查并实跑最小用例

来源: 用户沉淀 2026-09-28（evolution 执行实战：heredoc/`&&`/多行内联/sed 缺失/CRLF 五类异常）
补充: 2026-09-28（release.sh 优化实战：单行含 `$`/正则内联同样被截断；profile 异常与 CRLF 警告等 stderr 噪音不得误判为失败）
补充: 2026-09-29（evolution sh 跨平台审查实战：PATH 里的 `bash` 命中 WSL 无法解析 Windows 盘符路径，跑 `sh -n` 报 "No such file or directory"；改用 Git for Windows `sh.exe`）
