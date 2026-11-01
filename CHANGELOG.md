# Changelog

## 1.1.0

- Add File → Export as PDF… (⇧⌘E) and Print… (⌘P). Both render the document with a light print layout: white pages, readable code blocks, tables that no longer clip, and wrapped long code lines.
- ⌘1–⌘8 select tabs 1–8 and ⌘9 the last tab; Editor / Preview / Split move to ⌥1 / ⌥2 / ⌥3.
- Open files as tabs in one window by default, shown as rounded tabs in the header instead of the grey system tab bar. Tabs can be reordered, dragged out into their own window, closed, or merged back; **+** adds a new document.
- Replace the two per-pane headers with one shared header; the separate "Preview …" header is gone.
- Opening a file replaces the empty Untitled document shown at launch.
- Add an in-process test for the tab strip.
- Keep the editor text view at the origin of its scroll view so the editor can no longer appear blank after a layout change.
- Fix `make screenshots`: pass paths through the environment so AppKit no longer tries to open the output folder, and reset both panes to the top of the document before capture.

## 1.0.2

- Clear the old divider when switching from Split to Editor or Preview.
- Remove divider space in single-pane views.
- Add an offscreen rendering regression test for repeated view switches.

## 1.0.1

- Clip line-number gutter drawing so it cannot cover the editor or pane header.
- Add an offscreen regression test for gutter rendering.

## 1.0.0

- Initial native macOS Markdown reader and editor.
- Add Editor, Preview, and resizable Split views, live preview, and a dark theme.
- Add document opening, autosave, undo/redo, recent files, an outline, synchronized scrolling, and zoom.
