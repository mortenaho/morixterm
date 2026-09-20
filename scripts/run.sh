#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "Do not run MoriXterm with sudo/root. Run it as your desktop user." >&2
  exit 1
fi

exec ./build/bin/morixtrem
