import AppKit

enum Theme {
    static let background = NSColor(hex: 0x272934)
    static let chrome = NSColor(hex: 0x1e1f27)
    static let border = NSColor(hex: 0x3c3e4b)
    static let text = NSColor(hex: 0xe7e7ee)
    static let muted = NSColor(hex: 0x9295a8)
    static let accent = NSColor(hex: 0xc099ff)
    static let green = NSColor(hex: 0x80d9a4)
    static func mono(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
    static func label(_ text: String, size: CGFloat = 11, color: NSColor = muted) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                  blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

final class ColorView: NSView {
    init(_ color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

extension NSView {
    func pin(to parent: NSView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }
}
