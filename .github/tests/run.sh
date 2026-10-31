#!/bin/sh
# 在当前平台定位 POSIX sh，再启动标准库回归测试。
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
TACK_TEST_SH="$(command -v sh)"
PYTHON=python3
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        TACK_TEST_SH="$(cygpath -m "${TACK_TEST_SH}")"
        PYTHON=python
        ;;
esac
export TACK_TEST_SH
export PYTHONDONTWRITEBYTECODE=1
exec "${PYTHON}" "${SCRIPT_DIR}/test_commands.py" "$@"
