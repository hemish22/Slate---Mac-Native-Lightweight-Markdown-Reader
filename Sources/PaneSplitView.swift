import AppKit

final class PaneSplitView: NSSplitView {
    var showsDivider = true {
        didSet {
            guard showsDivider != oldValue else { return }
            needsLayout = true
            // Invalidate the entire backing surface, including the previous seam.
            needsDisplay = true
        }
    }

    override var dividerThickness: CGFloat { showsDivider ? super.dividerThickness : 0 }
    override var dividerColor: NSColor { Theme.border }

    override func drawDivider(in rect: NSRect) {
        guard showsDivider else { return }
        dividerColor.setFill()
        rect.intersection(bounds).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        // A transparent split view can leave its old divider on the backing layer
        // when a pane is hidden. Clear that surface before drawing the new mode.
        Theme.background.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }
}
