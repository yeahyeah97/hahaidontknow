import Foundation

enum TextContext {
    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "’"
    }

    static func currentWord(in text: String) -> String? {
        let word = String(text.suffix(while: isWordCharacter))
        return word.contains(where: { $0.isLetter }) ? word : nil
    }

    static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !isWordCharacter($0) })
            .map(String.init).filter { $0.contains(where: { $0.isLetter }) }
    }

    static func previousWord(in text: String) -> String? {
        let tokens = words(in: text)
        return currentWord(in: text) == nil ? tokens.last : tokens.dropLast().last
    }

    static func matchCase(_ value: String, source: String) -> String {
        if source.count > 1 && source == source.uppercased() {
            return value.uppercased()
        }
        if source.first?.isUppercase == true {
            return value.prefix(1).uppercased() + value.dropFirst()
        }
        return value
    }
}
