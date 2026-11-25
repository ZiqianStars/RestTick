#!/bin/bash
# 构建 RestTick.app（SwiftPM + 手动组装 App Bundle）
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"

# 只有 CommandLineTools（未装完整 Xcode）时，新版 SDK 的 SwiftUI 把 @State 等实现为宏，
# 但工具链未附带 SwiftUIMacros 插件；退回随附的旧 SDK 以属性包装器形式编译。
if xcode-select -p 2>/dev/null | grep -q CommandLineTools; then
    for sdk in \
        /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
        /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk; do
        if [ -d "$sdk" ]; then
            export SDKROOT="$sdk"
            echo "使用 SDK：$sdk"
            break
        fi
    done
fi

swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="dist/RestTick.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/RestTick" "$APP/Contents/MacOS/RestTick"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Backgrounds "$APP/Contents/Resources/Backgrounds"

# Ad-hoc 签名，保证菜单栏 App 在本地稳定运行
if ! codesign --force --sign - "$APP" >/dev/null 2>&1; then
    echo "提示：codesign 失败，可忽略（仍可直接运行）"
fi

echo "构建完成：$PWD/$APP"
