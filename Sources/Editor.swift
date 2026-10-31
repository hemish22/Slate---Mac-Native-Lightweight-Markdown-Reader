import AppKit

final class MarkdownTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [.font: Theme.mono(font?.pointSize ?? 13), .foregroundColor: Theme.muted.withAlphaComponent(0.55)]
            ("# A little space to think" as NSString).draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height), withAttributes: attributes)
        }
    }

    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let line = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let prefix = text.substring(with: NSRange(location: line.location, length: selectedRange().location - line.location))
        let indentation = String(prefix.prefix(while: { $0 == " " || $0 == "\t" }))
        super.insertNewline(sender)
        if !indentation.isEmpty { insertText(indentation, replacementRange: selectedRange()) }
    }
}

final class LineNumberRuler: NSRulerView {
    weak var editor: NSTextView?
    init(scrollView: NSScrollView, editor: NSTextView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = 48
        if #available(macOS 14.0, *) { clipsToBounds = true }
    }
    required init(coder: NSCoder) { fatalError() }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // Modern AppKit can provide a dirty rect outside the ruler's bounds.
        // Clip every draw so the gutter cannot cover the editor or pane header.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        Theme.background.setFill()
        bounds.fill()
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        let text = editor.string as NSString
        let visible = layout.glyphRange(forBoundingRect: editor.visibleRect.offsetBy(dx: -editor.textContainerOrigin.x, dy: -editor.textContainerOrigin.y), in: container)
        let chars = layout.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
        let firstLine = text.lineRange(for: NSRange(location: min(chars.location, text.length), length: 0))
        var number = text.substring(to: firstLine.location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        var index = firstLine.location
        let selected = editor.selectedRange().location
        let selectedLine = text.lineRange(for: NSRange(location: min(selected, text.length), length: 0))
        while index <= min(NSMaxRange(chars), text.length) {
            if index == text.length && text.length > 0 && text.character(at: text.length - 1) != 10 { break }
            let glyph = layout.glyphIndexForCharacter(at: index)
            let lineRect: NSRect
            if index == text.length && (text.length == 0 || text.character(at: text.length - 1) == 10) {
                lineRect = layout.extraLineFragmentRect
            } else {
                lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let y = lineRect.minY + editor.textContainerOrigin.y - editor.visibleRect.minY
            let label = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Theme.mono(max(10, (editor.font?.pointSize ?? 13) - 1)),
                .foregroundColor: index == selectedLine.location ? Theme.text : Theme.muted.withAlphaComponent(0.65)
            ]
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 12, y: y), withAttributes: attributes)
            if index == text.length { break }
            index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
            number += 1
        }
    }
}

final class SyntaxHighlighter {
    private struct Rule {
        let regex: NSRegularExpression
        let color: NSColor
    }
    private let rules: [Rule] = [
        ("(?m)^#{1,6} .+$", Theme.accent),
        ("(?m)^\\s*>.*$", Theme.muted),
        ("(?m)^\\s*(?:[-+*]|\\d+[.)])\\s", Theme.accent),
        ("!?\\[[^\\]\\n]*\\]\\([^\\n)]*\\)", NSColor(hex: 0x83b3f0)),
        ("(?<!\\*)\\*\\*[^\\n]+?\\*\\*(?!\\*)|__[^\\n]+?__", NSColor(hex: 0xffbb75)),
        ("(?<!\\*)\\*[^*\\n]+?\\*(?!\\*)|(?<!_)_[^_\\n]+?_(?!_)", NSColor(hex: 0xe4c2ff)),
        ("`[^`\\n]+`", Theme.green),
        ("(?ms)^```[^\\n]*\\n.*?^```\\s*$|^~~~[^\\n]*\\n.*?^~~~\\s*$", Theme.green),
        ("(?m)^\\s*(?:---+|___+|\\*\\*\\*+)\\s*$", Theme.muted)
    ].compactMap { pattern, color in
        try? Rule(regex: NSRegularExpression(pattern: pattern), color: color)
    }

    func highlight(_ editor: NSTextView) {
        guard let storage = editor.textStorage else { return }
        let range = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: Theme.text, range: range)
        // Keep large files responsive; rendering and editing still work at any size.
        if storage.length < 500_000 {
            let string = storage.string
            for rule in rules {
                rule.regex.enumerateMatches(in: string, range: range) { match, _, _ in
                    if let match { storage.addAttribute(.foregroundColor, value: rule.color, range: match.range) }
                }
            }
        }
        storage.endEditing()
    }
}
