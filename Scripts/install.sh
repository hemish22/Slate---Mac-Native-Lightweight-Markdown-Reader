#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
install_directory="${SLATE_INSTALL_DIR:-$HOME/Applications}"
test -d build/Slate.app || { printf 'Build the app with make build first.\n' >&2; exit 1; }
mkdir -p "$install_directory"
ditto build/Slate.app "$install_directory/Slate.app"
printf 'Installed %s/Slate.app\n' "$install_directory"
