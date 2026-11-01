import AppKit
import WebKit

/// Renders Markdown in an offscreen preview using the light print styles,
/// then saves it as a paginated PDF or opens the system print panel.
final class PDFExporter: NSObject, WKNavigationDelegate {
    enum Output { case file(URL), printPanel }

    private let markdown: String
    private let title: String
    private let output: Output
    private let assets = DocumentAssets()
    private let webView: WKWebView
    // Printing needs the web view in a window; this one is never shown.
    private let host: NSWindow
    private weak var parent: NSWindow?
    private var completion: ((Bool) -> Void)?
    private static var running: [PDFExporter] = []
    /// The preview page to render with (replaceable in tests).
    static var pageURL = Bundle.main.url(forResource: "preview", withExtension: "html")

    /// Exports `markdown`. Relative images resolve inside `directory`.
    /// `completion` reports whether the PDF was written (or the job printed).
    @discardableResult
    static func run(markdown: String, directory: URL?, title: String, output: Output,
                    parent: NSWindow?, completion: ((Bool) -> Void)? = nil) -> PDFExporter {
        let exporter = PDFExporter(markdown: markdown, directory: directory, title: title, output: output, parent: parent)
        exporter.completion = completion
        running.append(exporter)
        exporter.start()
        return exporter
    }

    private init(markdown: String, directory: URL?, title: String, output: Output, parent: NSWindow?) {
        self.markdown = markdown
        self.title = title
        self.output = output
        self.parent = parent
        assets.directory = directory
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(assets, forURLScheme: "slate-asset")
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
        webView = WKWebView(frame: frame, configuration: configuration)
        host = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    private func start() {
        guard let url = Self.pageURL else { return finish(false) }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Render, drop the empty-document placeholder, and wait (briefly) for images.
        let script = """
        window.updateMarkdown(markdown);
        if (!markdown.trim()) document.getElementById('content').innerHTML = '';
        document.title = title;
        await Promise.all([...document.images].map(image => image.complete ? null :
          new Promise(done => { image.onload = image.onerror = done; setTimeout(done, 5000); })));
        return true;
        """
        webView.callAsyncJavaScript(script, arguments: ["markdown": markdown, "title": title], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            if case .failure = result { return self.finish(false) }
            self.print()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }

    // Links in an exported document stay inert while rendering.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }

    private func print() {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        if case .file(let url) = output {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        }
        let operation = webView.printOperation(with: info)
        operation.jobTitle = title
        operation.showsPrintPanel = { if case .printPanel = output { return true } else { return false } }()
        operation.showsProgressPanel = false
        // WebKit's print view starts with a zero frame and would print blank pages.
        operation.view?.frame = webView.bounds
        operation.runModal(for: parent ?? host, delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        // WebKit can end the job on a background thread; windows close on the main one.
        DispatchQueue.main.async { self.finish(success) }
    }

    private func finish(_ success: Bool) {
        let completion = self.completion
        self.completion = nil
        host.close()
        Self.running.removeAll { $0 === self }
        completion?(success)
    }
}
