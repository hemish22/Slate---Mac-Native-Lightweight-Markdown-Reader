import AppKit
import WebKit
import UniformTypeIdentifiers

// Only serve assets inside the current document's folder, including resolved symlinks.
final class DocumentAssets: NSObject, WKURLSchemeHandler {
    var directory: URL?
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let directory else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let relative = String(url.path.drop(while: { $0 == "/" }))
        let file = root.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file),
              let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType,
              mime.hasPrefix("image/"), mime != "image/svg+xml" else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile)); return
        }
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

final class PreviewController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    let assets = DocumentAssets()
    var onScroll: ((Double) -> Void)?
    var onReady: (() -> Void)?
    private var ready = false
    private var pendingMarkdown = ""
    private var pendingZoom = 1.0

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(assets, forURLScheme: "slate-asset")
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        // A weak forwarding handler prevents a WKUserContentController retain cycle.
        configuration.userContentController.add(WeakMessageHandler(self), name: "scroll")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = Theme.background
        if let url = Bundle.main.url(forResource: "preview", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func update(markdown: String) {
        pendingMarkdown = markdown
        guard ready else { return }
        webView.callAsyncJavaScript("window.updateMarkdown(markdown)", arguments: ["markdown": markdown], in: nil, in: .page) { _ in }
    }

    func setZoom(_ zoom: Double) {
        pendingZoom = zoom
        webView.pageZoom = zoom
    }

    func scroll(to fraction: Double) {
        guard ready else { return }
        webView.callAsyncJavaScript("window.scrollToFraction(fraction)", arguments: ["fraction": fraction], in: nil, in: .page) { _ in }
    }

    func jump(to line: Int) {
        guard ready else { return }
        webView.callAsyncJavaScript("window.jumpToLine(line)", arguments: ["line": line], in: nil, in: .page) { _ in }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        update(markdown: pendingMarkdown)
        setZoom(pendingZoom)
        onReady?()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let fraction = message.body as? Double { onScroll?(fraction) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        if url.isFileURL, url.path == webView.url?.path, url.fragment != nil {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        } else if url.scheme == "slate-asset", let directory = assets.directory {
            let root = directory.resolvingSymlinksInPath().standardizedFileURL
            let file = root.appendingPathComponent(String(url.path.drop(while: { $0 == "/" }))).resolvingSymlinksInPath().standardizedFileURL
            guard file.path.hasPrefix(root.path + "/"), ["md", "markdown", "mdown", "mkd", "mkdn"].contains(file.pathExtension.lowercased()) else { return }
            NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
    }
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
