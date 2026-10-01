#!/bin/sh
# init-tack.sh — 初始化 tack 空间（确保 Git 可用、物化骨架、初始化为 Git 仓库）
# Usage: sh init-tack.sh <root-path>
#
# 本脚本是 tack 空间目录结构的唯一权威创建入口：
#   tack/ 目录本身就是出厂模板，内部结构与 tack 空间一一对应——
#   复制 <tack>/ 全部内容即完成静态骨架物化（AGENTS.md、.gitignore 在空间根）。
#   wiki 公共知识是运行时产物：init 命令有真实事实才按需物化文件，
#   故骨架只预建空的 wiki/ 目录；space/、repo/ 同为空目录，由本脚本显式创建。
# 额外职责：
#   1. 确保本机 Git 可用——缺失时尝试自动安装：Linux 用系统包管理器，
#      macOS 用 Homebrew；Windows 不经本脚本（Git for Windows 由 run.ps1
#      通过 winget 自动安装，bash 环境内 Git 必然随附）。
#   2. 将目标目录初始化为 Git 仓库并自动完成首次提交（.git 已存在时跳过；
#      空间仓库的 Git 操作全部由框架经 space.sh 自动完成，用户不直接操作）。
# 注意：项目信息存放在 AGENTS.md 的项目信息区块中，骨架不再包含 status.yaml。

set -e

# ensure_git — 确保 git 真正可用（command -v 命中且 git --version 成功；
# macOS 上 /usr/bin/git 可能是触发 Xcode CLT 安装的存根，故必须双重验证）。
# 缺失时按平台尝试自动安装；无法自动安装则报错并给出手动下载地址。
ensure_git() {
    if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
        return 0
    fi

    echo "Git not found; attempting to install Git automatically..."

    case "$(uname -s)" in
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                brew install git
            else
                echo "Error: Homebrew not found. Install Git from https://git-scm.com/download/mac"
                echo "       or run 'xcode-select --install' to install Apple Command Line Tools."
                exit 1
            fi
            ;;
        Linux)
            # root 直接执行，非 root 经 sudo（无 sudo/无权限时安装失败，走统一报错）
            if [ "$(id -u)" -eq 0 ]; then PRIV=""; else PRIV="sudo"; fi
            ok=0
            if   command -v apt-get >/dev/null 2>&1; then
                $PRIV apt-get update && $PRIV apt-get install -y git && ok=1
            elif command -v dnf >/dev/null 2>&1; then
                $PRIV dnf install -y git && ok=1
            elif command -v yum >/dev/null 2>&1; then
                $PRIV yum install -y git && ok=1
            elif command -v pacman >/dev/null 2>&1; then
                $PRIV pacman -Sy --noconfirm git && ok=1
            elif command -v zypper >/dev/null 2>&1; then
                $PRIV zypper --non-interactive install git && ok=1
            elif command -v apk >/dev/null 2>&1; then
                $PRIV apk add git && ok=1
            fi
            if [ "$ok" -ne 1 ]; then
                echo "Error: automatic Git installation failed (no supported package manager or insufficient privileges)."
                echo "Install Git manually: https://git-scm.com/downloads"
                exit 1
            fi
            ;;
        *)
            echo "Error: Git not found on $(uname -s). Install Git manually: https://git-scm.com/downloads"
            exit 1
            ;;
    esac

    if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
        echo "Git is ready: $(git --version)"
    else
        echo "Error: Git installation could not be verified. Install Git manually: https://git-scm.com/downloads"
        exit 1
    fi
}

ROOT="${1:-.}"

# 解析脚本所在目录，定位 tack 骨架根目录（本脚本位于 <tack>/harness/script/ 下）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TACK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ ! -d "$TACK_DIR" ]; then
    echo "Error: tack skeleton not found at $TACK_DIR"
    exit 1
fi

# 物化骨架前先确保 Git 可用（Git 是 worktree 工作流与空间版本管理的基础依赖）
ensure_git

mkdir -p "$ROOT"

# 复制 tack 骨架全部内容到目标目录：骨架内文件已位于最终位置，复制即物化
# -n: 目标已存在的文件跳过，不覆盖用户内容；重复执行安全
cp -rn "$TACK_DIR/." "$ROOT/"

# space/ 工作空间、repo/ 代码主仓库、wiki/ 公共知识目录在骨架中均为空目录
# （Git 不跟踪空目录；wiki 文件由 init 命令按需物化），显式创建
mkdir -p "$ROOT/space" "$ROOT/repo" "$ROOT/wiki"

# .tack/ 是框架本地运行时数据根（log 日志 / backup 回滚备份 / state 本机状态 /
# tmp 临时文件），整体被 .gitignore 排除、可随时删除。log/backup/state 为常驻
# 目录，预建让布局显式化；tmp/ 不预建——各脚本按需 mkdir -p、退出时空目录顺手
# 移除（重复执行安全）
mkdir -p "$ROOT/.tack/log" "$ROOT/.tack/backup" "$ROOT/.tack/state"

# README.md 是 skill 安装目录根的使用说明，物化到 harness/ 目录（已存在则跳过）；
# 不放空间根——根目录 README.md 位置留给用户项目自身
SKILL_ROOT="$(cd "$TACK_DIR/.." && pwd)"
[ -f "$SKILL_ROOT/README.md" ] && [ ! -e "$ROOT/harness/README.md" ] && \
    cp "$SKILL_ROOT/README.md" "$ROOT/harness/README.md"

# 将 tack 空间根初始化为 Git 仓库（$ROOT/.git 已存在则跳过；重复执行安全）。
# 空间仓库的 Git 操作全部由框架自动完成：init 后立即做首次提交，
# 用户无需也不应直接对 $root 执行 git（用户 git 只作用于 $work/repo/ 代码仓库）。
ABS_ROOT="$(cd "$ROOT" && pwd)"
if [ -d "$ROOT/.git" ]; then
    echo "Git repository already exists: $ABS_ROOT"
else
    git -C "$ROOT" init >/dev/null
    echo "Git repository initialized: $ABS_ROOT"
fi

# 物化 agent hook 声明（.trae/hooks.json、.claude/settings.json，可选加速层）：
# 已存在不覆盖；失败不阻断初始化（hook 纯为加速，缺失时自动降级为 AGENTS.md 路由）
sh "$ABS_ROOT/harness/script/hook/install-hooks.sh" "$ABS_ROOT" || true

# 回填 skill_version：版本号以本机 skill 的 SKILL.md front matter 为唯一事实源，
# 物化后写入 AGENTS.md 项目信息区块（skill_update_url 已在出厂模板中固定）。
# --if-empty 保证重复执行或已 update 过的空间不被本机旧版本降级；
# --no-commit 抑制单次提交，交由下方首次提交统一入库。
SKILL_VER=""
if [ -f "$SKILL_ROOT/SKILL.md" ]; then
    SKILL_VER=$(sed -n '2,/^---$/ s/^version:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$SKILL_ROOT/SKILL.md" | head -1)
fi
if [ -n "$SKILL_VER" ]; then
    sh "$ABS_ROOT/harness/script/project.sh" skill-version "$ABS_ROOT" "$SKILL_VER" --if-empty --no-commit
else
    echo "Warning: 未在 $SKILL_ROOT/SKILL.md front matter 找到 version 字段，skill_version 留空（可稍后执行 update 修正）" >&2
fi

# 首次/补漏自动提交（space.sh 内部判断无变更则跳过，重复执行安全）
sh "$ABS_ROOT/harness/script/space.sh" commit "$ABS_ROOT" "chore(tack): initialize tack space"

echo "Tack space initialized at: $ABS_ROOT"
