#!/bin/bash
# 运行单元测试（与 build_app.sh 使用相同的 SDK 兼容处理）
set -euo pipefail
cd "$(dirname "$0")/.."

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

# 运行测试（当前工具链缺少 XCTest，使用独立断言运行器）
swift run RestTickTests "$@"
