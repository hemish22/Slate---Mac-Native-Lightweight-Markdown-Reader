import AppKit

// Drives the custom tab strip with synthesized mouse events: documents open
// as tabs, the native tab bar stays hidden, and tabs can be selected,
// reordered, torn into their own window, closed, and added.
@main
enum TabStripTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = true
        TabStripView.install()
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("slate-tab-tests-\(getpid())")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            for document in NSDocumentController.shared.documents { document.close() }
            try? FileManager.default.removeItem(at: folder)
        }

        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
        func open(_ name: String) -> MarkdownDocument {
            let url = folder.appendingPathComponent(name)
            try! Data("# \(name)\n".utf8).write(to: url)
            let document = MarkdownDocument()
            try! document.read(from: Data(contentsOf: url), ofType: "net.daringfireball.markdown")
            document.fileURL = url
            NSDocumentController.shared.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            settle()
            return document
        }
        func window(_ document: MarkdownDocument) -> NSWindow { document.windowControllers[0].window! }
        func strip(_ window: NSWindow) -> TabStripView {
            let strip = (window.tabGroup?.selectedWindow?.windowController as! DocumentWindowController).tabStrip
            strip.layoutSubtreeIfNeeded()
            strip.layout()
            return strip
        }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint, in strip: TabStripView) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: strip.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: strip.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func center(_ rect: NSRect) -> NSPoint { NSPoint(x: rect.midX - 20, y: rect.midY) }

        // An untouched Untitled document is replaced by the first file opened.
        let untitled = MarkdownDocument()
        NSDocumentController.shared.addDocument(untitled)
        untitled.makeWindowControllers()
        untitled.showWindows()
        settle()
        let a = open("A.md")
        precondition(!NSDocumentController.shared.documents.contains(untitled), "Opening a file replaces the empty Untitled document.")

        // Further files open as tabs of the same window.
        let b = open("B.md"), c = open("C.md")
        let group = window(a).tabGroup!
        precondition(group.windows.count == 3, "Files open as tabs by default.")
        precondition(group.windows.allSatisfy { $0.titlebarAccessoryViewControllers.allSatisfy(\.isHidden) },
                     "The grey native tab bar stays hidden.")
        precondition(strip(window(a)).tabFrames.count == 3, "The strip shows one tab per file.")

        // Clicking a tab selects it.
        var bar = strip(window(a))
        bar.mouseDown(with: mouse(.leftMouseDown, center(bar.tabFrames[0]), in: bar))
        bar.mouseUp(with: mouse(.leftMouseUp, center(bar.tabFrames[0]), in: bar))
        settle()
        precondition(group.selectedWindow === window(a), "Clicking a tab selects its document.")

        // Dragging a tab sideways reorders it.
        bar = strip(window(a))
        bar.mouseDown(with: mouse(.leftMouseDown, center(bar.tabFrames[0]), in: bar))
        bar.mouseDragged(with: mouse(.leftMouseDragged, center(bar.tabFrames[2]), in: bar))
        bar.mouseUp(with: mouse(.leftMouseUp, center(bar.tabFrames[2]), in: bar))
        settle()
        precondition(window(a).tabGroup!.windows.last === window(a), "Dragging a tab reorders it.")

        // Dragging a tab well below the strip tears it into its own window.
        bar = strip(window(a))
        let last = bar.tabFrames.count - 1
        bar.mouseDown(with: mouse(.leftMouseDown, center(bar.tabFrames[last]), in: bar))
        bar.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: bar.tabFrames[last].midX, y: bar.bounds.height + 80), in: bar))
        settle()
        precondition(window(a).tabGroup!.windows.count == 1, "A torn-off tab becomes its own window.")
        precondition(window(b).tabGroup!.windows.count == 2, "The remaining tabs stay together.")

        // The close button closes that tab's document.
        bar = strip(window(b))
        let closeIndex = bar.tabFrames.firstIndex { _ in true }!
        let closePoint = NSPoint(x: bar.closeRect(in: bar.tabFrames[closeIndex]).midX, y: bar.tabFrames[closeIndex].midY)
        let closing = window(b).tabGroup!.windows[closeIndex]
        bar.mouseDown(with: mouse(.leftMouseDown, closePoint, in: bar))
        bar.mouseUp(with: mouse(.leftMouseUp, closePoint, in: bar))
        settle()
        precondition(!closing.isVisible, "The close button closes the tab.")
        let survivor = [b, c].first { window($0) !== closing }!
        precondition(window(survivor).tabGroup!.windows.count == 1, "One tab remains after closing.")

        // The + button opens a new document as a tab.
        window(survivor).makeKeyAndOrderFront(nil)
        settle()
        TabStripView.newDocument = {
            // The test binary has no Info.plist document types, so create the document directly.
            let document = MarkdownDocument()
            NSDocumentController.shared.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
        }
        bar = strip(window(survivor))
        bar.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: bar.newTabFrame.midX, y: bar.newTabFrame.midY), in: bar))
        settle()
        precondition(window(survivor).tabGroup!.windows.count == 2, "The + button adds a tab.")
        // Shortcuts: Slate's real menu maps ⌘1–⌘9 to tabs and ⌥1–⌥3 to the views.
        let delegate = AppDelegate()
        delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
        func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) } }
        func shortcut(_ key: String, _ modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
            let matches = items(NSApp.mainMenu!).filter {
                $0.keyEquivalent == key && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers
            }
            precondition(matches.count == 1, "Exactly one menu item must own \(modifiers == .command ? "⌘" : "⌥")\(key).")
            return matches[0]
        }
        let tabs = window(survivor).tabGroup!.windows
        let controller = tabs[0].windowController as! DocumentWindowController
        func press(_ key: String, _ modifiers: NSEvent.ModifierFlags) {
            let item = shortcut(key, modifiers)
            NSApp.sendAction(item.action!, to: controller, from: item)
            settle()
        }
        press("2", .command)
        precondition(window(survivor).tabGroup!.selectedWindow === tabs[1], "⌘2 selects the second tab.")
        press("1", .command)
        precondition(window(survivor).tabGroup!.selectedWindow === tabs[0], "⌘1 selects the first tab.")
        press("9", .command)
        precondition(window(survivor).tabGroup!.selectedWindow === tabs.last, "⌘9 selects the last tab.")
        press("1", .option)
        precondition(controller.mode == .editor, "⌥1 shows the editor.")
        press("2", .option)
        precondition(controller.mode == .preview, "⌥2 shows the preview.")
        press("3", .option)
        precondition(controller.mode == .split, "⌥3 shows split view.")
        for number in 1...8 { _ = shortcut("\(number)", .command) }

        // A real ⌥ + number key press (not just the menu action) switches views,
        // even though AppKit never sends ⌥-only presses to menu shortcuts.
        func optionKey(_ keyCode: UInt16, _ character: String) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0,
                             windowNumber: tabs[0].windowNumber, context: nil, characters: character,
                             charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode)!
        }
        precondition(DocumentWindowController.handleViewShortcut(optionKey(18, "¡")) && controller.mode == .editor, "⌥1 key press shows the editor.")
        precondition(DocumentWindowController.handleViewShortcut(optionKey(19, "™")) && controller.mode == .preview, "⌥2 key press shows the preview.")
        precondition(DocumentWindowController.handleViewShortcut(optionKey(20, "£")) && controller.mode == .split, "⌥3 key press shows split view.")
        let plainKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                        windowNumber: tabs[0].windowNumber, context: nil, characters: "1",
                                        charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18)!
        precondition(!DocumentWindowController.handleViewShortcut(plainKey), "Typing 1 without ⌥ still types.")

        print("Tab strip: open as tabs, hidden native bar, select, reorder, tear off, close, new tab, ⌘1–⌘9 tab and ⌥1–⌥3 view shortcut checks passed.")
        exit(0)
    }
}
