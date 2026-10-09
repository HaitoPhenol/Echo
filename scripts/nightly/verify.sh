#!/usr/bin/env bash
# 夜间门禁：analyze 零警告 + 全部 widget/单元测试绿。
# 任何一步非零即退出，pack.sh 会据此拒绝出包。
set -euo pipefail

ECHO_DIR="$(cd "$(dirname "$0")/../../echo" && pwd)"
cd "$ECHO_DIR"

echo "== flutter analyze =="
flutter analyze

echo "== flutter test =="
flutter test

echo "== verify OK =="
