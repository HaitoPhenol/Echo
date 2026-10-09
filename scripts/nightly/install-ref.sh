#!/usr/bin/env bash
# 回滚/基线工具：从任意 git ref（tag/分支/sha）在独立 worktree 构建并装到手机，
# 不触碰当前工作区。同时把 APK 归档到 artifacts/apks/ref-<名>.apk。
#
# 用法：scripts/nightly/install-ref.sh v0.5.4
set -euo pipefail

REF="${1:?用法：install-ref.sh <git-ref，如 v0.5.4>}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

# 确认 ref 存在
git rev-parse --verify "$REF^{commit}" >/dev/null
SHA="$(git rev-parse --short=8 "$REF")"
SAFE="$(printf '%s' "$REF" | tr '/:' '--')"
WT="/tmp/echo-refs/$SAFE"

mkdir -p "$REPO/artifacts/apks"

if [ ! -d "$WT" ]; then
  echo "== 创建 worktree $WT @ $REF ($SHA) =="
  mkdir -p /tmp/echo-refs
  git worktree add --detach "$WT" "$REF"
else
  echo "== worktree 已存在，检出到 $REF =="
  git -C "$WT" checkout --detach "$REF"
fi

echo "== 构建（首次需 pub get）=="
( cd "$WT/echo" && flutter pub get >/dev/null && flutter build apk --debug )

BUILT="$WT/echo/build/app/outputs/flutter-apk/app-debug.apk"
ARCHIVE="$REPO/artifacts/apks/ref-${SAFE}-${SHA}.apk"
cp "$BUILT" "$ARCHIVE"

echo "== 安装 $REF =="
adb install -r -d "$BUILT"
echo "完成：已安装 $REF ($SHA)，APK 归档：$ARCHIVE"
