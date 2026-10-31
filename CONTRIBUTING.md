# Contributing to Slate

Slate is a Swift and AppKit app for macOS 13 or later. Install Xcode or Apple's Command Line Tools and Node.js, then follow the clone instructions in the README.

```sh
make build
make test
make run
```

Keep changes focused, retain the plain-text document format, and prefer system frameworks to new runtime dependencies. Include a regression test for a bug when it can meaningfully verify the behavior.

For UI changes, also check the app on a macOS desktop: open a demo Markdown document, edit it and confirm the preview updates, save and reopen, use undo/redo, switch between all three views repeatedly, resize the window, and open the file from Finder. Offscreen rendering tests supplement these manual checks.

Use `make screenshots` to update screenshots from `Examples/Slate-Demo.md`. Do not use private or client documents in public screenshots.

When filing a bug, include your macOS version, Slate version, reproduction steps, and a minimal Markdown sample with sensitive information removed.
