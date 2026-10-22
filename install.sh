#!/bin/sh
# install.sh — 将 tack skill 安装到常见 AI Agent
# Usage:
#   sh install.sh                     自动检测已安装的 agent，交互选择
#   sh install.sh --agent <name>      安装到预设 agent（多个用逗号分隔）
#   sh install.sh --target <path>     安装到自定义目录
#   sh install.sh --list              列出支持的 agent
#   sh install.sh --dry-run --agent trae  预览安装
#   curl -fsSL <raw>/install.sh | sh -s [--agent <name>]  免克隆一键安装（自动下载源码）
#
# 交互式安装时，若目标已存在 tack，会询问覆盖方式
# （全部覆盖 / 全部跳过 / 逐个选择）；非交互环境请用 --force 控制。
#
# 默认安装最新 GitHub Release：下载 tar.gz 并强制核验 SHA-256；
# --branch <name> 安装指定分支源码（开发版，仅锁定分支、不做摘要校验）。
# 支持的 agent 预设与分发包清单由 tack/harness/script/common.sh 统一维护，
# 安装、升级、版本检查三条链路共用同一份事实源。

set -e

UPDATE_URL="https://github.com/frcoder-lh/tack-harness"

# —— 解析参数 ——
AGENT=""
TARGET=""
BRANCH_ARG=""
DRY_RUN=0
DO_LIST=0
FORCE=0
# 逐个选择覆盖时，记录需要强制覆盖的目标路径（每行一个）
FORCE_TARGETS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --agent)   AGENT="$2"; shift 2 ;;
        --target)  TARGET="$2"; shift 2 ;;
        --branch)  BRANCH_ARG="$2"; shift 2 ;;
        --list)    DO_LIST=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force)   FORCE=1; shift ;;
        --help|-h)
            echo "Usage: sh install.sh [--agent <name> | --target <path>] [--branch <name>] [--dry-run] [--force] [--list]"
            echo ""
            echo "  （无参数）       自动检测已安装的 agent，交互选择安装目标"
            echo "  --agent <name>   安装到预设 agent（多个用逗号分隔，如 trae,cursor）"
            echo "  --target <path>  安装到自定义目录"
            echo "  --branch <name>  安装指定分支源码（开发版，不做摘要校验；默认安装最新 Release）"
            echo "  --list           列出所有支持的 agent"
            echo "  --dry-run        预览，不实际复制"
            echo "  --force          覆盖已存在的文件（交互模式下不指定则会询问）"
            echo ""
            echo "示例:"
            echo "  sh install.sh"
            echo "  sh install.sh --agent trae"
            echo "  sh install.sh --agent cursor,trae --dry-run"
            echo "  sh install.sh --target ~/my-custom-agent/skills/tack"
            echo "  sh install.sh --branch master"
            exit 0 ;;
        *) echo "未知参数: $1 (使用 --help 查看帮助)"; exit 1 ;;
    esac
done

# —— 定位源码并加载 common.sh ——
# 本地仓库直接加载；curl | sh 时先取回 common.sh，再按版本下载完整源码
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_SRC=""

cleanup_tmp() {
    if [ -n "${TMP_SRC}" ] && [ -d "${TMP_SRC}" ]; then
        rm -rf "${TMP_SRC}"
    fi
}
trap cleanup_tmp EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 引导下载：仅在加载 common.sh 之前使用一次；此后一律复用 common.sh 的下载与校验能力
bootstrap_fetch() {
    _bootstrap_url="$1"
    _bootstrap_out="$2"
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL "${_bootstrap_url}" -o "${_bootstrap_out}" 2>/dev/null; then
            return 0
        fi
        # Windows Git Bash 的 schannel 后端在受限网络下需关闭证书吊销检查
        case "$(uname -s 2>/dev/null)" in
            MINGW*|MSYS*|CYGWIN*)
                if curl -fsSL --ssl-no-revoke "${_bootstrap_url}" -o "${_bootstrap_out}" 2>/dev/null; then
                    return 0
                fi
                ;;
        esac
    fi
    if command -v wget >/dev/null 2>&1; then
        if wget -q -O "${_bootstrap_out}" "${_bootstrap_url}" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

LOCAL_SOURCE=0
if [ -f "${SCRIPT_DIR}/SKILL.md" ] && [ -f "${SCRIPT_DIR}/tack/harness/script/common.sh" ]; then
    LOCAL_SOURCE=1
fi

if [ "${LOCAL_SOURCE}" -eq 1 ]; then
    . "${SCRIPT_DIR}/tack/harness/script/common.sh"
