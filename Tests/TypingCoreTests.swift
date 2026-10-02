import Foundation
import CoreGraphics

@main
enum TypingCoreTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }

    static func main() {
        expect(TextContext.currentWord(in: "ciao l'amico") == "l'amico", "Italian apostrophe token")
        expect(TextContext.currentWord(in: "don't") == "don't", "English contraction")
        expect(TextContext.previousWord(in: "ciao") == nil, "First token has no previous word")
        expect(TextContext.previousWord(in: "ciao mondo") == "ciao", "Previous token")
        expect(TextContext.matchCase("hello", source: "HELO") == "HELLO", "Caps correction")
        var caps = CapitalizationState()
        expect(caps.uppercase(context: "", mode: .sentences, current: false), "Sentence start")
        expect(caps.uppercase(context: "ciao!  ", mode: .sentences, current: false), "Multiple spaces")
        expect(caps.uppercase(context: "ciao.\" ", mode: .sentences, current: false), "Closing quote")
        expect(!caps.uppercase(context: "ciao ", mode: .sentences, current: true), "Mid sentence")
        expect(caps.uppercase(context: "hello ", mode: .words, current: false), "Word capitalization")
        expect(!caps.uppercase(context: "", mode: .none, current: true), "Host disables auto caps")
        caps.toggle(currentlyUppercase: false)
        expect(caps.uppercase(context: "ciao ", mode: .none, current: false), "Manual shift wins")
        caps.consumedLetter()
        expect(!caps.uppercase(context: "ciao ", mode: .none, current: true), "One-shot consumed")
        caps.toggle(currentlyUppercase: false, lock: true)
        caps.consumedLetter()
        expect(caps.uppercase(context: "ciao", mode: .none, current: false), "Caps lock persists")

        let suite = "milazy.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TouchLearningModel(defaults: defaults)
        let candidates = [
            TouchResolver.Candidate(id: 0, frame: CGRect(x: 0, y: 0, width: 40, height: 45), learningKey: "a"),
            TouchResolver.Candidate(id: 1, frame: CGRect(x: 46, y: 0, width: 40, height: 45), learningKey: "s"),
            TouchResolver.Candidate(id: 2, frame: CGRect(x: 0, y: 56, width: 50, height: 45), learningKey: nil)
        ]
        let expansion = CGSize(width: 8.5, height: 9)
        expect(TouchResolver.resolve(CGPoint(x: 20, y: 22), candidates: candidates,
                                     expansion: expansion, model: model) == 0, "Central tap stable")
        expect(TouchResolver.resolve(CGPoint(x: 47, y: 22), candidates: candidates,
                                     expansion: expansion, model: model) == 1, "Neighbor edge stable")
        expect(TouchResolver.resolve(CGPoint(x: 25, y: 78), candidates: candidates,
                                     expansion: expansion, model: model) == 2, "Special key stable")
        for _ in 0..<100 {
            model.record(key: "a", point: CGPoint(x: 27, y: 25), frame: candidates[0].frame)
        }
        model.flush()
        expect(TouchResolver.resolve(CGPoint(x: 20, y: 22), candidates: candidates,
                                     expansion: expansion, model: model) == 0, "Adaptation keeps center")
        let restored = TouchLearningModel(defaults: defaults)
        expect(restored.probabilityScore(for: "a", point: CGPoint(x: 27, y: 25), frame: candidates[0].frame)
               < restored.probabilityScore(for: "a", point: CGPoint(x: 6, y: 25), frame: candidates[0].frame),
               "Touch offsets persist")
        var language = BilingualLanguageState()
        expect(language.observe("hello how ") == .italian, "One sample cannot switch language")
        expect(language.observe("hello how ") == .italian, "Repeated callback cannot vote twice")
        expect(language.observe("hello how are you ") == .english, "Repeated English evidence switches")
        expect(language.observe("hello how are you ciao ") == .english, "Mixed word does not flap")

        let learned = LocalLanguageModel(defaults: defaults)
        let empty = learned.snapshot()
        var index = CorrectionIndex(personal: empty, mode: .automatic)
        expect(index.correction(for: "teh", previous: nil) == "the", "Immediate known typo")
        expect(index.correction(for: "perche", previous: nil) == "perché", "Immediate Italian accent")
        expect(index.correction(for: "helol", previous: nil) == "hello", "Local transposition")
        expect(index.correction(for: "ciao", previous: nil) == nil, "Valid Italian preserved")
        expect(index.correction(for: "hello", previous: nil) == nil, "Valid English preserved")
        expect(index.correction(for: "Milazy", previous: nil) == nil, "Unfamiliar name preserved")
        expect(index.correction(for: "boh", previous: nil) == nil, "Short slang preserved")
        index.markValid("improbable")
        expect(index.keeps("improbable"), "System exact words protected")

        learned.learn(word: "milazy", previous: "ciao")
        learned.learn(word: "milazy", previous: "ciao")
        learned.learnCorrection(from: "mialzy", to: "milazy")
        learned.persist()
        let restoredWords = LocalLanguageModel(defaults: defaults).snapshot()
        expect(restoredWords.frequency(of: "milazy") == 2, "Personal word persistence")
        expect(restoredWords.contextFrequency("milazy", previous: "ciao") == 2, "Bigram persistence")
        let personalIndex = CorrectionIndex(personal: restoredWords, mode: .automatic)
        expect(personalIndex.correction(for: "mialzy", previous: nil) == "milazy", "Selected correction persisted")
        expect(personalIndex.correction(for: "milazy", previous: nil) == nil, "Learned name protected")
        learned.rejectCorrection(for: "mialzy")
        let rejectedIndex = CorrectionIndex(personal: learned.snapshot(), mode: .automatic)
        expect(rejectedIndex.correction(for: "mialzy", previous: nil) == nil, "Undo keeps original")
        let lexicon = CorrectionIndex(personal: empty, mode: .automatic,
            lexicon: [("omw", "On my way"), ("Zyki", "Zyki")])
        expect(lexicon.correction(for: "omw", previous: nil) == "On my way", "Supplementary shortcut")
        expect(lexicon.correction(for: "Zyki", previous: nil) == nil, "Supplementary name")
        let italianOnly = CorrectionIndex(personal: empty, mode: .italian)
        expect(italianOnly.correction(for: "teh", previous: nil) == nil, "Forced language respected")

        let start = Date.timeIntervalSinceReferenceDate
        for _ in 0..<1000 {
            _ = index.correction(for: "helol", previous: nil)
        }
        let elapsed = Date.timeIntervalSinceReferenceDate - start
        expect(elapsed < 3, "Bounded Space decisions: 1000 calls within 3 seconds on CI")
        print("1000 local Space decisions: \(elapsed) seconds")
        expect(!SemanticFixRouting.needsDeepPass("I am tired.", verbCount: 1), "Simple English uses one request")
        expect(!SemanticFixRouting.needsDeepPass("Sono stanco.", verbCount: 1), "Simple Italian uses one request")
        expect(!SemanticFixRouting.needsDeepPass("Spero che tu stia bene.", verbCount: 2), "Grammatical wish uses one request")
        expect(!SemanticFixRouting.needsDeepPass("Mamma ha detto che mi chiamerà dopo il lavoro.", verbCount: 3), "Complete relationships use one request")
        expect(SemanticFixRouting.needsDeepPass("armadio porta arancione", verbCount: 0), "Noun fragment uses semantic map")
        expect(SemanticFixRouting.needsDeepPass("Marco no venire io andare se piove forse casa", verbCount: 3), "Fragmented conditional uses semantic map")
        expect(SemanticFixRouting.needsDeepPass("mamma telefono lei detto dopo lavoro chiamare", verbCount: 2), "Ambiguous actor uses semantic map")
        expect(SemanticFixRouting.needsDeepPass("Sicuramente Gian se spero sei forte spero zyki ha sconfitta va beneee", verbCount: 4), "Two fragmented hopes use semantic map")
        print("Typing core regression checks passed")
    }
}


