# <指令名>

> 本文件是一条 run 指令的执行说明，由 `run` 命令按 `run/run.md` 索引识别后加载。
> 本目录存放该指令的全部脚本与数据；密钥、token、账号等敏感配置一律放在本目录的 `local/`（已被 .gitignore 忽略，不入版本库）。

## 执行前准备

1. 将本指令需要的密钥、token、账号等敏感信息写入 `local/` 下的对应文件（如 `local/credentials.sh`、`local/.env`）
2. 确认脚本中读取凭据的路径指向本目录的 `local/`，不得硬编码

## 脚本清单与执行顺序

| 序号 | 脚本 | 用途 | 运行命令 | 依赖 |
|------|------|------|----------|------|
| 1    |      |      |          |      |

## 机器可读清单（run-plan）

> `run-plan.sh check <指令目录>` 只读校验本区块，不执行脚本。
> 列以 Tab 分隔：seq / script / command / deps / requires。
> seq 为正整数且按文件顺序严格递增；deps 为前置步骤 seq（逗号分隔，必须小于当前 seq）；
> requires 为相对本目录的必需文件（逗号分隔，通常为 local/ 下凭据文件）。
> script 与 requires 一律使用相对本目录的路径；可选参数不写入清单。

<!-- run-plan:start -->
seq	script	command	deps	requires
<!-- run-plan:end -->

## 执行约定

- 脚本退出码非 0 时停止后续步骤并报告
- 需要人工介入的步骤在脚本中标注并等待确认
- 执行结果（输出、日志）写入 `local/` 或控制台，不回写本文件
