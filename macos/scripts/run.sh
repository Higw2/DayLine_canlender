#!/bin/zsh
set -euo pipefail
base_dir="${0:A:h:h}"
"$base_dir/scripts/build-app.sh"
exec "$base_dir/build/DayLine.app/Contents/MacOS/DayLine" "$@"
