import AppKit

enum ViewMode: Int { case editor, preview, split }

final class DocumentWindowController: NSWindowController, NSToolbarDelegate, NSTextViewDelegate, NSSplitViewDelegate, NSMenuItemValidation {
    private weak var markdownDocument: MarkdownDocument?
    let editor = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
    let editorScroll = NSScrollView()
    let preview = PreviewController()
    private let splitView = PaneSplitView()
    private let editorPane = ColorView(Theme.background)
    private let previewPane = ColorView(Theme.background)
    private let editorTitle = Theme.label("Untitled.md", size: 12, color: Theme.text)
    private let previewTitle = Theme.label("Preview", size: 12, color: Theme.text)
    private let documentStats = Theme.label("")
    private let cursorStatus = Theme.label("")
    private let saveStatus = Theme.label("", color: Theme.green)
    private let highlighter = SyntaxHighlighter()
    private var ruler: LineNumberRuler!
    private var renderWork: DispatchWorkItem?
    private var statsWork: DispatchWorkItem?
    private var scrollObservation: NSObjectProtocol?
    private var mode: ViewMode = .split
    private var zoom = 1.0
    private var synced = true
    private var handlingScroll = false
    private var modeControl: NSSegmentedControl!
    private var syncButton: NSButton?
    private var splitRatio: CGFloat = 0.5

    init(document: MarkdownDocument) {
        markdownDocument = document
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 560, height: 400)
        window.backgroundColor = Theme.background
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .preferred
        window.setFrameAutosaveName("SlateDocument")
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
        window.contentView = ColorView(Theme.background)
        setupEditor()
        setupContent()
        setupToolbar()
        mode = ViewMode(rawValue: UserDefaults.standard.integer(forKey: "viewMode")) ?? .split
        if UserDefaults.standard.object(forKey: "viewMode") == nil { mode = .split }
        synced = UserDefaults.standard.object(forKey: "syncedScrolling") as? Bool ?? true
        zoom = UserDefaults.standard.object(forKey: "zoom") as? Double ?? 1
        zoom = min(2, max(0.7, zoom))
        reloadDocument()
        applyMode()
        applyZoom()
        updateSyncButton()
        preview.onScroll = { [weak self] fraction in self?.previewScrolled(fraction) }
        window.makeFirstResponder(mode == .preview ? preview.webView : editor)
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit {
        if let scrollObservation { NotificationCenter.default.removeObserver(scrollObservation) }
        renderWork?.cancel()
        statsWork?.cancel()
    }

