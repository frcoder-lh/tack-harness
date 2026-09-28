# Windows 环境执行纪律

> 适用：AI 在 Windows（PowerShell 宿主）执行 shell 命令、创建文件时遵守。macOS / Linux 不适用。
> 引用方式：AGENTS.md「脚本调用约定」指向本文件；涉及 shell 执行或文件创建的命令可按需引用。

## Shell 调用

- **多行 bash 脚本禁止内联在 PowerShell 命令行**（会被逐行解析、引号截断）：先写入临时 `.sh` 文件，再 `bash -l <file>` 执行
- **PowerShell 不支持 heredoc**（`<<EOF`）：多行字符串用 here-string `@"..."@`
- **PowerShell 不支持 `&&` / `||`**：用 `;` 分隔，或写入脚本文件
- **`bash` / `sed` 等 GNU 工具不在 PowerShell PATH**：经 `& "C:\Program Files\Git\bin\bash.exe" -c "<cmd>"` 调用；文件读写改优先用内置 Read/Write/Edit 工具
- `harness/script/` 脚本一律走 `run.ps1` 启动器（见 AGENTS.md「脚本调用约定」）

## 文件换行约定

- `.gitattributes` 声明 `*.sh text eol=lf`、`*.md text eol=lf`：新建/覆写这两类文件**必须是 LF 换行**
- Windows 下编辑器与部分写入方式会引入 CRLF，导致 git 整文件脏 diff、sh 脚本执行异常
- 落地后用 `file <路径>` 或 git diff 抽查；发现 CRLF 时用 bash 执行 `sed -i 's/\r$//' <file>` 修复
- 新建 `.sh` 后必须 `sh -n` 语法检查并实跑最小用例

来源: 用户沉淀 2026-09-28（evolution 执行实战：heredoc/`&&`/多行内联/sed 缺失/CRLF 五类异常）
