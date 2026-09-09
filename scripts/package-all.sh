#!/usr/bin/env bash
set -euo pipefail
base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== 1. 打包 Ubuntu 24.04 安装包 ==="
"$base_dir/ubuntu/package.sh"

echo ""
echo "=== 2. 打包 macOS 原生应用包 ==="
"$base_dir/macos/scripts/build-app.sh"

echo ""
echo "=== 打包完成！发布包位于 dist/ 目录 ==="
ls -lh "$base_dir/dist"
