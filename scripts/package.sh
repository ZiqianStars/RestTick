#!/bin/bash
# 打包可分发安装镜像（DMG）。
#
# 可选环境变量：
#   CODESIGN_IDENTITY  Developer ID Application 证书名称；缺省时自动查找，找不到则用 ad-hoc 签名
#   NOTARY_PROFILE     notarytool 钥匙串配置名；设置后自动提交公证并装订
#
# 公证前需先执行（一次即可）：
#   xcrun notarytool store-credentials <配置名> --apple-id <账号> --team-id <团队> --password <专用密码>
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build_app.sh release

APP="dist/RestTick.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/RestTick-$VERSION.dmg"

IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
fi

if [ -n "$IDENTITY" ]; then
    echo "签名：$IDENTITY"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
    echo "未找到 Developer ID 证书，使用 ad-hoc 签名（仅本机可用，无法通过 Gatekeeper）"
    codesign --force --sign - "$APP"
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/RestTick.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "RestTick" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "已生成：$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "提交公证：$NOTARY_PROFILE"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "公证与装订完成"
else
    echo "跳过公证：配置 NOTARY_PROFILE 后可自动提交"
fi

codesign --verify --strict "$APP" && echo "签名校验通过"
