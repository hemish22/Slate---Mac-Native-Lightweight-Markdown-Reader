import AppKit

@main
enum EditorTests {
    static func main() {
        let editor = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        editor.font = Theme.mono(13)
        editor.string = "# Visible heading\n\nThis is **Markdown**, with `code`.\n"
        let scroll = NSScrollView(frame: editor.frame)
        scroll.documentView = editor
        let ruler = LineNumberRuler(scrollView: scroll, editor: editor)
        ruler.frame = NSRect(x: 0, y: 0, width: 48, height: 400)

        // AppKit can pass a dirty rect wider than the gutter on macOS 14+.
        // Painting it must leave the adjacent editor and header untouched.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 440,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.magenta.setFill()
        NSRect(x: 0, y: 0, width: 600, height: 440).fill()
        ruler.drawHashMarksAndLabels(in: NSRect(x: 0, y: 0, width: 600, height: 440))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        // Bitmap rows count from the top; the 40 px header is rows 0...39.
        for (x, y) in [(200, 200), (47, 20), (500, 20)] {
            let pixel = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            precondition(pixel.redComponent > 0.95 && pixel.blueComponent > 0.95 && pixel.greenComponent < 0.05,
                         "The line-number gutter painted over content outside its bounds at (\(x), \(y)).")
        }
        let gutter = bitmap.colorAt(x: 5, y: 200)!.usingColorSpace(.deviceRGB)!
        precondition(gutter.greenComponent > 0.1 && gutter.redComponent < 0.3, "The gutter background was not drawn.")
        precondition(editor.string.contains("# Visible heading"), "Drawing must preserve the Markdown source.")
        print("Editor rendering: gutter background and line numbers stay inside their bounds.")
    }
}
