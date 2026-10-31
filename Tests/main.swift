import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}

for original in ["", "# Hello", "# Hello\n\nWorld\n", "# Hello\r\n\r\nWorld\r\n", "# Hello\rWorld\r", "\u{feff}# BOM\r\n", "# नमस्ते 👋\n你好 café\n"] {
    let bytes = Data(original.utf8)
    let content = try MarkdownContent(data: bytes)
    check(content.data() == bytes, "Exact UTF-8 round trip: \(original.debugDescription)")
    check(!content.text.contains("\r"), "Editor uses normalized line endings")
    check(!content.text.hasPrefix("\u{feff}"), "BOM is hidden in editor")
}

var crlf = try MarkdownContent(data: Data("# Title\r\nOriginal\r\n".utf8))
crlf.text = "# Title\nEdited 👋\n"
check(crlf.data() == Data("# Title\r\nEdited 👋\r\n".utf8), "Edits retain original CRLF convention")

var bom = try MarkdownContent(data: Data("\u{feff}Original".utf8))
bom.text = "Edited"
check(bom.data() == Data("\u{feff}Edited".utf8), "BOM retained on save")

do {
    _ = try MarkdownContent(data: Data([0xff, 0xfe, 0x80]))
    fatalError("Invalid UTF-8 should fail")
} catch {
    check((error as NSError).code == NSFileReadInapplicableStringEncodingError, "Invalid UTF-8 is rejected without data loss")
}

let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("slate-test-\(UUID().uuidString).md")
defer { try? FileManager.default.removeItem(at: scratch) }
try crlf.data().write(to: scratch, options: .atomic)
let reopened = try MarkdownContent(data: Data(contentsOf: scratch))
check(reopened.text == crlf.text, "Saved file reopens with edited contents")
check(reopened.lineEnding == "\r\n", "Reopened file retains line endings")

let large = String(repeating: "## Section\n\nSome **content** and 👋.\n", count: 30_000)
let largeContent = try MarkdownContent(data: Data(large.utf8))
check(largeContent.text == large, "Large document round trip")
print("File handling: \(checks) checks passed (UTF-8, Unicode, BOM, LF/CRLF/CR, edits, atomic save, reopen, and large files).")
