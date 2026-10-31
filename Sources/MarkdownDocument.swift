import AppKit
import UniformTypeIdentifiers

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    private var content = MarkdownContent()
    var markdown: String {
        get { content.text }
        set { content.text = newValue }
    }
    override class var autosavesInPlace: Bool { true }

    override init() {
        super.init()
        fileType = "net.daringfireball.markdown"
    }

    override func makeWindowControllers() {
        let controller = DocumentWindowController(document: self)
        addWindowController(controller)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        content = try MarkdownContent(data: data)
        // NSDocument calls read again when reverting or accepting an external update.
        for case let controller as DocumentWindowController in windowControllers {
            controller.reloadDocument()
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        content.data()
    }

    override var fileURL: URL? {
        didSet {
            for case let controller as DocumentWindowController in windowControllers { controller.fileLocationChanged() }
        }
    }
}
