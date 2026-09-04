import AppKit

protocol Clipboard: AnyObject {
    func copy(_ text: String)
}

final class NSPasteboardClipboard: Clipboard {
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
