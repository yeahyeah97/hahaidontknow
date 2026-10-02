import XCTest
import UIKit

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
        controller.view.frame = CGRect(x: 0, y: 0, width: 440, height: 248)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        proxy.onInsert = { [weak controller] in controller?.textDidChange(nil) }
        return controller
    }

    private func press(_ text: String, on controller: KeyboardViewController) throws {
        for character in text {
            let key = try XCTUnwrap(controller.keyCanvas.subviews.compactMap { $0 as? TouchKey }
                .first { character == " " ? $0.referenceRole == .space :
                    $0.learningKey == String(character).lowercased() })
            let contact = UUID()
            XCTAssertTrue(controller.keyCanvas.beginContact(contact,
                at: CGPoint(x: key.frame.midX, y: key.frame.midY)))
            controller.keyCanvas.endContact(contact)
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
        XCTAssertTrue(controller.keyCanvas.beginContact(100,
            at: CGPoint(x: delete.frame.midX, y: delete.frame.midY)))
        controller.keyCanvas.endContact(100)
        XCTAssertEqual(proxy.text, "Osa")
        try press(" ", on: controller)
        XCTAssertEqual(proxy.text, "Osa ")
    }

    private func key(_ letter: String, in controller: KeyboardViewController) throws -> TouchKey {
        try XCTUnwrap(controller.keyCanvas.subviews.compactMap { $0 as? TouchKey }
            .first { $0.learningKey == letter })
    }

    func testMiddleRowOuterEdgesCannotLoseTaps() throws {
        let proxy = TypingProxy("ciao ")
        let controller = try controller(proxy)
        let canvas = controller.keyCanvas
        let a = try key("a", in: controller), l = try key("l", in: controller)
        let left = CGPoint(x: 1, y: a.frame.midY)
        let right = CGPoint(x: canvas.bounds.width - 1, y: l.frame.midY)
        XCTAssertTrue(canvas.hitTest(left, with: nil) === canvas)
        XCTAssertTrue(canvas.hitTest(right, with: nil) === canvas)
        XCTAssertTrue(canvas.beginContact(1, at: left))
        XCTAssertTrue(canvas.beginContact(2, at: right))
        canvas.endContact(2)
        canvas.endContact(1)
        XCTAssertEqual(proxy.text, "ciao al")
    }

    func testOverlappingContactsOnSameAndDifferentKeysRegisterExactlyOnce() throws {
        let proxy = TypingProxy("ciao ")
        let controller = try controller(proxy)
        let canvas = controller.keyCanvas
        let a = try key("a", in: controller), s = try key("s", in: controller)
        let first = CGPoint(x: a.frame.midX, y: a.frame.midY)
        let second = CGPoint(x: s.frame.midX, y: s.frame.midY)
        XCTAssertTrue(canvas.isMultipleTouchEnabled)
        XCTAssertTrue(canvas.beginContact(1, at: first))
        XCTAssertFalse(canvas.beginContact(1, at: first), "Duplicate begin cannot double-insert")
        XCTAssertTrue(canvas.beginContact(2, at: first), "A second finger on the same key registers")
        XCTAssertTrue(canvas.beginContact(3, at: second))
        canvas.moveContact(1, to: second)
        canvas.endContact(3)
        canvas.endContact(1)
        canvas.endContact(2)
        canvas.endContact(2)
        XCTAssertEqual(proxy.text, "ciao aas", "Move/release order never changes committed characters")
    }

    func testEveryVisibleCapAndRowGapRoutesAnInput() throws {
        let proxy = TypingProxy("ciao ")
        let controller = try controller(proxy)
        let canvas = controller.keyCanvas
        for (i, key) in canvas.subviews.compactMap({ $0 as? TouchKey }).enumerated()
            where key.learningKey != nil {
            for point in [CGPoint(x: key.frame.minX + 0.5, y: key.frame.minY + 0.5),
                          CGPoint(x: key.frame.maxX - 0.5, y: key.frame.maxY - 0.5)] {
                let previous = proxy.text
                XCTAssertTrue(canvas.beginContact(i, at: point))
                canvas.endContact(i)
                XCTAssertEqual(proxy.text, previous + key.learningKey!)
            }
        }
        let a = try key("a", in: controller), s = try key("s", in: controller)
        let gap = CGPoint(x: (a.frame.maxX + s.frame.minX) / 2, y: a.frame.midY)
        let before = proxy.text.count
        XCTAssertTrue(canvas.beginContact(999, at: gap))
        canvas.endContact(999)
        XCTAssertEqual(proxy.text.count, before + 1)
        XCTAssertFalse(canvas.beginContact(1000, at: CGPoint(x: -1, y: 20)))
        XCTAssertEqual(proxy.text.count, before + 1, "Outside the key canvas belongs to the system")
    }

    func testLayoutChangeAndCancellationCannotDuplicateCharacters() throws {
        let proxy = TypingProxy("ciao ")
        let controller = try controller(proxy)
        let canvas = controller.keyCanvas
        let a = try key("a", in: controller)
        XCTAssertTrue(canvas.beginContact(1, at: CGPoint(x: a.frame.midX, y: a.frame.midY)))
        controller.page = .numbers
        controller.rebuildKeys()
        controller.view.layoutIfNeeded()
        canvas.endContact(1)
        XCTAssertEqual(proxy.text, "ciao a")
        let one = try key("1", in: controller)
        XCTAssertTrue(canvas.beginContact(2, at: CGPoint(x: one.frame.midX, y: one.frame.midY)))
        canvas.endContact(2, cancelled: true)
        canvas.endContact(2)
        XCTAssertEqual(proxy.text, "ciao a1")
    }

    func testBackspaceContactRepeatsAndStopsOnRelease() async throws {
        let proxy = TypingProxy("abcdefghijklmnopqrst")
        let controller = try controller(proxy)
        let canvas = controller.keyCanvas
        let delete = try XCTUnwrap(canvas.subviews.compactMap { $0 as? TouchKey }
            .first { $0.referenceRole == .delete })
        XCTAssertTrue(canvas.beginContact(1, at: CGPoint(x: delete.frame.midX, y: delete.frame.midY)))
        XCTAssertEqual(proxy.text, "abcdefghijklmnopqrs", "Delete commits immediately once")
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertLessThan(proxy.text.count, 19, "Holding repeats")
        canvas.endContact(1)
        let released = proxy.text
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(proxy.text, released, "Release stops all repeat work")
    }
}
