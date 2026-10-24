#!/bin/zsh
# Builds BambooDriver.app (universal arm64 + x86_64) into macos/build/.
set -euo pipefail
cd "${0:A:h}"

VERSION=0.2.1
APP=build/BambooDriver.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" build/obj

for arch in arm64 x86_64; do
    swiftc -O -target $arch-apple-macos14.0 BambooDriver/*.swift -o build/obj/BambooDriver-$arch
done
lipo -create build/obj/BambooDriver-arm64 build/obj/BambooDriver-x86_64 -output "$APP/Contents/MacOS/BambooDriver"
rm -rf build/obj

# App icon from the repo-root icon.png.
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET" "$APP/Contents/Resources"
for size in 16 32 128 256 512; do
    sips -z $size $size ../icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) ../icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.local.BambooDriver</string>
    <key>CFBundleName</key><string>BambooDriver</string>
    <key>CFBundleExecutable</key><string>BambooDriver</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Personal user-space driver for Wacom CTL-470.</string>
</dict>
</plist>
PLIST

# A stable identity keeps the Accessibility grant across rebuilds and updates; ad-hoc signatures
# change every build. Create it once with tools/make-signing-cert.sh (CI imports it from secrets).
IDENTITY="BambooDriver Local Signing"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "warning: '$IDENTITY' not found; ad-hoc signing (Accessibility must be re-granted after each build)"
    codesign --force --sign - "$APP"
fi
echo "built $APP ($VERSION)"
