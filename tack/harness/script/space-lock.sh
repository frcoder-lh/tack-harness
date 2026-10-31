#!/bin/sh
# space-lock.sh — tack 空间级互斥锁（source 使用，不独立执行）
#
# 作用: 串行化同一空间内的登记写入（tack.yaml / AGENTS.md）与空间仓库提交，
#       避免并发「读取→修改→落盘」丢失更新、Git index.lock 冲突，
#       以及把其它工作区的文件混入本次提交。
#
# 用法:
#   . "${SCRIPT_DIR}/space-lock.sh"
#   tack_space_lock_acquire "<root>" [超时秒数，默认 60]
#   tack_space_lock_release
#
# 语义:
#   - 锁目录 <root>/.tack/lock，mkdir 原子创建；目录内 pid 仅供排查
#   - 持锁进程导出 TACK_SPACE_LOCK_HELD=1，子脚本据此跳过重复加锁（避免自锁）
#   - 只有实际加锁的进程会释放；子进程退出不会误删父进程的锁
#   - 获取超时报错（调用方 set -e 生效）；残留锁需确认无并发进程后手工删除

TACK_SPACE_LOCK_DIR=""
_TACK_SPACE_LOCK_OWNED=0

tack_space_lock_acquire() {
    _tsl_root="$1"
    _tsl_timeout="${2:-60}"

    [ "${TACK_SPACE_LOCK_HELD:-0}" = "1" ] && return 0

    mkdir -p "${_tsl_root}/.tack" || return 1
    _tsl_dir="${_tsl_root}/.tack/lock"
    _tsl_waited=0
    while ! mkdir "${_tsl_dir}" 2>/dev/null; do
        if [ "${_tsl_waited}" -ge "${_tsl_timeout}" ]; then
            echo "Error: 等待空间锁超时（${_tsl_timeout}s）: ${_tsl_dir}" >&2
            echo "       若确认没有其它 tack 进程在运行，删除该目录后重试" >&2
            return 1
        fi
        sleep 1
        _tsl_waited=$((_tsl_waited + 1))
    done

    printf '%s\n' "$$" > "${_tsl_dir}/pid"
    TACK_SPACE_LOCK_DIR="${_tsl_dir}"
    _TACK_SPACE_LOCK_OWNED=1
    export TACK_SPACE_LOCK_DIR
    export TACK_SPACE_LOCK_HELD=1
    return 0
}

tack_space_lock_release() {
    [ "${_TACK_SPACE_LOCK_OWNED}" = "1" ] || return 0
    [ -n "${TACK_SPACE_LOCK_DIR}" ] || return 0
    rm -f "${TACK_SPACE_LOCK_DIR}/pid" 2>/dev/null || true
    rmdir "${TACK_SPACE_LOCK_DIR}" 2>/dev/null || true
    _TACK_SPACE_LOCK_OWNED=0
    TACK_SPACE_LOCK_DIR=""
    unset TACK_SPACE_LOCK_HELD 2>/dev/null || true
}
