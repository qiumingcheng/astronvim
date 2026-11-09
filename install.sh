#!/usr/bin/env bash
set -euo pipefail
ASTRO_INSTALL_SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if ! command -v python3 >/dev/null 2>&1; then
  printf '安装器需要 Python 3.8 或更新版本。请先用系统包管理器安装 python3。\n' >&2
  exit 1
fi
exec python3 "$ASTRO_INSTALL_SOURCE/installer.py" "$@"
