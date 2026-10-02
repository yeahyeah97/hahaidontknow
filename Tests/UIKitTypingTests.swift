import XCTest
import UIKit

private final class TypingProxy: NSObject, UITextDocumentProxy {
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

@MainActor
final class UIKitTypingTests: XCTestCase {
    private func controller(_ proxy: TypingProxy) throws -> KeyboardViewController {
        let vocabulary = try XCTUnwrap(SpellVocabulary.load(directory: Bundle.main.resourceURL!))
        let suite = "milazy.integration." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let controller = KeyboardViewController()
        controller.predictionEngine = PredictionEngine(vocabulary: vocabulary, defaults: defaults)
        controller.testingProxy = proxy
        controller.loadViewIfNeeded()
        proxy.onInsert = { [weak controller] in controller?.textDidChange(nil) }
        return controller
    }

    private func press(_ text: String, on controller: KeyboardViewController) throws {
        for character in text {
            let key = try XCTUnwrap(controller.keyCanvas.subviews.compactMap { $0 as? TouchKey }
                .first { character == " " ? $0.referenceRole == .space :
                    $0.learningKey == String(character).lowercased() })
            key.sendActions(for: .touchDown)
        }
    }

    func testFastItalianSpaceWithoutWaitingForPredictions() throws {
        let proxy = TypingProxy("")
        let controller = try controller(proxy)
        try press("osa far vediam ", on: controller)
        XCTAssertEqual(proxy.text, "Cosa fare vediamo ")
    }

    func testFirstCapitalizedWordCorrectsOnSpace() throws {
        let proxy = TypingProxy("")
        let controller = try controller(proxy)
        try press("vediam ", on: controller)
        XCTAssertEqual(proxy.text, "Vediamo ")
    }

    func testLettersDoNotReadHostContextOrIdentifier() throws {
        let proxy = TypingProxy("ciao ")
        let controller = try controller(proxy)
        proxy.beforeReads = 0
        proxy.identifierReads = 0
        try press("abcdefghijklmnopqrstuv", on: controller)
        XCTAssertEqual(proxy.text, "ciao abcdefghijklmnopqrstuv")
        XCTAssertEqual(proxy.beforeReads, 0, "No host context round-trip per character")
        XCTAssertEqual(proxy.identifierReads, 0, "No document round-trip per character")
    }

    func testGapHitboxIsAcceptedByTheControl() {
        let key = TouchKey(type: .system)
        key.frame = CGRect(x: 0, y: 0, width: 37, height: 45)
        XCTAssertTrue(key.point(inside: CGPoint(x: -3, y: 22), with: nil))
        XCTAssertFalse(key.point(inside: CGPoint(x: -40, y: 22), with: nil))
    }

    func testCorrectionUndoProtectsOriginalImmediately() throws {
        let proxy = TypingProxy("")
        let controller = try controller(proxy)
        try press("osa ", on: controller)
        XCTAssertEqual(proxy.text, "Cosa ")
        let delete = try XCTUnwrap(controller.keyCanvas.subviews.compactMap { $0 as? TouchKey }
            .first { $0.referenceRole == .delete })
        delete.sendActions(for: .touchDown)
        XCTAssertEqual(proxy.text, "Osa")
        try press(" ", on: controller)
        XCTAssertEqual(proxy.text, "Osa ")
    }
}
