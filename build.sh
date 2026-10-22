#!/bin/bash
# Compila o Conversor.app em build/. Com --install copia-o para /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Conversor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Universal: Apple Silicon e Intel.
for ARCH in arm64 x86_64; do
    swiftc -O -swift-version 5 -parse-as-library -target $ARCH-apple-macos26.0 \
        Sources/*.swift -o build/Conversor-$ARCH
done
lipo -create build/Conversor-arm64 build/Conversor-x86_64 -output "$APP/Contents/MacOS/Conversor"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

if [ ! -f build/AppIcon.icns ]; then
    swiftc -O make_icon.swift -o build/make_icon
    build/make_icon build/icon.png
    ICONSET=build/AppIcon.iconset
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) build/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force -s - "$APP"
echo "Criado: $APP"

# Zip para a release do GitHub (o install.sh descarrega este ficheiro).
rm -f build/Conversor.zip
ditto -c -k --keepParent "$APP" build/Conversor.zip

if [ "${1:-}" = "--install" ]; then
    pkill -x Conversor 2>/dev/null || true
    rm -rf /Applications/Conversor.app
    ditto "$APP" /Applications/Conversor.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Conversor.app
    /System/Library/CoreServices/pbs -update
    pkill -x Conversor 2>/dev/null || true
    open -g /Applications/Conversor.app --args --background
    echo "Instalado em /Applications/Conversor.app"
fi
