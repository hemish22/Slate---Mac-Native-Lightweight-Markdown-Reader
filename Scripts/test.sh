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
node Tests/renderer.test.cjs
plutil -lint Resources/Info.plist