else
    # 开发版按所选分支取 common.sh；默认取 master（一键安装脚本自身即来自 master）
    COMMON_REF="${BRANCH_ARG:-master}"
    TMP_SRC="$(mktemp -d "${TMPDIR:-/tmp}/tack-install.XXXXXX")"
    COMMON_FILE="${TMP_SRC}/common.sh"
    echo "==> 正在获取安装器公共能力（${COMMON_REF}）..."
    if ! bootstrap_fetch "${UPDATE_URL}/raw/${COMMON_REF}/tack/harness/script/common.sh" "${COMMON_FILE}"; then
        echo "错误: 无法获取 tack/harness/script/common.sh（需要可用的 curl 或 wget）"
        exit 1
    fi
    . "${COMMON_FILE}"
fi

SKILL_FILES="${TACK_SKILL_FILES}"
AGENTS="$(tack_agent_presets)"

# —— 列出支持的 agent ——
if [ "${DO_LIST}" -eq 1 ]; then
    echo "支持的 agent 预设："
    echo ""
    printf "%-12s %-45s %s\n" "名称" "检测目录" "安装路径"
    printf "%-12s %-45s %s\n" "----" "--------" "--------"
    set -f
    OLD_IFS="${IFS}"
    IFS='
'
    for line in $AGENTS; do
        [ -z "${line}" ] && continue
        name=${line%%|*}
        rest=${line#*|}
        detect=${rest%%|*}
        path=${rest#*|}
        printf "%-12s %-45s %s\n" "${name}" "${detect}" "${path}"
    done
    IFS="${OLD_IFS}"
    set +f
    echo ""
    echo "也可使用 --target <path> 指定任意目录"
    exit 0
fi

# —— 管道安装：下载源码 ——
if [ "${LOCAL_SOURCE}" -ne 1 ]; then
    if [ -n "${BRANCH_ARG}" ]; then
        ARCHIVE_URL="${UPDATE_URL}/archive/refs/heads/${BRANCH_ARG}.tar.gz"
        echo "==> 安装开发版分支 ${BRANCH_ARG}（不做摘要校验）"
    else
        if ! RELEASE_TAG="$(tack_latest_release_tag "${UPDATE_URL}")"; then
            echo "错误: 无法解析最新 Release 版本；如需安装开发版，请用 --branch <分支名>"
            exit 1
        fi
        ARCHIVE_URL="${UPDATE_URL}/releases/download/${RELEASE_TAG}/tack-harness-${RELEASE_TAG}.tar.gz"
        CHECKSUM_URL="${ARCHIVE_URL}.sha256"
        echo "==> 安装最新 Release ${RELEASE_TAG}"
    fi

    ARCHIVE="${TMP_SRC}/src.tar.gz"
    echo "==> 正在下载源码: ${ARCHIVE_URL}"
    if ! tack_download_to "${ARCHIVE_URL}" "${ARCHIVE}"; then
        echo "错误: 源码下载失败（需要可用的 curl 或 wget）: ${ARCHIVE_URL}"
        exit 1
    fi

    if [ -z "${BRANCH_ARG}" ]; then
        CHECKSUM_FILE="${TMP_SRC}/src.tar.gz.sha256"
        if ! tack_download_to "${CHECKSUM_URL}" "${CHECKSUM_FILE}"; then
            echo "错误: 校验文件下载失败: ${CHECKSUM_URL}"
            exit 1
        fi
        if ! tack_verify_sha256 "${ARCHIVE}" "${CHECKSUM_FILE}"; then
            echo "错误: 源码 SHA-256 校验失败，安装中止"
            exit 1
        fi
        echo "    SHA-256 校验通过"
    fi

    if ! tar -xzf "${ARCHIVE}" -C "${TMP_SRC}"; then
        echo "错误: 源码压缩包解压失败"
        exit 1
    fi
    # 压缩包解压后为 <repo>-<ref>/ 单层目录
    SRC_SKILL="$(find "${TMP_SRC}" -mindepth 2 -maxdepth 2 -name SKILL.md | head -n 1)"
    if [ -z "${SRC_SKILL}" ]; then
        echo "错误: 下载包中未找到 SKILL.md"
        exit 1
    fi
    SCRIPT_DIR="$(dirname "${SRC_SKILL}")"

    # 以安装版本自带的 common.sh 为准刷新预设与清单（引导阶段仅保证脚本可运行）
    if [ -f "${SCRIPT_DIR}/tack/harness/script/common.sh" ]; then
        . "${SCRIPT_DIR}/tack/harness/script/common.sh"
        SKILL_FILES="${TACK_SKILL_FILES}"
        AGENTS="$(tack_agent_presets)"
    fi
    echo "    源码已下载至临时目录，安装结束后自动清理"
    echo ""
fi

# SELECTIONS 保存最终安装目标，每行格式: "名称|路径"
SELECTIONS=""

add_selection() {
    # $1 = "name|path"，去重后追加
    new_line="$1"
    OLD_IFS="${IFS}"
    IFS='
'
    for existing in $SELECTIONS; do
        if [ "${existing}" = "${new_line}" ]; then
            IFS="${OLD_IFS}"
            return 0
        fi
    done
    IFS="${OLD_IFS}"
    SELECTIONS="${SELECTIONS}
${new_line}"
}

# —— 交互输入来源 ——
# 经管道运行（curl | sh）时 stdin 已被脚本占用，交互输入改读控制终端 /dev/tty
USE_DEV_TTY=0
if [ ! -t 0 ] && (: < /dev/tty) 2>/dev/null; then
    USE_DEV_TTY=1
fi

read_input() {
    if [ "${USE_DEV_TTY}" -eq 1 ]; then
        read "$@" < /dev/tty
    else
        read "$@"
    fi
}

# —— 确定目标路径 ——
if [ -n "${AGENT}" ] && [ -n "${TARGET}" ]; then
    echo "错误: --agent 和 --target 不能同时使用"
    exit 1
fi

if [ -n "${AGENT}" ]; then
    # 支持逗号分隔多个 agent
    OLD_IFS="${IFS}"
    IFS=','
    set -f
    for name in $AGENT; do
        IFS="${OLD_IFS}"
        # 去除首尾空白
        name=$(printf '%s' "${name}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "${name}" ] && continue
        found_line=""
        IFS='
'
        for line in $AGENTS; do
            [ -z "${line}" ] && continue
            cand=${line%%|*}
            if [ "${cand}" = "${name}" ]; then
                found_line="${line}"
                break
            fi
        done
        if [ -z "${found_line}" ]; then
            echo "错误: 未知的 agent '${name}'"
            echo "使用 --list 查看支持的 agent"
            exit 1
        fi
        add_selection "${found_line}"
        IFS=','
    done
    IFS="${OLD_IFS}"
    set +f
elif [ -n "${TARGET}" ]; then
    # 三列格式与预设表保持一致: "名称|检测目录|安装路径"
    add_selection "custom|${TARGET}|${TARGET}"
else
    # —— 无参数：自动检测已安装的 agent，交互选择 ——
    if [ ! -t 0 ] && [ "${USE_DEV_TTY}" -ne 1 ]; then
        echo "错误: 当前为非交互环境，无法选择 agent"
        echo "请使用 --agent <name>（多个用逗号分隔）或 --target <path>"
        echo "使用 --list 查看支持的 agent"
        exit 1
    fi

    echo "==> 正在检测已安装的 Agent..."
    echo ""

    FOUND=""
    IDX=0
    set -f
    OLD_IFS="${IFS}"
    IFS='
'
    for line in $AGENTS; do
        [ -z "${line}" ] && continue
        name=${line%%|*}
        rest=${line#*|}
        detect=${rest%%|*}
        path=${rest#*|}
        if [ -d "${detect}" ]; then
            IDX=$((IDX + 1))
            tag=""
            [ -d "${path}" ] && tag="  [tack 已安装]"
            printf "  [%d] %-10s %s%s\n" "${IDX}" "${name}" "${detect}" "${tag}"
            FOUND="${FOUND}
${line}"
        fi
    done
    IFS="${OLD_IFS}"
    set +f

    if [ "${IDX}" -eq 0 ]; then
        echo "未检测到任何受支持的 Agent（检测目录均不存在）。"
        echo "可使用 --target <path> 指定自定义安装目录，或使用 --list 查看预设。"
        exit 1
    fi

    echo ""
    printf "请选择要安装的 Agent（输入编号，逗号分隔；直接回车=全部；q=取消）: "
    read_input CHOICE

    # 归一化为小写判断关键字
    CHOICE_KEY=$(printf '%s' "${CHOICE}" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    case "${CHOICE_KEY}" in
        q|quit|exit)
            echo "已取消安装"
            exit 0 ;;
        ""|a|all)
            SELECTIONS="${FOUND}" ;;
        *)
            # 按编号在 FOUND 中查找对应行，结果写入 SELECTED_LINE
            find_found_line() {
                want_idx="$1"
                cur_idx=0
                _oifs="${IFS}"
                IFS='
'
                for fl in $FOUND; do
                    [ -z "${fl}" ] && continue
                    cur_idx=$((cur_idx + 1))
                    if [ "${cur_idx}" -eq "${want_idx}" ]; then
                        SELECTED_LINE="${fl}"
                        IFS="${_oifs}"
                        return 0
                    fi
                done
                IFS="${_oifs}"
                return 1
            }

            # 解析逗号/空格分隔的编号
            for token in $(printf '%s' "${CHOICE}" | tr ',' ' '); do
                case "${token}" in
                    ''|*[!0-9]*)
                        echo "错误: 无效的选择 '${token}'，请输入编号（如 1,2）"
                        exit 1 ;;
                esac
                if [ "${token}" -lt 1 ] || [ "${token}" -gt "${IDX}" ]; then
                    echo "错误: 编号 ${token} 超出范围（1-${IDX}）"
                    exit 1
                fi
                find_found_line "${token}"
                add_selection "${SELECTED_LINE}"
            done
            ;;
    esac

    # —— 询问是否覆盖已存在的安装 ——
    # 仅交互分支可达（上方已校验 stdin 为终端或可读取 /dev/tty）；dry-run 为预览，不询问。
    # 已通过 --force 指定时同样无需询问。
    if [ "${FORCE}" -ne 1 ] && [ "${DRY_RUN}" -ne 1 ]; then
        EXISTING=""
        EX_CNT=0
        set -f
        _oifs="${IFS}"
        IFS='
'
        for line in $SELECTIONS; do
            [ -z "${line}" ] && continue
            _p=${line#*|}
            _p=${_p#*|}
            if [ -d "${_p}" ]; then
                EX_CNT=$((EX_CNT + 1))
                EXISTING="${EXISTING}
${line}"
            fi
        done
        IFS="${_oifs}"
        set +f

        if [ "${EX_CNT}" -gt 0 ]; then
            echo ""
            echo "以下目标已存在 tack 安装："
            _i=0
            set -f
            _oifs="${IFS}"
            IFS='
'
            for line in $EXISTING; do
                [ -z "${line}" ] && continue
                _i=$((_i + 1))
                _n=${line%%|*}
                _r=${line#*|}
                _p=${_r#*|}
                printf "  [%d] %-10s %s\n" "${_i}" "${_n}" "${_p}"
            done
            IFS="${_oifs}"
            set +f
            echo ""
            printf "请选择覆盖方式 [y=全部覆盖 / n=全部跳过(默认) / e=逐个选择]: "
            read_input OW
            OW_KEY=$(printf '%s' "${OW}" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            case "${OW_KEY}" in
                y|yes)
                    FORCE=1
                    echo "  已选择: 全部覆盖"
                    ;;
                e|each)
                    set -f
                    _oifs="${IFS}"
                    IFS='
'
                    for line in $EXISTING; do
                        [ -z "${line}" ] && continue
                        _n=${line%%|*}
                        _r=${line#*|}
                        _p=${_r#*|}
                        while :; do
                            printf "  覆盖 %s (%s)？[y/N]: " "${_n}" "${_p}"
                            read_input ONE
                            ONE_KEY=$(printf '%s' "${ONE}" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            case "${ONE_KEY}" in
                                y|yes)
                                    FORCE_TARGETS="${FORCE_TARGETS}
${_p}"
                                    echo "    -> 将覆盖"
                                    break ;;
                                n|no|"")
                                    echo "    -> 将跳过已有文件"
                                    break ;;
                            esac
                        done
                    done
                    IFS="${_oifs}"
                    set +f
                    ;;
                *)
                    echo "  已选择: 全部跳过（已有文件保留，仅复制缺失文件）"
                    ;;
            esac
        fi
    fi
fi

# 统计目标数量
set -f
TOTAL=0
OLD_IFS="${IFS}"
IFS='
'
for line in $SELECTIONS; do
    [ -z "${line}" ] && continue
    TOTAL=$((TOTAL + 1))
done
IFS="${OLD_IFS}"
set +f

if [ "${TOTAL}" -eq 0 ]; then
    echo "错误: 未选择任何安装目标"
    exit 1
fi

# —— 安装单个目标 ——
# $1 = 序号  $2 = 总数  $3 = 名称  $4 = 目标路径
install_one() {
    # 函数内使用默认 IFS，避免外层按换行遍历时影响 $SKILL_FILES 分词
    _FUNC_IFS="${IFS}"
    unset IFS
    IDX_NOW="$1"
    IDX_TOTAL="$2"
    NAME_NOW="$3"
    TARGET_NOW="$4"

    # 该目标是否强制覆盖：全局 --force 或交互时逐个选择了覆盖
    # 用换行包裹后做 case 匹配，避免改动函数内已 unset 的 IFS
    FORCE_NOW="${FORCE}"
    if [ "${FORCE_NOW}" -ne 1 ] && [ -n "${FORCE_TARGETS}" ]; then
        case "
${FORCE_TARGETS}
" in
            *"
${TARGET_NOW}
"*) FORCE_NOW=1 ;;
        esac
    fi

    if [ "${DRY_RUN}" -eq 1 ]; then
        echo "[DRY RUN] (${IDX_NOW}/${IDX_TOTAL}) ${NAME_NOW} -> ${TARGET_NOW}"
        if [ -d "${TARGET_NOW}" ]; then
            if [ "${FORCE_NOW}" -eq 1 ]; then
                echo "    注意: 目标已存在，本次将覆盖已有文件"
            else
                echo "    注意: 目标已存在，已有文件将被跳过（加 --force 可覆盖）"
            fi
        fi
        echo ""
        echo "将复制以下文件："
        for item in $SKILL_FILES; do
            if [ -e "${SCRIPT_DIR}/${item}" ]; then
                echo "  ${item}"
            fi
        done
        echo ""
        echo "目标内容预览:"
        echo "  ${TARGET_NOW}/"
        for item in $SKILL_FILES; do
            if [ -e "${SCRIPT_DIR}/${item}" ]; then
                if [ -d "${SCRIPT_DIR}/${item}" ]; then
                    COUNT=$(find "${SCRIPT_DIR}/${item}" -type f | wc -l)
                    echo "  ├── ${item}/  (${COUNT} 个文件)"
                else
                    echo "  ├── ${item}"
                fi
            fi
        done
        echo ""
    else
        echo "==> (${IDX_NOW}/${IDX_TOTAL}) 安装 tack skill 到 ${NAME_NOW}"
        echo "    源目录: ${SCRIPT_DIR}"
        echo "    目标:   ${TARGET_NOW}"
        if [ -d "${TARGET_NOW}" ]; then
            if [ "${FORCE_NOW}" -eq 1 ]; then
                echo "    策略:   覆盖已存在的文件"
            else
                echo "    策略:   保留已存在的文件（仅复制缺失文件）"
            fi
        fi
        echo ""

        # 创建目标目录
        mkdir -p "${TARGET_NOW}"

        # 复制文件
        for item in $SKILL_FILES; do
            SRC="${SCRIPT_DIR}/${item}"
            DST="${TARGET_NOW}/${item}"

            if [ ! -e "${SRC}" ]; then
                echo "  跳过（不存在）: ${item}"
                continue
            fi

            if [ -e "${DST}" ] && [ "${FORCE_NOW}" -ne 1 ]; then
                echo "  已存在: ${item} (已跳过；使用 --force 或在交互询问中选择覆盖)"
                continue
            fi

            if [ -d "${SRC}" ]; then
                rm -rf "${DST}" 2>/dev/null || true
                cp -r "${SRC}" "${DST}"
                COUNT=$(find "${SRC}" -type f | wc -l)
                echo "  复制: ${item}/ (${COUNT} 个文件)"
            else
                cp "${SRC}" "${DST}"
                echo "  复制: ${item}"
            fi
        done

        echo ""
        echo "验证:"
        if [ -f "${TARGET_NOW}/SKILL.md" ]; then
            echo "  ✓ SKILL.md 已安装"
        else
            echo "  ✗ SKILL.md 缺失"
        fi
        if [ -d "${TARGET_NOW}/tack" ]; then
            COUNT=$(find "${TARGET_NOW}/tack" -type f | wc -l)
            echo "  ✓ tack/ 骨架（${COUNT} 个文件，含 harness/cmd、template、reference、rule、script）"
        else
            echo "  ✗ tack/ 骨架缺失"
        fi
        echo ""
    fi

    IFS="${_FUNC_IFS}"
}

# —— 循环执行安装 ——
NOW=0
set -f
OLD_IFS="${IFS}"
IFS='
'
for line in $SELECTIONS; do
    [ -z "${line}" ] && continue
    NOW=$((NOW + 1))
    sel_name=${line%%|*}
    sel_rest=${line#*|}
    sel_path=${sel_rest#*|}
    install_one "${NOW}" "${TOTAL}" "${sel_name}" "${sel_path}"
done
IFS="${OLD_IFS}"
set +f

if [ "${DRY_RUN}" -eq 1 ]; then
    echo "==> 预览完成，共 ${TOTAL} 个目标（加 --force 可覆盖已存在文件）"
else
    echo "==> 全部安装完成，共 ${TOTAL} 个目标"
    echo ""
    echo "下一步:"
    echo "  1. 重启 Agent 或重新加载技能"
    echo "  2. 输入 /tack 验证 skill 是否可用"
fi
