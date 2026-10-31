import AppKit

/// Draws one rounded tab per document window in the current tab group, in
/// place of the grey native tab bar. The windows still use native tabbing, so
/// a tab can be torn into its own window and windows can be merged again.
final class TabStripView: NSView {
    weak var owner: NSWindow?

    private struct Tab {
        let window: NSWindow
        var frame: NSRect
    }

    private static let tabHeight: CGFloat = 29
    private static let topInset: CGFloat = 8
    private static let plusWidth: CGFloat = 30
    private var tabs: [Tab] = []
    private var plusFrame = NSRect.zero
    private var hover: Int?
    private var hoverClose = false
    private var pressedClose: Int?
    private var dragIndex: Int?
    private var trackingArea: NSTrackingArea?
    private var iconCache: [Bool: NSImage] = [:]

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 37) }

    // MARK: Model

    private var groupWindows: [NSWindow] {
        guard let owner else { return [] }
        let windows = owner.tabGroup?.windows ?? [owner]
        return windows.isEmpty ? [owner] : windows
    }

    func reload() {
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let windows = groupWindows
        let available = max(0, bounds.width - 8 - Self.plusWidth - 8)
        let width = min(200, max(110, available / CGFloat(max(1, windows.count))))
        var x: CGFloat = 8
        tabs = windows.map { window in
            defer { x += width + 2 }
            return Tab(window: window, frame: NSRect(x: x, y: Self.topInset, width: width, height: Self.tabHeight))
        }
        plusFrame = NSRect(x: x + 4, y: Self.topInset, width: Self.plusWidth, height: Self.tabHeight)
    }

    private func info(for window: NSWindow) -> (title: String, edited: Bool) {
        let controller = window.windowController as? DocumentWindowController
        return (controller?.tabTitle ?? window.title, window.isDocumentEdited)
    }

    /// Tab frames in strip coordinates, left to right (used by tests).
    var tabFrames: [NSRect] { tabs.map(\.frame) }
    var newTabFrame: NSRect { plusFrame }

    func closeRect(in frame: NSRect) -> NSRect {
        NSRect(x: frame.maxX - 26, y: frame.minY + 5, width: 20, height: frame.height - 10)
    }

    // MARK: Drawing

    private func tintedIcon(selected: Bool) -> NSImage? {
        if let cached = iconCache[selected] { return cached }
        guard let symbol = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil) else { return nil }
        let color = selected ? Theme.accent : Theme.muted
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        iconCache[selected] = image
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.setFill()
        bounds.fill()
        let selectedWindow = owner?.tabGroup?.selectedWindow ?? owner
        for (index, tab) in tabs.enumerated() {
            let selected = tab.window === selectedWindow
            let frame = tab.frame
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: frame).addClip()
            let shape = NSBezierPath(roundedRect: NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + 12),
                                     xRadius: 8, yRadius: 8)
            if selected {
                Theme.background.setFill()
                shape.fill()
                Theme.border.setStroke()
                shape.lineWidth = 1
                shape.stroke()
            } else if hover == index {
                Theme.background.withAlphaComponent(0.55).setFill()
                shape.fill()
            }
            NSGraphicsContext.restoreGraphicsState()

            let (title, edited) = info(for: tab.window)
            if let icon = tintedIcon(selected: selected) {
                let size = NSSize(width: 15, height: 11)
                icon.draw(in: NSRect(x: frame.minX + 13, y: frame.midY - size.height / 2, width: size.width, height: size.height))
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingMiddle
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: selected ? .medium : .regular),
                .foregroundColor: selected ? Theme.text : Theme.muted,
                .paragraphStyle: paragraph
            ]
            let textRect = NSRect(x: frame.minX + 36, y: frame.midY - 8, width: frame.width - 36 - 30, height: 16)
            (title as NSString).draw(in: textRect, withAttributes: attributes)

            let close = closeRect(in: frame)
            if hover == index || (selected && !edited) {
                let glyph = NSAttributedString(string: "✕", attributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                    .foregroundColor: hover == index && hoverClose ? Theme.text : Theme.muted
                ])
                let size = glyph.size()
                glyph.draw(at: NSPoint(x: close.midX - size.width / 2, y: close.midY - size.height / 2))
            } else if edited {
                Theme.muted.setFill()
                NSBezierPath(ovalIn: NSRect(x: close.midX - 3, y: close.midY - 3, width: 6, height: 6)).fill()
            }
        }
        let plus = NSAttributedString(string: "+", attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .regular), .foregroundColor: Theme.muted
        ])
        let size = plus.size()
        plus.draw(at: NSPoint(x: plusFrame.midX - size.width / 2, y: plusFrame.midY - size.height / 2 - 1))
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    private func index(at point: NSPoint) -> Int? { tabs.firstIndex { $0.frame.contains(point) } }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = index(at: point)
        let overClose = index.map { closeRect(in: tabs[$0].frame).contains(point) } ?? false
        if index != hover || overClose != hoverClose { hover = index; hoverClose = overClose; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        hoverClose = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressedClose = nil
        dragIndex = nil
        if plusFrame.contains(point) {
            // The new document joins this window's tabs.
            TabStripView.requestedHost = owner?.tabGroup?.selectedWindow ?? owner
            TabStripView.newDocument()
            TabStripView.requestedHost = nil
            return
        }
        guard let index = index(at: point) else { return }
        if closeRect(in: tabs[index].frame).contains(point) {
            pressedClose = index
            return
        }
        let window = tabs[index].window
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
        dragIndex = index
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let current = dragIndex, current < tabs.count else { return }
        let point = convert(event.locationInWindow, from: nil)
        // Pull a tab well below or above the strip to tear it into its own window.
        if (point.y > bounds.height + 30 || point.y < -30) && tabs.count > 1 {
            let window = tabs[current].window
            dragIndex = nil
            window.moveTabToNewWindow(nil)
            TabStripView.refreshAll()
            return
        }
        guard let target = index(at: NSPoint(x: min(max(point.x, tabs[0].frame.minX + 1), tabs[tabs.count - 1].frame.maxX - 1), y: Self.topInset + 1)),
              target != current, let group = owner?.tabGroup else { return }
        let window = tabs[current].window
        group.removeWindow(window)
        group.insertWindow(window, at: target)
        group.selectedWindow = window
        dragIndex = target
        TabStripView.refreshAll()
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedClose = nil; dragIndex = nil }
        guard let pressed = pressedClose, pressed < tabs.count else { return }
        let point = convert(event.locationInWindow, from: nil)
        if closeRect(in: tabs[pressed].frame).contains(point) { tabs[pressed].window.performClose(nil) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = index(at: point) else { return nil }
        let window = tabs[index].window
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = window
            menu.addItem(item)
        }
        add("Close Tab", #selector(closeTab(_:)))
        if tabs.count > 1 { add("Move Tab to New Window", #selector(moveToNewWindow(_:))) }
        if NSApp.windows.filter({ $0.windowController is DocumentWindowController }).count > tabs.count {
            add("Merge All Windows", #selector(mergeAll(_:)))
        }
        return menu
    }

    @objc private func closeTab(_ sender: NSMenuItem) { (sender.representedObject as? NSWindow)?.performClose(nil) }
    @objc private func moveToNewWindow(_ sender: NSMenuItem) {
        (sender.representedObject as? NSWindow)?.moveTabToNewWindow(nil)
        TabStripView.refreshAll()
    }
    @objc private func mergeAll(_ sender: NSMenuItem) {
        (sender.representedObject as? NSWindow)?.mergeAllWindows(nil)
        TabStripView.refreshAll()
    }

    // MARK: Coordination

    private static var installed = false
    private static weak var lastActive: NSWindow?
    fileprivate static weak var requestedHost: NSWindow?
    /// Creates the document for the + button (replaceable in tests).
    static var newDocument: () -> Void = { NSDocumentController.shared.newDocument(nil) }

    private static func isDocumentWindow(_ window: NSWindow) -> Bool {
        window.isVisible && (window.windowController as? DocumentWindowController)?.document != nil
    }

    /// The window whose tab group a newly opened document should join:
    /// the last active document window, else the oldest one.
    static func hostWindow(excluding window: NSWindow) -> NSWindow? {
        if let requestedHost, requestedHost !== window, isDocumentWindow(requestedHost) { return requestedHost }
        if let lastActive, lastActive !== window, isDocumentWindow(lastActive) { return lastActive }
        return NSApp.windows.first { $0 !== window && isDocumentWindow($0) }
    }

    /// Refresh every strip and keep the native tab bar hidden. Call once at launch.
    static func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.willCloseNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                if name != NSWindow.willCloseNotification, let window = note.object as? NSWindow, isDocumentWindow(window) { lastActive = window }
                refreshAll()
                // Closing and tab moves settle after the notification.
                DispatchQueue.main.async { refreshAll() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { refreshAll() }
            }
        }
    }

    static func refreshAll() {
        for window in NSApp.windows {
            guard let controller = window.windowController as? DocumentWindowController else { continue }
            hideNativeTabBar(of: window)
            controller.tabStrip.reload()
        }
    }

    /// Slate draws its own tabs, so the grey system tab bar (a titlebar
    /// accessory AppKit adds to tabbed windows) is always hidden.
    private static func hideNativeTabBar(of window: NSWindow) {
        for accessory in window.titlebarAccessoryViewControllers where !accessory.isHidden {
            accessory.isHidden = true
        }
    }
}
