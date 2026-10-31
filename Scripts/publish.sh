#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
project_root="$PWD"
repository="hemish22/Slate---Mac-Native-Lightweight-Markdown-Reader"
for dependency in git gh node python3; do
  command -v "$dependency" >/dev/null || { printf 'Missing command: %s\n' "$dependency" >&2; exit 1; }
done
gh auth status || { printf 'Run: gh auth login --scopes repo,workflow\nThen run this script again.\n' >&2; exit 1; }
gh api "repos/$repository" --silent
make test
make build
if [ "${SLATE_SKIP_SCREENSHOTS:-0}" != "1" ]; then
  bash Scripts/capture-screenshots.sh
fi
mkdir -p build
publish_directory="$(mktemp -d "$project_root/build/publish.XXXXXX")"
gh repo clone "$repository" "$publish_directory/repository"
checkout="$publish_directory/repository"
branch="$(git -C "$checkout" symbolic-ref --short HEAD)"
if ! git -C "$checkout" rev-parse --verify HEAD >/dev/null 2>&1; then
  branch=main
  git -C "$checkout" symbolic-ref HEAD refs/heads/main
fi
# Keep build output, local settings, and unrelated local files out of the upload.
for entry in Sources Resources Scripts Tests docs Examples .github .gitignore .gitattributes Makefile README.md LICENSE CONTRIBUTING.md CHANGELOG.md; do
  if [ -d "$project_root/$entry" ]; then
    rsync -a --exclude=.DS_Store "$project_root/$entry" "$checkout/"
  else
    cp "$project_root/$entry" "$checkout/$entry"
  fi
done
git -C "$checkout" add --all
if git -C "$checkout" diff --cached --quiet; then
  printf 'The remote repository already has these files.\n'
else
  git -C "$checkout" commit -m "Publish Slate native macOS Markdown reader and editor"
  git -C "$checkout" push origin "HEAD:$branch"
fi
gh repo edit "$repository" --description 'A lightweight, native macOS Markdown reader and editor with live preview, split view, syntax highlighting, and Finder integration.'
printf 'Published https://github.com/%s\nWorking checkout: %s\n' "$repository" "$checkout"
