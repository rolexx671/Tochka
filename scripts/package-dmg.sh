#!/bin/bash
# Builds the app and packs dist/Tochka.dmg with a SHA-256 checksum next to it.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/version.env
TOCHKA_PREVIEW=0 bash scripts/build.sh
if [ ! -x build/packaging-env/bin/python3 ]; then
    python3 -m venv build/packaging-env
    build/packaging-env/bin/pip install --quiet 'ds-store==1.3.1' 'mac-alias==2.2.2'
fi
STAGE="$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")"
chmod 755 "$STAGE"
trap 'rm -rf "$STAGE"' EXIT
ditto build/Точка.app "$STAGE/Точка.app"
ln -s /Applications "$STAGE/Программы"
cp 'distribution/Начни здесь.html' "$STAGE/Начни здесь.html"
build/packaging-env/bin/python3 scripts/dmg-layout.py "$STAGE"
mkdir -p dist
DMG="$PWD/dist/Tochka.dmg"
hdiutil create -quiet -ov -volname 'Точка' -srcfolder "$STAGE" -format UDZO -fs HFS+ "$DMG"
if [ -n "${TOCHKA_SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$TOCHKA_SIGN_IDENTITY" "$DMG"
fi
hdiutil verify -quiet "$DMG"
(cd dist && shasum -a 256 Tochka.dmg > Tochka.dmg.sha256)
echo "Готово: $DMG ($TOCHKA_VERSION)"
cat dist/Tochka.dmg.sha256
