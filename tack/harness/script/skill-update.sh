#!/bin/sh
# skill-update.sh — 把本机已安装的 tack skill 更新到指定版本
#
# update 命令的固定流程脚本：定位本机 skill 安装目录 → 下载指定版本源码 →
# 整体覆盖本机 skill 目录（先完整备份旧目录，再清空后复制
# SKILL.md / README.md / README.en.md / CHANGELOG.md / CHANGELOG.en.md / install.sh / tack/，旧版残留文件一并清除）→ 校验版本号。
# 只有覆盖动作，不做版本对比（对比由 update 命令负责）。
#
# Usage:
#   sh skill-update.sh <update-url> <tag>                       # 自动探测本机 skill 目录
#   sh skill-update.sh <update-url> <tag> --skill-root <path>   # 指定 skill 安装目录
#   sh skill-update.sh <update-url> <tag> --tack-root <path>    # 临时/备份目录落入 tack 空间
#
# 参数:
#   update-url   仓库地址（取自 AGENTS.md 项目信息区块 skill_update_url，
#                如 https://github.com/frcoder-lh/tack-harness）
#   tag          目标版本 tag（Vx.y.z）
#   --tack-root <path>  可选；tack 空间的 .tack 运行时目录。传入后下载解压的临时
#                目录放 <path>/tmp/ 下（脚本结束自动清理），旧版完整备份放
#                <path>/backup/skill-<时间戳>/（保留供回滚，不自动删除）；
#                不传时二者均使用系统临时目录（脱离空间手动执行的回退模式）
#
# 退出码: 0 成功；非 0 失败（本机 skill 未被改动，可安全重试）
#
# 注意: 下载源码压缩包为 <update-url>/archive/refs/tags/<tag>.tar.gz，
#       下载兼容性处理与 install.sh 一致（curl 失败回退 --ssl-no-revoke，再回退 wget）。

set -eu

UPDATE_URL=""
TAG=""
SKILL_ROOT_ARG=""
TACK_ROOT_ARG=""

usage() {
    sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --skill-root)
            [ $# -ge 2 ] || { echo "错误：--skill-root 需要参数" >&2; exit 1; }
            SKILL_ROOT_ARG="$2"; shift 2 ;;
        --tack-root)
            [ $# -ge 2 ] || { echo "错误：--tack-root 需要参数" >&2; exit 1; }
            TACK_ROOT_ARG="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        --)
            shift; break ;;
        -*)
            echo "错误：未知选项 $1" >&2; usage; exit 1 ;;
        *)
            if [ -z "${UPDATE_URL}" ]; then
                UPDATE_URL="$1"
            elif [ -z "${TAG}" ]; then
                TAG="$1"
            else
                echo "错误：多余参数 $1" >&2; usage; exit 1
            fi
            shift ;;
    esac
done

[ -n "${UPDATE_URL}" ] || { echo "错误：缺少 update-url 参数" >&2; usage; exit 1; }
[ -n "${TAG}" ] || { echo "错误：缺少 tag 参数" >&2; usage; exit 1; }
case "${UPDATE_URL}" in
    http://*|https://*) ;;
    *) echo "错误：update-url 须为 http(s) 地址: ${UPDATE_URL}" >&2; exit 1 ;;
esac

# —— 1. 定位本机 skill 安装目录 ——
# 未指定时按 install.sh 的 agent 预设路径探测（HOME 下 <agent>/skills/tack）
locate_skill_root() {
    candidates=""
    for agent_dir in .trae-cn .trae .cursor .windsurf .cline .codeium .aider .devbox; do
        dir="${HOME}/${agent_dir}/skills/tack"
        [ -f "${dir}/SKILL.md" ] && candidates="${candidates}${dir}
"
    done
    if [ -z "${candidates}" ]; then
        echo "错误：未在常见 agent 路径探测到 tack skill，请用 --skill-root 指定安装目录（须含 SKILL.md）" >&2
        exit 1
    fi
    count=$(printf '%s' "${candidates}" | grep -c . )
    if [ "${count}" -gt 1 ]; then
        echo "错误：探测到多个 tack skill 安装目录，请用 --skill-root 指定其一:" >&2
        printf '%s' "${candidates}" >&2
        exit 1
    fi
    printf '%s' "${candidates}"
}

if [ -n "${SKILL_ROOT_ARG}" ]; then
    [ -f "${SKILL_ROOT_ARG}/SKILL.md" ] || {
        echo "错误：--skill-root 目录不存在或缺少 SKILL.md: ${SKILL_ROOT_ARG}" >&2
        exit 1
    }
    SKILL_ROOT="${SKILL_ROOT_ARG}"
else
    SKILL_ROOT="$(locate_skill_root)"
fi

