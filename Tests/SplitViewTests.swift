import AppKit

@main
enum SplitViewTests {
    static func main() {
        let split = PaneSplitView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        split.isVertical = true
        split.dividerStyle = .thin
        let editor = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let preview = NSView(frame: NSRect(x: 301, y: 0, width: 299, height: 400))
        split.addArrangedSubview(editor)
        split.addArrangedSubview(preview)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 400,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        func matches(_ x: Int, _ color: NSColor) -> Bool {
            context.flushGraphics()
            let actual = bitmap.colorAt(x: x, y: 200)!.usingColorSpace(.deviceRGB)!
            let expected = color.usingColorSpace(.deviceRGB)!
            return abs(actual.redComponent - expected.redComponent) < 0.01 &&
                   abs(actual.greenComponent - expected.greenComponent) < 0.01 &&
                   abs(actual.blueComponent - expected.blueComponent) < 0.01
        }

        // Repeated transitions at the same window size must erase the old seam,
        // whether the editor or the preview is the surviving pane.
        for hideEditor in [true, false, true, false] {
            editor.isHidden = false
            preview.isHidden = false
            split.showsDivider = true
            split.adjustSubviews()
            split.setPosition(300, ofDividerAt: 0)
            precondition(split.dividerThickness > 0, "Split mode needs a draggable divider.")
            split.drawDivider(in: NSRect(x: 300, y: 0, width: 1, height: 400))
            precondition(matches(300, Theme.border), "Split divider must be visible.")

            split.showsDivider = false
            editor.isHidden = hideEditor
            preview.isHidden = !hideEditor
            split.adjustSubviews()
            precondition(split.dividerThickness == 0, "Single-pane mode must reserve no divider space.")
            split.draw(split.bounds)
            // Even if AppKit asks to draw an obsolete divider rect, ignore it.
            split.drawDivider(in: NSRect(x: 300, y: 0, width: 1, height: 400))
            precondition(matches(300, Theme.background), "Old divider remains visible after switching modes.")
            let active = hideEditor ? preview : editor
            precondition(abs(active.frame.width - split.bounds.width) < 0.01, "The active pane must fill the entire width.")
        }
        print("View switching: repeated split → preview/editor transitions clear the divider without resizing.")
    }
}
