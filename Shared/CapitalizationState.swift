import Foundation

struct CapitalizationState {
    enum Mode { case none, words, sentences, allCharacters }
    private enum Override { case automatic, once, lowercase, locked }
    private var manual: Override = .automatic

    mutating func toggle(currentlyUppercase: Bool, lock: Bool = false) {
        manual = lock ? .locked : (currentlyUppercase ? .lowercase : .once)
    }

    mutating func consumedLetter() {
        if manual != .locked { manual = .automatic }
    }

    mutating func reset() { manual = .automatic }

    func uppercase(context: String?, mode: Mode, current: Bool) -> Bool {
        switch manual {
        case .once, .locked: return true
        case .lowercase: return false
        case .automatic: break
        }
        switch mode {
        case .none: return false
        case .allCharacters: return true
        case .words:
            guard let context else { return current }
            return context.last.map { !TextContext.isWordCharacter($0) } ?? true
        case .sentences:
            guard let context else { return current }
            if context.isEmpty || context.hasSuffix("\n") { return true }
            guard context.last?.isWhitespace == true else { return false }
            let trimmed = context.reversed().drop(while: { $0.isWhitespace })
                .drop(while: { "\"'’”)]}".contains($0) })
            return trimmed.first.map { ".!?".contains($0) } ?? true
        }
    }
}
