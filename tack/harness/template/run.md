# run 执行说明

> 本文件说明执行 `run` 命令后如何运行和启动 `run/` 目录下的脚本。
> `run` 命令会加载本文件，按其中列出的脚本顺序执行。
>
> 目录约定：
> - `run/`：测试/执行脚本与本说明文件
> - `run/local/`：**敏感数据目录（已被 .gitignore 忽略，不入版本库）**——用户填入的密钥、token、账号、环境变量等一律落在此处；AI 生成的敏感数据同样写这里；其他脚本需要密钥时从这里读取

## 执行前准备

1. 将密钥、token、账号等敏感信息写入 `run/local/` 下的对应文件（如 `local/credentials.sh`、`local/.env`）
2. 确认脚本中读取凭据的路径指向 `run/local/`，不得硬编码

## 脚本清单与执行顺序

| 序号 | 脚本 | 用途 | 运行命令 | 依赖 |
|------|------|------|----------|------|
| 1    |      |      |          |      |

## 机器可读清单（run-plan）

> `run-plan.sh check <work/run>` 只读校验本区块，不执行脚本。
> 列以 Tab 分隔：seq / script / command / deps / requires。
> seq 为正整数且按文件顺序严格递增；deps 为前置步骤 seq（逗号分隔，必须小于当前 seq）；
> requires 为相对 run/ 的必需文件（逗号分隔，通常为 local/ 下凭据文件）。
> script 与 requires 一律使用相对 run/ 的路径；可选参数不写入清单。

<!-- run-plan:start -->
seq	script	command	deps	requires
<!-- run-plan:end -->

## 执行约定

- 脚本退出码非 0 时停止后续步骤并报告
- 需要人工介入的步骤在脚本中标注并等待确认
- 执行结果（输出、日志）写入 `run/local/` 或控制台，不回写本文件
