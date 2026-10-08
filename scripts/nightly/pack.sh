#!/usr/bin/env bash
# 夜间出包：门禁 → debug 构建 → APK 归档（文件名带分支/sha/时间）
# → smoke.py 装机+手势序列+截图录屏+台账。设备锁由 smoke.py 持有。
#
# 用法：scripts/nightly/pack.sh <标签>
# 标签举例：fix-dock-arc、night-anchor-red-flash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
ECHO_DIR="$REPO/echo"
LABEL="${1:?用法：pack.sh <标签>}"

cd "$REPO"
BRANCH="$(git rev-parse --abbrev-ref HEAD | tr '/:' '--')"
SHA="$(git rev-parse HEAD)"
STAMP="$(date +%Y%m%d-%H%M%S)"
SAN_LABEL="$(printf '%s' "$LABEL" | tr ' /:' '---')"

mkdir -p "$REPO/artifacts/apks"

# 任一步失败都在台账留痕，方便明早排查
fail_row() {
  python3 - "$STAMP" "$SAN_LABEL" "$BRANCH" "$SHA" <<'PY'
import sys, pathlib
stamp, label, branch, sha = sys.argv[1:5]
p = pathlib.Path("artifacts/LEDGER.md")
if not p.exists():
    p.write_text("# 夜间台账\n\n| 时间 | 标签 | 来源 | APK | 报告 | 结果 |\n|---|---|---|---|---|---|\n", encoding="utf-8")
with p.open("a", encoding="utf-8") as f:
    f.write(f"| {stamp} | {label} | {branch}@{sha[:8]} | - | - | 失败：见对话记录 |\n")
PY
}
trap fail_row ERR

echo "== 1/3 门禁 verify =="
"$REPO/scripts/nightly/verify.sh"

echo "== 2/3 构建 debug APK =="
( cd "$ECHO_DIR" && flutter build apk --debug )
BUILT="$ECHO_DIR/build/app/outputs/flutter-apk/app-debug.apk"
[ -f "$BUILT" ] || { echo "构建产物不存在：$BUILT" >&2; exit 1; }

ARCHIVE="$REPO/artifacts/apks/${STAMP}-${SAN_LABEL}-${BRANCH}-${SHA:0:8}.apk"
cp "$BUILT" "$ARCHIVE"
echo "已归档：$ARCHIVE"

echo "== 3/3 真机冒烟（脚本内排队拿设备锁）=="
python3 "$REPO/scripts/nightly/smoke.py" \
  --label "$SAN_LABEL" --apk "$ARCHIVE" \
  --branch "$BRANCH" --sha "$SHA"

echo
echo "全部完成。明早先看 artifacts/LEDGER.md，再打开对应 reports/<时间>-${SAN_LABEL}/index.md"