    private func setupEditor() {
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.font = Theme.mono(13)
        editor.textColor = Theme.text
        editor.backgroundColor = Theme.background
        editor.insertionPointColor = Theme.accent
        editor.selectedTextAttributes = [.backgroundColor: NSColor(hex: 0x514369), .foregroundColor: NSColor.white]
        editor.textContainerInset = NSSize(width: 15, height: 24)
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = self
        editorScroll.documentView = editor
        editorScroll.hasVerticalScroller = true
        editorScroll.hasHorizontalScroller = false
        editorScroll.drawsBackground = true
        editorScroll.backgroundColor = Theme.background
        editorScroll.borderType = .noBorder
        ruler = LineNumberRuler(scrollView: editorScroll, editor: editor)
        editorScroll.verticalRulerView = ruler
        editorScroll.hasVerticalRuler = true
        editorScroll.rulersVisible = true
        editorScroll.contentView.postsBoundsChangedNotifications = true
        scrollObservation = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: editorScroll.contentView, queue: .main) { [weak self] _ in
                self?.ruler.needsDisplay = true
                self?.editorScrolled()
            }
    }

    private func setupContent() {
        guard let content = window?.contentView else { return }
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.addArrangedSubview(editorPane)
        splitView.addArrangedSubview(previewPane)
        content.addSubview(splitView)
        splitView.translatesAutoresizingMaskIntoConstraints = false

        setupPane(editorPane, title: editorTitle, symbol: "chevron.left.forwardslash.chevron.right", accessory: "MARKDOWN", body: editorScroll)
        setupPane(previewPane, title: previewTitle, symbol: "doc.richtext", accessory: "LIVE PREVIEW", body: preview.webView)

        let status = ColorView(Theme.chrome)
        content.addSubview(status)
        status.translatesAutoresizingMaskIntoConstraints = false
        let dot = Theme.label("●", size: 7, color: Theme.green)
        let left = NSStackView(views: [dot, saveStatus, separator(), documentStats])
        left.spacing = 9
        let right = NSStackView(views: [cursorStatus, separator(), Theme.label("UTF-8"), separator(), Theme.label("Markdown")])
        right.spacing = 12
        for stack in [left, right] { status.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: content.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            status.heightAnchor.constraint(equalToConstant: 29),
            left.leadingAnchor.constraint(equalTo: status.leadingAnchor, constant: 16),
            left.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: status.trailingAnchor, constant: -16),
            right.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -16)
        ])
        documentStats.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func separator() -> NSView {
        let view = ColorView(Theme.border)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: 1), view.heightAnchor.constraint(equalToConstant: 11)])
        return view
    }

    private func setupPane(_ pane: NSView, title: NSTextField, symbol: String, accessory: String, body: NSView) {
        let header = ColorView(Theme.chrome)
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: accessory)!)
        image.contentTintColor = Theme.accent
        let hint = Theme.label(accessory, size: 9, color: Theme.muted.withAlphaComponent(0.65))
        hint.font = .systemFont(ofSize: 9, weight: .medium)
        for view in [header, body] { pane.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        for view in [image, title, hint] { header.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: pane.topAnchor), header.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: pane.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 37),
            image.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16), image.widthAnchor.constraint(equalToConstant: 15),
            image.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 9), title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            hint.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16), hint.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: hint.leadingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: header.bottomAnchor), body.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: pane.trailingAnchor), body.bottomAnchor.constraint(equalTo: pane.bottomAnchor)
        ])
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "SlateToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("open"), .init("outline"), .flexibleSpace, .init("modes"), .flexibleSpace, .init("sync")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier.rawValue {
        case "open":
            item.label = "Open"
            item.toolTip = "Open Markdown file (⌘O)"
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open Markdown file")
            item.target = NSDocumentController.shared
            item.action = #selector(NSDocumentController.openDocument(_:))
        case "outline":
            item.label = "Outline"
            item.toolTip = "Jump to a heading"
            item.image = NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: "Document outline")
            item.target = self
            item.action = #selector(showOutline(_:))
        case "modes":
            modeControl = NSSegmentedControl(labels: ["Editor", "Preview", "Split"], trackingMode: .selectOne, target: self, action: #selector(changeMode(_:)))
            modeControl.segmentStyle = .rounded
            for (index, symbol) in ["chevron.left.forwardslash.chevron.right", "doc.richtext", "rectangle.split.2x1"].enumerated() {
                modeControl.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), forSegment: index)
                modeControl.setWidth(94, forSegment: index)
                modeControl.setToolTip(["Editor only (⌘1)", "Preview only (⌘2)", "Split view (⌘3)"][index], forSegment: index)
            }
            modeControl.setAccessibilityLabel("Document view")
            item.label = "View"
            item.view = modeControl
        case "sync":
            let button = NSButton(image: NSImage(systemSymbolName: "link", accessibilityDescription: "Synchronized scrolling")!, target: self, action: #selector(toggleSync(_:)))
            button.bezelStyle = .texturedRounded
            button.setButtonType(.toggle)
            button.toolTip = "Toggle synchronized scrolling"
            button.setAccessibilityLabel("Synchronized scrolling")
            syncButton = button
            item.view = button
            item.label = "Sync Scrolling"
        default: return nil
        }
        return item
    }

    func reloadDocument() {
        guard let document = markdownDocument else { return }
        if editor.string != document.markdown {
            editor.string = document.markdown
            editor.undoManager?.removeAllActions()
        }
        highlighter.highlight(editor)
        preview.update(markdown: document.markdown)
        fileLocationChanged()
        updateStats()
    }

    func fileLocationChanged() {
        guard let document = markdownDocument else { return }
        editorTitle.stringValue = document.fileURL?.lastPathComponent ?? "Untitled.md"
        previewTitle.stringValue = "Preview \(document.fileURL?.lastPathComponent ?? "Untitled.md")"
        preview.assets.directory = document.fileURL?.deletingLastPathComponent()
        preview.update(markdown: document.markdown)
        updateSaveStatus()
    }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        updateSaveStatus()
    }

    private func updateSaveStatus() {
        guard let document = markdownDocument else { return }
        saveStatus.stringValue = document.fileURL == nil ? "Unsaved" : document.isDocumentEdited ? "Edited" : "Saved"
        saveStatus.textColor = document.isDocumentEdited || document.fileURL == nil ? Theme.muted : Theme.green
    }

    func textDidChange(_ notification: Notification) {
        guard let document = markdownDocument else { return }
        document.markdown = editor.string
        document.updateChangeCount(.changeDone)
        updateSaveStatus()
        ruler.needsDisplay = true
        renderWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.highlighter.highlight(self.editor)
            if self.mode != .editor { self.preview.update(markdown: self.editor.string) }
            self.updateStats()
        }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        // Coalesce rapid selection changes without delaying text input.
        statsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateCursor(); self?.ruler.needsDisplay = true }
        statsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    private func updateStats() {
        let source = editor.string
        var count = 0
        source.enumerateSubstrings(in: source.startIndex..<source.endIndex, options: .byWords) { _, _, _, _ in count += 1 }
        let reading = max(1, Int(ceil(Double(count) / 220)))
        documentStats.stringValue = "\(count.formatted()) \(count == 1 ? "word" : "words")  ·  \(reading) min read"
        updateCursor()
    }

    private func updateCursor() {
        let source = editor.string as NSString
        let location = min(editor.selectedRange().location, source.length)
        let prefix = source.substring(to: location)
        let line = prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let range = source.lineRange(for: NSRange(location: location, length: 0))
        let column = source.substring(with: NSRange(location: range.location, length: location - range.location)).count + 1
        cursorStatus.stringValue = "Ln \(line), Col \(column)"
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) { setMode(ViewMode(rawValue: sender.selectedSegment) ?? .split) }
    @objc func showEditor(_ sender: Any?) { setMode(.editor) }
    @objc func showPreview(_ sender: Any?) { setMode(.preview) }
    @objc func showSplit(_ sender: Any?) { setMode(.split) }

    private func setMode(_ next: ViewMode) {
        if mode == .split && splitView.bounds.width > 0 { splitRatio = editorPane.frame.width / splitView.bounds.width }
        mode = next
        UserDefaults.standard.set(mode.rawValue, forKey: "viewMode")
        applyMode()
    }

    private func applyMode() {
        splitView.showsDivider = mode == .split
        editorPane.isHidden = mode == .preview
        previewPane.isHidden = mode == .editor
        modeControl?.selectedSegment = mode.rawValue
        splitView.adjustSubviews()
        window?.contentView?.layoutSubtreeIfNeeded()
        if mode == .split { splitView.setPosition(splitView.bounds.width * splitRatio, ofDividerAt: 0) }
        splitView.needsDisplay = true
        if mode != .editor { preview.update(markdown: editor.string) }
        window?.makeFirstResponder(mode == .preview ? preview.webView : editor)
        updateSyncButton()
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat { 240 }
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat { max(240, splitView.bounds.width - 240) }

    @objc func toggleSync(_ sender: Any?) {
        synced.toggle()
        UserDefaults.standard.set(synced, forKey: "syncedScrolling")
        updateSyncButton()
        if synced { editorScrolled() }
    }

    private func updateSyncButton() {
        syncButton?.state = synced ? .on : .off
        syncButton?.contentTintColor = synced ? Theme.accent : Theme.muted
        syncButton?.isEnabled = mode == .split
    }

    private func editorScrolled() {
        guard mode == .split, synced, !handlingScroll else { return }
        let available = max(0, editor.bounds.height - editorScroll.contentView.bounds.height)
        preview.scroll(to: available > 0 ? Double(editorScroll.contentView.bounds.minY / available) : 0)
    }

    private func previewScrolled(_ fraction: Double) {
        guard mode == .split, synced, !handlingScroll else { return }
        handlingScroll = true
        let available = max(0, editor.bounds.height - editorScroll.contentView.bounds.height)
        editorScroll.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(min(1, max(0, fraction))) * available))
        editorScroll.reflectScrolledClipView(editorScroll.contentView)
        handlingScroll = false
    }

    @objc func zoomIn(_ sender: Any?) { zoom = min(2, zoom + 0.1); applyZoom() }
    @objc func zoomOut(_ sender: Any?) { zoom = max(0.7, zoom - 0.1); applyZoom() }
    @objc func resetZoom(_ sender: Any?) { zoom = 1; applyZoom() }
    private func applyZoom() {
        editor.font = Theme.mono(13 * zoom)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5 * zoom
        paragraph.tabStops = []
        paragraph.defaultTabInterval = 4 * Theme.mono(13 * zoom).maximumAdvancement.width
        editor.defaultParagraphStyle = paragraph
        editor.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: (editor.string as NSString).length))
        editor.typingAttributes = [.font: Theme.mono(13 * zoom), .foregroundColor: Theme.text, .paragraphStyle: paragraph]
        preview.setZoom(zoom)
        ruler.needsDisplay = true
        UserDefaults.standard.set(zoom, forKey: "zoom")
    }

    @objc func findInDocument(_ sender: Any?) {
        if mode == .preview { setMode(.split) }
        window?.makeFirstResponder(editor)
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        editor.performFindPanelAction(item)
    }

    @objc func makeBold(_ sender: Any?) { wrapSelection(prefix: "**", suffix: "**", placeholder: "bold text") }
    @objc func makeItalic(_ sender: Any?) { wrapSelection(prefix: "*", suffix: "*", placeholder: "italic text") }
    @objc func makeCode(_ sender: Any?) { wrapSelection(prefix: "`", suffix: "`", placeholder: "code") }
    @objc func makeLink(_ sender: Any?) { wrapSelection(prefix: "[", suffix: "](https://)", placeholder: "link text") }

    private func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        if mode == .preview { setMode(.split) }
        window?.makeFirstResponder(editor)
        let range = editor.selectedRange()
        let selected = (editor.string as NSString).substring(with: range)
        let content = selected.isEmpty ? placeholder : selected
        let replacement = prefix + content + suffix
        guard editor.shouldChangeText(in: range, replacementString: replacement) else { return }
        editor.textStorage?.replaceCharacters(in: range, with: replacement)
        editor.didChangeText()
        editor.setSelectedRange(NSRange(location: range.location + (prefix as NSString).length, length: (content as NSString).length))
    }

    @objc private func showOutline(_ sender: Any?) {
        let menu = NSMenu(title: "Document Outline")
        let lines = editor.string.components(separatedBy: "\n")
        var inFence = false
        var fence: String?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if !inFence { inFence = true; fence = marker }
                else if marker == fence { inFence = false }
                continue
            }
            guard !inFence else { continue }
            let level = line.prefix(while: { $0 == "#" }).count
            guard level > 0, level <= 6, line.dropFirst(level).first == " " else { continue }
            let title = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
            let item = NSMenuItem(title: title, action: #selector(jumpToHeading(_:)), keyEquivalent: "")
            item.indentationLevel = level - 1
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        if menu.items.isEmpty { menu.addItem(withTitle: "No headings yet", action: nil, keyEquivalent: "") }
        if let view = window?.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: 95, y: view.bounds.height - 5), in: view)
        }
    }

    @objc private func jumpToHeading(_ sender: NSMenuItem) {
        let lines = editor.string.components(separatedBy: "\n")
        let location = lines.prefix(sender.tag).reduce(0) { $0 + ($1 as NSString).length + 1 }
        editor.setSelectedRange(NSRange(location: location, length: 0))
        handlingScroll = true
        editor.scrollRangeToVisible(NSRange(location: location, length: 0))
        handlingScroll = false
        preview.jump(to: sender.tag)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showEditor(_:)): menuItem.state = mode == .editor ? .on : .off
        case #selector(showPreview(_:)): menuItem.state = mode == .preview ? .on : .off
        case #selector(showSplit(_:)): menuItem.state = mode == .split ? .on : .off
        case #selector(toggleSync(_:)): menuItem.state = synced ? .on : .off; return mode == .split
        case #selector(zoomIn(_:)): return zoom < 2
        case #selector(zoomOut(_:)): return zoom > 0.7
        default: break
        }
        return true
    }
}
