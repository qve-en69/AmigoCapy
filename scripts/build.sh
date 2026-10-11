#!/usr/bin/env bash
# Собирает AmigoCapy.app (Apple Silicon + Intel) и AmigoCapy.dmg в папку dist/.
# Нужен macOS с Xcode или Command Line Tools: bash scripts/build.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AmigoCapy"
VERSION="${VERSION:-1.6}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_MACOS="12.0"
DIST="dist"
APP="$DIST/$APP_NAME.app"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

binaries=()
for arch in arm64 x86_64; do
  triple="$arch-apple-macosx$MIN_MACOS"
  echo "==> Сборка $arch"
  swift build -c release --triple "$triple"
  binaries+=("$(swift build -c release --triple "$triple" --show-bin-path)/$APP_NAME")
done
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/$APP_NAME"

cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Картинки пушек и красок (общие с Windows-версией)"
mkdir -p "$APP/Contents/Resources/turrets" "$APP/Contents/Resources/paints"
cp windows/Assets/turrets/*.png "$APP/Contents/Resources/turrets/"
cp windows/Assets/paints/*.png "$APP/Contents/Resources/paints/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

echo "==> Иконка"
ICON_WORK="$DIST/icon"
mkdir -p "$ICON_WORK/AppIcon.iconset"
if swift scripts/make-icon.swift "$ICON_WORK/icon_1024.png"; then
  for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$ICON_WORK/icon_1024.png" --out "$ICON_WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$ICON_WORK/icon_1024.png" --out "$ICON_WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
else
  echo "!! Иконку нарисовать не удалось, собираю без неё"
fi

echo "==> Подпись (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> DMG"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp docs/install-ru.txt "$STAGE/Как установить.txt"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP_NAME.dmg"

echo "Готово: $DIST/$APP_NAME.dmg"
