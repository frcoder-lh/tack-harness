# Shell 编码规范

> 语言特定规则文件：`code` / `testcode` 任务涉及 shell 脚本（`.sh`）时，与 `coding-standards.md` 一并加载；`code-reviewer` 的「约定与安全」视角按同一标准评审。
>
> 以下为随 harness 分发的**默认基线**；项目可经 `record` 收紧或补充（落点规则见 `record-rule.md`）。

## 变量引用

- **默认写 `"${VAR}"`**：命名变量一律「双引号 + 花括号」——花括号界定变量名边界（拼接后缀时必需，如 `"${name}_tmp"`），双引号防止词分割与路径通配
- **特殊参数保留惯用简写**：`"$0"`、`"$1"`…`"$9"`、`"$@"`、`"$*"`、`"$#"`、`"$?"`、`"$$"`、`"$!"`；两位以上位置参数仍须花括号：`"${10}"`
- 参数展开 `${var:-default}`、算术展开 `$((i + 1))`、命令替换 `"$(cmd)"` 按各自语法书写，不套用变量引用约定
- 刻意利用分词或 glob 而不加引号（如 `for item in $items`、命令位置的 `$PRIV`）仅限局部，且意图显而易见；除此以外默认加引号

## 三平台兼容基线（Linux / macOS / Windows）

所有 `.sh` 须在 Linux（GNU 工具）、macOS（BSD 工具）、Windows（Git for Windows，经 `run.ps1` 启动）三平台运行，以下为默认基线：

- **解释器与语法**：shebang 固定 `#!/bin/sh`，只用 POSIX sh——不用 bash 数组、`[[ ]]`、进程替换 `<(...)`、here-string `<<<`、`set -o pipefail`、`local`/`declare`/`typeset`、`$RANDOM`、`source`（引入文件用 `.`）
- **外部命令只用三平台共有选项**：禁用 GNU 专有用法，常见替换——`grep -P`/`-oP` → `-E` 或 awk；`find -printf` → `-print` + awk；`readlink -f` → `cd <目录> && pwd -P`；`stat -c`/`--format` → `ls -l` + awk；`date -d` → `date '+格式'` 或 `date +%s`；`mktemp -p` → `mktemp "${TMPDIR:-/tmp}/tack-XXXXXX"`；`xargs -r` → 先判断输入非空；`sort -V` → awk 版本比较；`echo -e` → `printf`；`seq` → awk 循环
- **`mktemp` 必须带模板**：BSD（macOS）不接受无模板调用，`mktemp` 与 `mktemp -d` 一律带模板，如 `"${TMPDIR:-/tmp}/tack-XXXXXX"`
- **awk 只用 POSIX 特性**：不用 `gensub`、`asort`、`ARGIND` 等 gawk 扩展；`getline`、`split`、`sub`/`gsub`、`sprintf` 按 POSIX 写法
- **路径**：正斜杠；不硬编码平台绝对路径或工具安装位置；Windows 盘符路径由 `run.ps1` 归一化
- **目录链接**：Windows 用 junction（`cmd //c mklink //J`），不依赖 Git Bash 的 `ln -s`（未开启 winsymlinks 会退化为复制）；其他平台用 `ln -s`
- **换行**：`.sh` 与文本文件一律 LF；`.bat`/`.cmd` 用 CRLF
- **验证**：`sh -n` 只检查 shell 语法，不校验外部命令选项与 sed 表达式；每个外部命令按本清单静态核对，当前平台实跑最小用例，无法实跑的平台在结果中注明；可移植性机检执行 `sh <harness-dir>/script/lint-shell-portability.sh <harness-dir>`（与 `lint-harness.sh` 集成）

## sed 用法（三平台兼容细则）

- **不依赖 `sed -i`**：GNU 与 BSD 的 `-i` 语义不同；就地修改一律「写临时文件 + `mv`」
- **块内命令一律以 `;` 分隔**：`/pat/{ cmd1; cmd2; }` 中每条命令（含块内最后一条）后都必须写 `;`，不依赖 GNU sed 对 `cmd }` 的宽松解析——BSD sed 会报语法错误
- **只用 POSIX 正则与选项**：基本正则下不用 GNU 扩展 `\+`、`\?`、`\b`、`\w`；需要扩展正则时用 `-E`（GNU/BSD/Git for Windows 均支持），不用 GNU 专有的 `-r`、`--posix`、`--debug`、`-z`
- 结构化文本替换必须限定地址范围，并在执行前校验目标字段存在
