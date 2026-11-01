import AppKit
import PDFKit

// Exports a long document to PDF and checks it is paginated, uses the light
// print theme, contains the rendered text, and owns its menu shortcuts.
@main
enum PDFExportTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = true
        TabStripView.install()
        let resources = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("../Resources/preview.html").standardizedFileURL
        precondition(FileManager.default.fileExists(atPath: resources.path), "Run from the repository's build folder.")
        PDFExporter.pageURL = resources
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("slate-pdf-tests-\(getpid())")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let paragraphs = (1...60).map { "Paragraph \($0) of the export test, long enough to wrap across the printed line." }
        let markdown = "# Export Heading\n\n**Bold words** and `inline code`.\n\n| Name | Value |\n| --- | --- |\n| Rows | 2 |\n\n"
            + "| Method | Path | Notes |\n| --- | --- | --- |\n"
            + "| GET | `/admin/clients/:id/{contract,summary,comments,comments/:cid,breakdown/subreddits,timeseries}` | Same read models for any client RIGHTEDGE |\n\n"
            + "```swift\nlet answer = 42\n```\n\n" + paragraphs.joined(separator: "\n\n") + "\n\nThe final line.\n"
        let document = MarkdownDocument()
        document.markdown = markdown
        document.makeWindowControllers()
        document.showWindows()
        let controller = document.windowControllers[0] as! DocumentWindowController
        precondition(controller.pdfName == "Untitled.pdf", "PDFs are named after the document.")

        let url = folder.appendingPathComponent("Export.pdf")
        var result: Bool?
        controller.exportPDF(to: url) { result = $0 }
        let deadline = Date().addingTimeInterval(20)
        while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        precondition(result == true, "Export finishes successfully.")

        let pdf = PDFDocument(url: url)!
        precondition(pdf.pageCount >= 2, "Long documents span several pages (got \(pdf.pageCount)).")
        let text = pdf.string ?? ""
        for expected in ["Export Heading", "Bold words", "inline code", "let answer = 42", "Rows", "Paragraph 1 ", "The final line."] {
            precondition(text.contains(expected), "The PDF contains “\(expected)”.")
        }
        precondition(!text.contains("**") && !text.contains("```"), "The PDF shows rendered Markdown, not source.")
        let first = pdf.page(at: 0)!
        // Wide tables with long unbroken code wrap inside the page instead of
        // being cut off: every character stays inside the right margin.
        let pageWidth = first.bounds(for: .mediaBox).width
        let characters = first.numberOfCharacters
        let rightmost = (0..<characters).map { first.characterBounds(at: $0) }.filter { $0.width > 0 }.map(\.maxX).max() ?? 0
        let sample = (first.string! as NSString).range(of: "Bold words")
        // An over-wide table makes WebKit shrink the whole page (to about 64%) and clip it.
        let glyph = first.characterBounds(at: sample.location).height
        precondition(glyph > 6, "Body text prints at full size, not shrunk to fit a wide table (glyph \(glyph)pt).")
        precondition(text.contains("RIGHTEDGE"), "The table's last column is exported.")
        precondition(rightmost <= pageWidth - 50, "Text stays inside the right margin (reaches \(Int(rightmost)) of \(Int(pageWidth))).")
        let bounds = first.bounds(for: .mediaBox)
        let image = first.thumbnail(of: NSSize(width: bounds.width, height: bounds.height), for: .mediaBox)
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let corner = bitmap.colorAt(x: 4, y: 4)!.usingColorSpace(.deviceRGB)!
        precondition(corner.redComponent > 0.95 && corner.greenComponent > 0.95 && corner.blueComponent > 0.95,
                     "Pages use a white background, not the dark theme.")

        // An empty document exports a blank page, not the welcome placeholder.
        let empty = MarkdownDocument()
        empty.makeWindowControllers()
        empty.showWindows()
        let emptyURL = folder.appendingPathComponent("Empty.pdf")
        result = nil
        (empty.windowControllers[0] as! DocumentWindowController).exportPDF(to: emptyURL) { result = $0 }
        while result == nil && Date() < deadline.addingTimeInterval(20) { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        precondition(result == true, "Empty export finishes.")
        precondition(!(PDFDocument(url: emptyURL)?.string ?? "").contains("clear view"), "Empty exports skip the placeholder.")

        let delegate = AppDelegate()
        delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
        func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) } }
        func owner(_ key: String, _ modifiers: NSEvent.ModifierFlags) -> [NSMenuItem] {
            items(NSApp.mainMenu!).filter { $0.keyEquivalent == key && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers }
        }
        precondition(owner("e", [.command, .shift]).map(\.action) == [#selector(DocumentWindowController.exportPDF(_:))], "⇧⌘E exports a PDF.")
        precondition(owner("p", .command).map(\.action) == [#selector(DocumentWindowController.printMarkdown(_:))], "⌘P prints.")

        print("PDF export: \(pdf.pageCount) pages, rendered text, white pages, blank empty export, and ⇧⌘E / ⌘P shortcut checks passed.")
        exit(0)
    }
}
