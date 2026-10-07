#!/bin/bash
# Run only after enrolling in Apple Developer, signing with Developer ID,
# and storing credentials using `xcrun notarytool store-credentials`.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TOCHKA_NOTARY_PROFILE:?Укажи имя сохранённого профиля notarytool в TOCHKA_NOTARY_PROFILE}"
DMG="$PWD/dist/Tochka.dmg"
if ! codesign -dv "$DMG" 2>&1 | /usr/bin/grep -q 'Authority=Developer ID Application'; then
    echo 'Сначала пересобери DMG с TOCHKA_SIGN_IDENTITY="Developer ID Application: ...".' >&2
    exit 1
fi
xcrun notarytool submit "$DMG" --keychain-profile "$TOCHKA_NOTARY_PROFILE" --wait --output-format json > build/notary-result.json
if [ "$(plutil -extract status raw -o - build/notary-result.json)" != Accepted ]; then
    cat build/notary-result.json
    echo 'Apple не подтвердила сборку. Проверь журнал notarization.' >&2
    exit 1
fi
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
(cd dist && shasum -a 256 Tochka.dmg > Tochka.dmg.sha256)
echo 'Подпись, проверка Apple и прикреплённый билет проверены.'
