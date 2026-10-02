import UIKit

final class TypingProxy: NSObject, UITextDocumentProxy {
    var text: String
    var beforeReads = 0
    var identifierReads = 0
    var onInsert: (() -> Void)?
    private let id = UUID()
    var documentIdentifier: UUID { identifierReads += 1; return id }
    var documentContextBeforeInput: String? { beforeReads += 1; return text }
    var documentContextAfterInput: String? { "" }
    var documentInputMode: UITextInputMode? { nil }
    var selectedText: String? { nil }
    var hasText: Bool { !text.isEmpty }
    var autocapitalizationType: UITextAutocapitalizationType = .sentences
    var autocorrectionType: UITextAutocorrectionType = .yes
    var keyboardType: UIKeyboardType = .default
    var keyboardAppearance: UIKeyboardAppearance = .light
    var returnKeyType: UIReturnKeyType = .default
    init(_ text: String) { self.text = text }
    func insertText(_ value: String) { text += value; onInsert?() }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
}
