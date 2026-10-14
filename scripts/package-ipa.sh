#!/usr/bin/env bash
# 把 xcodebuild archive 产物打包成未签名 .ipa（供 AltStore / Sideloadly / TrollStore / 自签证书安装）
# 用法: scripts/package-ipa.sh <xcarchive 路径> <输出 ipa 路径>
set -euo pipefail

ARCHIVE="${1:?用法: package-ipa.sh <xcarchive> <out.ipa>}"
OUT="${2:?用法: package-ipa.sh <xcarchive> <out.ipa>}"

APP_DIR="$ARCHIVE/Products/Applications"
APP_PATH="$(find "$APP_DIR" -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "错误: 在 $APP_DIR 未找到 .app" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Payload"
cp -R "$APP_PATH" "$WORK/Payload/"

# 去掉签名目录（自签工具会重新签名，留着反而可能冲突）
rm -rf "$WORK/Payload/$(basename "$APP_PATH")/_CodeSignature"

mkdir -p "$(dirname "$OUT")"
(
  cd "$WORK"
  zip -qry "$OLDPWD/$OUT" Payload
)

echo "已生成: $OUT ($(du -h "$OUT" | cut -f1))"
