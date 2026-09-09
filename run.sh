#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$(uname -s)" in
    Darwin*)
        exec "$ROOT_DIR/macos/scripts/run.sh" "$@"
        ;;
    Linux*)
        exec "$ROOT_DIR/ubuntu/run.sh" "$@"
        ;;
    *)
        echo "不支持的操作系统: $(uname -s)" >&2
        exit 1
        ;;
esac
