#!/bin/sh
# install.sh — 将 tack skill 安装到常见 AI Agent
# Usage:
#   sh install.sh --agent <name>        安装到预设 agent
#   sh install.sh --target <path>       安装到自定义目录
#   sh install.sh --list                列出支持的 agent
#   sh install.sh --dry-run --agent trae  预览安装
#
# 支持的 agent 预设：
#   trae       TRAE (默认)
#   cursor     Cursor
#   windsurf   Windsurf
#   cline      Cline
#   codeium    Codeium
#   aider      Aider
#   devbox     DevBox
#   claude     Claude Code (~/Library/Application Support/...)

set -e

SKILL_NAME="tack"
SKILL_FILES="SKILL.md README.md resources script template"

# —— 预设 agent 目录 ——
# 格式: "agent_name|skill_dir"
AGENTS=""
AGENTS="${AGENTS}
trae|${HOME}/.trae/skills/${SKILL_NAME}"
AGENTS="${AGENTS}
cursor|${HOME}/.cursor/skills/${SKILL_NAME}"
AGENTS="${AGENTS}
windsurf|${HOME}/.windsurf/skills/${SKILL_NAME}"
AGENTS="${AGENTS}
cline|${HOME}/.cline/skills/${SKILL_NAME}"
AGENTS="${AGENTS}
codeium|${HOME}/.codeium/skills/${SKILL_NAME}"
AGENTS="${AGENTS}
aider|${HOME}/.aider/skills/${SKILL_NAME}"
AGENTS="${AGENTS}
devbox|${HOME}/.devbox/skills/${SKILL_NAME}"
AGENTS="${AGENTS}
claude|${HOME}/Library/Application Support/Code/User/globalStorage/skills/${SKILL_NAME}"

# —— 解析参数 ——
AGENT=""
TARGET=""
DRY_RUN=0
DO_LIST=0
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --agent)   AGENT="$2"; shift 2 ;;
        --target)  TARGET="$2"; shift 2 ;;
        --list)    DO_LIST=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force)   FORCE=1; shift ;;
        --help|-h)
            echo "Usage: sh install.sh [--agent <name> | --target <path>] [--dry-run] [--force] [--list]"
            echo ""
            echo "  --agent <name>   安装到预设 agent"
            echo "  --target <path>  安装到自定义目录"
            echo "  --list           列出所有支持的 agent"
            echo "  --dry-run        预览，不实际复制"
            echo "  --force          覆盖已存在的文件"
            echo ""
            echo "示例:"
            echo "  sh install.sh --agent trae"
            echo "  sh install.sh --agent cursor --dry-run"
            echo "  sh install.sh --target ~/my-custom-agent/skills/tack"
            exit 0 ;;
        *) echo "未知参数: $1 (使用 --help 查看帮助)"; exit 1 ;;
    esac
done

# —— 列出支持的 agent ——
if [ "$DO_LIST" -eq 1 ]; then
    echo "支持的 agent 预设："
    echo ""
    printf "%-12s %s\n" "名称" "安装路径"
    printf "%-12s %s\n" "----" "--------"
    echo "$AGENTS" | grep -v '^$' | while IFS='|' read -r name path; do
        printf "%-12s %s\n" "$name" "$path"
    done
    echo ""
    echo "也可使用 --target <path> 指定任意目录"
    exit 0
fi

# —— 确定目标路径 ——
if [ -n "$AGENT" ]; then
    TARGET=$(echo "$AGENTS" | grep "^${AGENT}|" | head -1 | cut -d'|' -f2)
    if [ -z "$TARGET" ]; then
        echo "错误: 未知的 agent '${AGENT}'"
        echo "使用 --list 查看支持的 agent"
        exit 1
    fi
fi

if [ -z "$TARGET" ]; then
    echo "错误: 请指定 --agent <name> 或 --target <path>"
    echo "使用 --help 查看帮助"
    exit 1
fi

# —— 解析脚本所在目录 ——
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/SKILL.md" ]; then
    echo "错误: 找不到 SKILL.md，请在 skill 仓库根目录运行此脚本"
    echo "  当前目录: $SCRIPT_DIR"
    exit 1
fi

# —— 预览模式 ——
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY RUN] 将安装 skill 到: $TARGET"
    echo ""
    echo "将复制以下文件："
    for item in $SKILL_FILES; do
        if [ -e "$SCRIPT_DIR/$item" ]; then
            echo "  $item"
        fi
    done
    echo ""
    echo "目标内容预览:"
    echo "  $TARGET/"
    for item in $SKILL_FILES; do
        if [ -e "$SCRIPT_DIR/$item" ]; then
            if [ -d "$SCRIPT_DIR/$item" ]; then
                COUNT=$(find "$SCRIPT_DIR/$item" -type f | wc -l)
                echo "  ├── $item/  ($COUNT 个文件)"
            else
                echo "  ├── $item"
            fi
        fi
    done
    exit 0
fi

# —— 执行安装 ——
echo "==> 安装 tack skill"
echo "    源目录: $SCRIPT_DIR"
echo "    目标:   $TARGET"
echo ""

# 创建目标目录
mkdir -p "$TARGET"

# 复制文件
for item in $SKILL_FILES; do
    SRC="$SCRIPT_DIR/$item"
    DST="$TARGET/$item"

    if [ ! -e "$SRC" ]; then
        echo "  跳过（不存在）: $item"
        continue
    fi

    if [ -e "$DST" ] && [ "$FORCE" -ne 1 ]; then
        echo "  已存在: $item (使用 --force 覆盖)"
        continue
    fi

    if [ -d "$SRC" ]; then
        rm -rf "$DST" 2>/dev/null || true
        cp -r "$SRC" "$DST"
        COUNT=$(find "$SRC" -type f | wc -l)
        echo "  复制: $item/ ($COUNT 个文件)"
    else
        cp "$SRC" "$DST"
        echo "  复制: $item"
    fi
done

echo ""
echo "==> 安装完成"
echo "    目标: $TARGET"
echo ""
echo "验证:"
if [ -f "$TARGET/SKILL.md" ]; then
    echo "  ✓ SKILL.md 已安装"
else
    echo "  ✗ SKILL.md 缺失"
fi
if [ -d "$TARGET/resources" ]; then
    COUNT=$(find "$TARGET/resources" -name '*.md' | wc -l)
    echo "  ✓ resources/ ($COUNT 个文件)"
else
    echo "  ✗ resources/ 缺失"
fi
if [ -d "$TARGET/script" ]; then
    echo "  ✓ script/"
fi
if [ -d "$TARGET/template" ]; then
    echo "  ✓ template/"
fi
echo ""
echo "下一步:"
echo "  1. 重启 Agent 或重新加载技能"
echo "  2. 输入 /tack 验证 skill 是否可用"
