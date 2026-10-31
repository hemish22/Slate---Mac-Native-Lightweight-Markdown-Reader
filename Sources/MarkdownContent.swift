import Foundation

struct MarkdownContent {
    var text = ""
    private(set) var lineEnding = "\n"
    private(set) var hasBOM = false

    init() {}
    init(data: Data) throws {
        hasBOM = data.starts(with: [0xef, 0xbb, 0xbf])
        let bytes = hasBOM ? Data(data.dropFirst(3)) : data
        guard let decoded = String(data: bytes, encoding: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError,
                          userInfo: [NSLocalizedDescriptionKey: "This file is not UTF-8 text. Save it as UTF-8 and open it again."])
        }
        lineEnding = decoded.contains("\r\n") ? "\r\n" : decoded.contains("\r") ? "\r" : "\n"
        text = decoded.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    func data() -> Data {
        Data(((hasBOM ? "\u{feff}" : "") + text.replacingOccurrences(of: "\n", with: lineEnding)).utf8)
    }
}
