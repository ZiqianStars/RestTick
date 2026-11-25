#!/bin/bash
# 构建并启动 RestTick
set -euo pipefail
cd "$(dirname "$0")"

./scripts/build_app.sh "$@"

pkill -x RestTick 2>/dev/null || true
sleep 0.3
open dist/RestTick.app

echo "RestTick 已启动，请在菜单栏查看计时。"
