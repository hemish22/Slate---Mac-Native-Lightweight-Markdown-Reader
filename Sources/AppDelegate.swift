import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var recentFilesMenu: NSMenu?
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSDocumentController.shared.autosavingDelay = 2
        // New documents open as tabs; Slate draws its own tab strip.
        NSWindow.allowsAutomaticWindowTabbing = true
        TabStripView.install()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            DocumentWindowController.handleViewShortcut(event) ? nil : event
        }
        buildMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let main = NSMenu()
        NSApp.mainMenu = main
        let app = submenu("Slate", in: main)
        item("About Slate", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), in: app)
        app.addItem(.separator())
        item("Hide Slate", #selector(NSApplication.hide(_:)), key: "h", in: app)
        item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], in: app)
        item("Show All", #selector(NSApplication.unhideAllApplications(_:)), in: app)
        app.addItem(.separator())
        item("Quit Slate", #selector(NSApplication.terminate(_:)), key: "q", in: app)

        let file = submenu("File", in: main)
        item("New", #selector(NSDocumentController.newDocument(_:)), key: "n", in: file)
        item("Open…", #selector(NSDocumentController.openDocument(_:)), key: "o", in: file)
        let recent = submenu("Open Recent", in: file)
        recentFilesMenu = recent
        recent.delegate = self
        file.addItem(.separator())
        item("Close", #selector(NSWindow.performClose(_:)), key: "w", in: file)
        item("Save", #selector(NSDocument.save(_:)), key: "s", in: file)
        item("Save As…", #selector(NSDocument.saveAs(_:)), key: "s", modifiers: [.command, .shift], in: file)
        item("Revert to Saved…", #selector(NSDocument.revertToSaved(_:)), in: file)
        file.addItem(.separator())
        item("Export as PDF…", #selector(DocumentWindowController.exportPDF(_:)), key: "e", modifiers: [.command, .shift], in: file)
        item("Print…", #selector(DocumentWindowController.printMarkdown(_:)), key: "p", in: file)

        let edit = submenu("Edit", in: main)
        item("Undo", Selector(("undo:")), key: "z", in: edit)
        item("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift], in: edit)
        edit.addItem(.separator())
        item("Cut", #selector(NSText.cut(_:)), key: "x", in: edit)
        item("Copy", #selector(NSText.copy(_:)), key: "c", in: edit)
        item("Paste", #selector(NSText.paste(_:)), key: "v", in: edit)
        item("Select All", #selector(NSText.selectAll(_:)), key: "a", in: edit)
        edit.addItem(.separator())
        item("Find…", #selector(DocumentWindowController.findInDocument(_:)), key: "f", in: edit)

        let format = submenu("Format", in: main)
        item("Bold", #selector(DocumentWindowController.makeBold(_:)), key: "b", in: format)
        item("Italic", #selector(DocumentWindowController.makeItalic(_:)), key: "i", in: format)
        item("Inline Code", #selector(DocumentWindowController.makeCode(_:)), key: "e", in: format)
        item("Link", #selector(DocumentWindowController.makeLink(_:)), key: "k", in: format)

        let view = submenu("View", in: main)
        // ⌘1–⌘9 select tabs, so the views use ⌥1–⌥3.
        item("Editor", #selector(DocumentWindowController.showEditor(_:)), key: "1", modifiers: .option, in: view)
        item("Preview", #selector(DocumentWindowController.showPreview(_:)), key: "2", modifiers: .option, in: view)
        item("Split View", #selector(DocumentWindowController.showSplit(_:)), key: "3", modifiers: .option, in: view)
        view.addItem(.separator())
        item("Zoom In", #selector(DocumentWindowController.zoomIn(_:)), key: "+", in: view)
        item("Zoom Out", #selector(DocumentWindowController.zoomOut(_:)), key: "-", in: view)
        item("Actual Size", #selector(DocumentWindowController.resetZoom(_:)), key: "0", in: view)
        item("Synchronized Scrolling", #selector(DocumentWindowController.toggleSync(_:)), in: view)
        view.addItem(.separator())
        item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control], in: view)

        let window = submenu("Window", in: main)
        NSApp.windowsMenu = window
        item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m", in: window)
        item("Zoom", #selector(NSWindow.performZoom(_:)), in: window)
        window.addItem(.separator())
        item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), in: window)
        // ⌘1–⌘8 jump to that tab and ⌘9 to the last one, as in browsers. The
        // items stay hidden to keep the menu short but still answer their keys.
        for number in 1...9 {
            let tab = NSMenuItem(title: number == 9 ? "Last Tab" : "Tab \(number)",
                                 action: #selector(DocumentWindowController.selectTab(_:)), keyEquivalent: "\(number)")
            tab.keyEquivalentModifierMask = .command
            tab.tag = number
            tab.isHidden = true
            tab.allowsKeyEquivalentWhenHidden = true
            window.addItem(tab)
        }

        let help = submenu("Help", in: main)
        item("Welcome to Slate", #selector(openWelcome(_:)), in: help, target: self)
    }

    @objc private func openWelcome(_ sender: Any?) {
        guard let url = Bundle.main.url(forResource: "Welcome", withExtension: "md") else { return }
        do {
            let document = try NSDocumentController.shared.makeUntitledDocument(ofType: "net.daringfireball.markdown") as! MarkdownDocument
            document.markdown = try String(contentsOf: url, encoding: .utf8)
            NSDocumentController.shared.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
        } catch { NSApp.presentError(error) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentFilesMenu else { return }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        if menu.items.isEmpty { menu.addItem(withTitle: "No Recent Documents", action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)), in: menu, target: NSDocumentController.shared)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        parent.addItem(item)
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "",
                      modifiers: NSEvent.ModifierFlags = .command, in menu: NSMenu, target: AnyObject? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        menu.addItem(item)
    }
}
