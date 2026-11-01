#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" Sources/MarkdownContent.swift Tests/main.swift -o build/file-tests
build/file-tests
xcrun swiftc -module-cache-path "$PWD/build/module-cache" Sources/Theme.swift Sources/Editor.swift Tests/EditorTests.swift -o build/editor-tests
build/editor-tests
xcrun swiftc -module-cache-path "$PWD/build/module-cache" Sources/Theme.swift Sources/PaneSplitView.swift Tests/SplitViewTests.swift -o build/split-view-tests
build/split-view-tests
tab_sources=()
for swift_source in Sources/*.swift; do
  case "$swift_source" in Sources/main.swift) continue ;; esac
  tab_sources+=("$swift_source")
done
xcrun swiftc -module-name Slate -module-cache-path "$PWD/build/module-cache" \
  -framework AppKit -framework WebKit -framework UniformTypeIdentifiers \
  "${tab_sources[@]}" Tests/TabStripTests.swift -o build/tab-strip-tests
build/tab-strip-tests -ApplePersistenceIgnoreState YES
xcrun swiftc -module-name Slate -module-cache-path "$PWD/build/module-cache" \
  -framework AppKit -framework WebKit -framework UniformTypeIdentifiers -framework PDFKit \
  "${tab_sources[@]}" Tests/PDFExportTests.swift -o build/pdf-export-tests
build/pdf-export-tests -ApplePersistenceIgnoreState YES
node Tests/renderer.test.cjs
plutil -lint Resources/Info.plist
