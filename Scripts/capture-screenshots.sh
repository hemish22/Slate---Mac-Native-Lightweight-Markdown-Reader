#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
capture_app="$PWD/build/Slate Capture.app"
mkdir -p "$capture_app/Contents/MacOS" "$capture_app/Contents/Resources" build/module-cache
test -d build/Slate.app || { printf 'Run make build first.\n' >&2; exit 1; }
ditto build/Slate.app/Contents/Resources "$capture_app/Contents/Resources"
cp Resources/Info.plist "$capture_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable SlateCapture' "$capture_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.hemish.slate.capture' "$capture_app/Contents/Info.plist"
capture_sources=()
for swift_source in Sources/*.swift; do
  case "$swift_source" in Sources/main.swift|Sources/AppDelegate.swift) continue ;; esac
  capture_sources+=("$swift_source")
done
xcrun swiftc -O -module-name Slate -module-cache-path "$PWD/build/module-cache" \
  -framework AppKit -framework WebKit -framework UniformTypeIdentifiers \
  "${capture_sources[@]}" Scripts/CaptureScreenshots.swift -o "$capture_app/Contents/MacOS/SlateCapture"
codesign --force --sign - "$capture_app"
if [ "${1:-}" = "--build-only" ]; then exit 0; fi
printf 'Opening a separate demo window to capture Editor, Preview, and Split.\n'
"$capture_app/Contents/MacOS/SlateCapture" "$PWD/docs/images" "$PWD/Examples/Slate-Demo.md"
python3 Scripts/update-screenshots.py
