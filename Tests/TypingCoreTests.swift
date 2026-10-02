import Foundation

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
        print("Typing core regression checks passed")
    }
}
