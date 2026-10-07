#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="assets/logo.png"
if [ ! -f "$SOURCE" ]; then echo 'Не найден выбранный логотип: assets/logo.png' >&2; exit 1; fi
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
