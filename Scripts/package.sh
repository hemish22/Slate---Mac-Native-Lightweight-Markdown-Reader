#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../build"
test -d Slate.app || { printf 'Build the app with make build first.\n' >&2; exit 1; }
codesign --verify --deep --strict Slate.app
ditto -c -k --sequesterRsrc --keepParent Slate.app Slate.zip
shasum -a 256 Slate.zip > SHA256SUMS
printf 'Packaged build/Slate.zip and build/SHA256SUMS\n'
