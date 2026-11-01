Slate is a native macOS Markdown reader and editor with Editor, Preview, and resizable Split views, live preview, syntax colors, and Finder integration.

## What's new in 1.1.0

- **Tabs:** files open as tabs in one window by default. Drag a tab to reorder it, drag it out to give it its own window, or right-click it to move it or merge windows back. **+** opens a new document.
- **Export as PDF and Print:** File → Export as PDF… (⇧⌘E) saves the rendered document as a paginated PDF on white pages. Print… (⌘P) uses the same layout. Wide tables and long code lines wrap to fit the page.
- **New shortcuts:** ⌘1–⌘8 jump to a tab and ⌘9 to the last one. Editor, Preview, and Split move to ⌥1, ⌥2, and ⌥3.
- **Cleaner header:** one shared header shows your tabs, replacing the grey system tab bar and the separate preview header.
- Opening a file now replaces the empty Untitled document Slate shows at launch.
- Fixed a case where the editor could appear blank after a layout change.

## Install

Download `Slate.zip`, unzip it, and move `Slate.app` into Applications. The universal app supports Apple Silicon and Intel Macs running macOS 13 or later.

The archive is ad hoc signed and is not Developer ID signed or notarized. The first time you open it, macOS may block it. Go to **System Settings → Privacy & Security** and choose **Open Anyway**. The README also covers building from source.

Verify the download using the included checksum:

    shasum -a 256 -c SHA256SUMS