OLD_VER=$(sed -n '2,/^---$/ s/^version:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "${SKILL_ROOT}/SKILL.md" | head -1)
echo ">> 本机 skill: ${SKILL_ROOT}（当前 ${OLD_VER:-未知版本}）"

# —— 2. 下载指定版本源码 ——
ARCHIVE_URL="${UPDATE_URL}/archive/refs/tags/${TAG}.tar.gz"
# 临时下载/解压目录：传入 --tack-root 时落 <tack-root>/tmp/（结束自动清理）；
# 不传则回退系统临时目录（脱离 tack 空间手动执行）
if [ -n "${TACK_ROOT_ARG}" ]; then
    TMP_PARENT="${TACK_ROOT_ARG}/tmp"
    mkdir -p "${TMP_PARENT}"
    TMP_SRC="$(mktemp -d "${TMP_PARENT}/skill-update.$$.XXXXXX")"
else
    TMP_SRC="$(mktemp -d)"
fi
cleanup_src() { rm -rf "${TMP_SRC}"; }
trap cleanup_src EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo ">> 下载源码: ${ARCHIVE_URL}"
ARCHIVE="${TMP_SRC}/src.tar.gz"
DOWNLOAD_OK=0
if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "${ARCHIVE_URL}" -o "${ARCHIVE}"; then
        DOWNLOAD_OK=1
    elif curl -fsSL --ssl-no-revoke "${ARCHIVE_URL}" -o "${ARCHIVE}"; then
        # Windows Git Bash 的 schannel 后端在受限网络下需关闭证书吊销检查
        DOWNLOAD_OK=1
    fi
elif command -v wget >/dev/null 2>&1; then
    if wget -q -O "${ARCHIVE}" "${ARCHIVE_URL}"; then
        DOWNLOAD_OK=1
    fi
fi
if [ "${DOWNLOAD_OK}" -ne 1 ]; then
    echo "错误: 源码下载失败（需要可用的 curl 或 wget）: ${ARCHIVE_URL}" >&2
    echo "提示: 可手动安装最新 skill 后重新执行 update" >&2
    exit 1
fi
tar -xzf "${ARCHIVE}" -C "${TMP_SRC}"
# GitHub 压缩包解压后为 <repo>-<tag>/ 单层目录
SRC_SKILL="$(find "${TMP_SRC}" -mindepth 2 -maxdepth 2 -name SKILL.md | head -n 1)"
[ -n "${SRC_SKILL}" ] || { echo "错误: 下载包中未找到 SKILL.md" >&2; exit 1; }
SRC_ROOT="$(dirname "${SRC_SKILL}")"

SRC_VER=$(sed -n '2,/^---$/ s/^version:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "${SRC_ROOT}/SKILL.md" | head -1)
if [ "${SRC_VER}" != "${TAG}" ]; then
    echo "错误: 下载包 SKILL.md 版本 (${SRC_VER}) 与目标 tag (${TAG}) 不一致，中止" >&2
    exit 1
fi

# —— 3. 备份本机旧版本（回滚用，保留不自动清理；路径打印给用户） ——
# 传入 --tack-root 时备份到 tack 空间 .tack/backup/skill-<时间戳>/（与 update/study 的
# harness-<ts>、study-<ts> 备份同级）；不传时回退系统临时目录
STAMP="$(date +%Y%m%d%H%M%S)"
if [ -n "${TACK_ROOT_ARG}" ]; then
    mkdir -p "${TACK_ROOT_ARG}/backup"
    BACKUP_DIR="${TACK_ROOT_ARG}/backup/skill-${STAMP}"
else
    BACKUP_DIR="${TMPDIR:-/tmp}/tack-backup-${STAMP}-$$"
fi
# 同一秒连跑防撞名
[ -e "${BACKUP_DIR}" ] && BACKUP_DIR="${BACKUP_DIR}-$$"
mkdir -p "${BACKUP_DIR}"
cp -R "${SKILL_ROOT}/." "${BACKUP_DIR}/"
echo ">> 旧版本已备份: ${BACKUP_DIR}（回滚用，确认无误后可手动删除）"

# —— 4. 整体覆盖本机 skill 目录（旧版本已在第 3 步完整备份） ——
# 清空整个目录后复制全部分发文件，旧版中新版已删除的残留文件/目录也一并清除
case "${SKILL_ROOT}" in
    ""|/|"${HOME}")
        echo "错误：skill 目录路径异常，拒绝清空: '${SKILL_ROOT}'" >&2
        exit 1 ;;
esac
rm -rf "${SKILL_ROOT}"
mkdir -p "${SKILL_ROOT}"
for item in SKILL.md README.md README.en.md CHANGELOG.md CHANGELOG.en.md install.sh tack; do
    if [ -e "${SRC_ROOT}/${item}" ]; then
        cp -R "${SRC_ROOT}/${item}" "${SKILL_ROOT}/${item}"
    fi
done

# —— 5. 校验 ——
NEW_VER=$(sed -n '2,/^---$/ s/^version:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "${SKILL_ROOT}/SKILL.md" | head -1)
[ "${NEW_VER}" = "${TAG}" ] || { echo "错误: 覆盖后 SKILL.md 版本 (${NEW_VER}) 与目标 (${TAG}) 不一致" >&2; exit 1; }

echo "✅ 本机 skill 已更新: ${OLD_VER:-未知} → ${NEW_VER}"
