#!/usr/bin/env bash
set -euo pipefail
base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$base_dir/.." && pwd)"
dist_dir="$repo_dir/dist"
mkdir -p "$dist_dir"

package_name="DayLine-Ubuntu-24.04"
tmp_dir="$(mktemp -d /tmp/dayline-pkg.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

target="$tmp_dir/$package_name"
mkdir -p "$target"

# Copy files
cp -r "$base_dir/dayline" "$target/"
cp -r "$base_dir/packaging" "$target/"
cp "$base_dir/install.py" "$target/"
cp "$base_dir/run.sh" "$target/"
cp "$base_dir/README.md" "$target/"

# Clean up pycache
find "$target" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$target" -name "*.pyc" -delete 2>/dev/null || true

# Archive
tar -czf "$dist_dir/$package_name.tar.gz" -C "$tmp_dir" "$package_name"
cp "$dist_dir/$package_name.tar.gz" "$dist_dir/DayLine-Ubuntu.tar.gz"

echo "Ubuntu 安装包已生成："
echo "  - $dist_dir/$package_name.tar.gz"
echo "  - $dist_dir/DayLine-Ubuntu.tar.gz"
