#!/bin/bash
# Builds build/Точка.app (arm64 + x86_64). TOCHKA_PREVIEW=1 adds the screenshot mode used for docs.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/version.env
APP="$PWD/build/Точка.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/bin
FLAGS=()
if [ "${TOCHKA_PREVIEW:-0}" = 1 ]; then FLAGS+=(-D PREVIEW); fi
for arch in arm64 x86_64; do
    /usr/bin/swiftc -O ${FLAGS[@]+"${FLAGS[@]}"} -target "$arch-apple-macosx13.0" Sources/*.swift -o "build/bin/Tochka-$arch" \
        -framework AppKit -framework Carbon -framework ApplicationServices -framework ServiceManagement
done
/usr/bin/lipo -create build/bin/Tochka-arm64 build/bin/Tochka-x86_64 -output "$APP/Contents/MacOS/Tochka"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$TOCHKA_BUNDLE_ID</string>
<key>CFBundleName</key><string>Точка</string>
<key>CFBundleDisplayName</key><string>Точка</string>
<key>CFBundleExecutable</key><string>Tochka</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$TOCHKA_VERSION</string>
<key>CFBundleVersion</key><string>$TOCHKA_BUILD</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDevelopmentRegion</key><string>ru</string>
<key>CFBundleLocalizations</key><array><string>ru</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHumanReadableCopyright</key><string>© rolexx671 · MIT License · github.com/rolexx671/Tochka</string>
<key>NSAccessibilityUsageDescription</key><string>Для переназначения четырёх знаков препинания в русской раскладке.</string>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
if [ -n "${TOCHKA_SIGN_IDENTITY:-}" ]; then
    /usr/bin/codesign --force --options runtime --timestamp --sign "$TOCHKA_SIGN_IDENTITY" "$APP"
else
    /usr/bin/codesign --force --sign - --identifier "$TOCHKA_BUNDLE_ID" "$APP"
fi
/usr/bin/codesign --verify --strict "$APP"
echo "Собрано: $APP ($TOCHKA_VERSION, сборка $TOCHKA_BUILD)"
