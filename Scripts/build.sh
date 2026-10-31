#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Slate.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/build/module-cache"
if [ ! -f Resources/AppIcon.icns ] || [ Scripts/MakeIcon.swift -nt Resources/AppIcon.icns ]; then
  xcrun swiftc -module-cache-path "$PWD/build/module-cache" Scripts/MakeIcon.swift -o build/make-icon
  build/make-icon build/AppIcon.iconset Resources/AppIcon.icns
fi
architectures=(${SLATE_BUILD_ARCHS:-$(uname -m)})
binaries=()
for architecture in "${architectures[@]}"; do
  case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;; esac
  binary="$PWD/build/Slate-$architecture"
  xcrun swiftc -O -module-name Slate -target "$architecture-apple-macosx13.0" \
    -module-cache-path "$PWD/build/module-cache" \
    -framework AppKit -framework WebKit -framework UniformTypeIdentifiers \
    Sources/*.swift -o "$binary"
  binaries+=("$binary")
done
xcrun lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/Slate"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/vendor "$APP/Contents/Resources/"
cp Resources/preview.html Resources/renderer.js Resources/Welcome.md "$APP/Contents/Resources/"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
