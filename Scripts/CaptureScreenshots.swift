import AppKit
import WebKit

// Render the production window and WebKit content in a separate app process.
// This captures only Slate's demo window, without desktop capture permissions.
@main
enum CaptureMain {
    static func main() {
        // Paths come from the environment, not argv: AppKit treats path
        // arguments as documents to open and shows "cannot open folder" errors.
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["SLATE_CAPTURE_OUTPUT"], let demo = environment["SLATE_CAPTURE_DEMO"] else {
            fputs("Usage: SLATE_CAPTURE_OUTPUT=DIR SLATE_CAPTURE_DEMO=FILE SlateCapture\n", stderr)
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = CaptureDelegate(output: URL(fileURLWithPath: output), demo: URL(fileURLWithPath: demo))
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class CaptureDelegate: NSObject, NSApplicationDelegate {
    private let output: URL
    private let demo: URL
    private var document: MarkdownDocument?
    private var controller: DocumentWindowController?
    private var index = 0
    private let names = ["slate-split", "slate-editor", "slate-preview"]

    init(output: URL, demo: URL) { self.output = output; self.demo = demo }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            // Both panes must start at the top. Synchronized scrolling races
            // with the programmatic reset and leaves one pane scrolled away.
            // This capture app has its own bundle ID, so real prefs are untouched.
            UserDefaults.standard.set(false, forKey: "syncedScrolling")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let document = MarkdownDocument()
            try document.read(from: Data(contentsOf: demo), ofType: "net.daringfireball.markdown")
            document.fileURL = demo
            document.makeWindowControllers()
            self.document = document
            guard let controller = document.windowControllers.first as? DocumentWindowController,
                  let window = controller.window else { fail("Could not create the demo window.") }
            self.controller = controller
            window.setFrame(NSRect(x: 60, y: 60, width: 1240, height: 840), display: true)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            controller.resetZoom(nil)
            controller.preview.onReady = { [weak self] in
                self?.controller?.preview.onReady = nil
                self?.nextView()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                self.fail("Screenshot capture timed out. Run this command in a normal macOS desktop session.")
            }
        } catch { fail(error.localizedDescription) }
    }

    private func nextView() {
        guard let controller else { fail("The demo window was closed.") }
        guard index < names.count else {
            print("Captured Split, Editor, and Preview into \(output.path)")
            exit(0)
        }
        switch index {
        case 0: controller.showSplit(nil)
        case 1: controller.showEditor(nil)
        default: controller.showPreview(nil)
        }
        resetScroll()
        // Layout and synchronized scrolling settle asynchronously after a mode
        // change, so reset again just before the snapshot to guarantee both
        // panes start at the top of the document.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.resetScroll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.capture() }
        }
    }

    private func resetScroll() {
        guard let controller else { return }
        controller.editor.setSelectedRange(NSRange(location: 0, length: 0))
        // Scroll to the topmost position AppKit allows rather than literal (0, 0);
        // with the line-number ruler the natural origin is not always zero.
        let clip = controller.editorScroll.contentView
        let top = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: clip.bounds.size)).origin
        clip.scroll(to: NSPoint(x: top.x, y: top.y))
        controller.editorScroll.reflectScrolledClipView(controller.editorScroll.contentView)
        controller.preview.scroll(to: 0)
    }

    private func capture() {
        guard let controller, let window = controller.window,
              let root = window.contentView?.superview else { fail("The demo window is unavailable.") }
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else {
            fail("Could not create a native window snapshot.")
        }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let native = NSImage(size: root.bounds.size)
        native.addRepresentation(bitmap)
        let filename = names[index] + ".png"

        // WebKit renders out of process, so capture it explicitly and composite
        // it into the native view snapshot at its actual window coordinates.
        if index == 1 {
            write(native: native, preview: nil, rect: .zero, filename: filename)
        } else {
            let converted = controller.preview.webView.convert(controller.preview.webView.bounds, to: root)
            let rect = root.isFlipped
                ? NSRect(x: converted.minX, y: root.bounds.height - converted.maxY, width: converted.width, height: converted.height)
                : converted
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = true
            controller.preview.webView.takeSnapshot(with: configuration) { image, error in
                guard let image else { self.fail(error?.localizedDescription ?? "WebKit snapshot failed.") }
                self.write(native: native, preview: image, rect: rect, filename: filename)
            }
        }
    }

    private func write(native: NSImage, preview: NSImage?, rect: NSRect, filename: String) {
        let composite = NSImage(size: native.size)
        composite.lockFocus()
        native.draw(in: NSRect(origin: .zero, size: native.size))
        preview?.draw(in: rect)
        composite.unlockFocus()
        guard let tiff = composite.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fail("PNG encoding failed.")
        }
        do { try png.write(to: output.appendingPathComponent(filename), options: .atomic) }
        catch { fail(error.localizedDescription) }
        index += 1
        nextView()
    }

    private func fail(_ message: String) -> Never {
        fputs("Screenshot capture: \(message)\n", stderr)
        exit(1)
    }
}
