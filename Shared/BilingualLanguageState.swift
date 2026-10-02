import Foundation

struct BilingualLanguageState {
    enum Language: String { case italian = "it_IT", english = "en_US" }
    private(set) var dominant: Language = .italian
    private var pending: Language?
    private var votes = 0
    private var lastSample = ""

    private static let italian = Set("ad alla anche ancora bene ciao che chi come con cosa da dai devo di dove è fai fare fatto gli hai ho il io la le lo mi mia mio nel nella non noi per perché più poi puoi qui quindi sei sì sono stai sto ti tu una vai voi vorrei".split(separator: " ").map(String.init))
    private static let english = Set("about also am and are as at be because but can do for from good have he hello hey how i if in is it just like me my not of on or so that the this to was we what when where who why with you your".split(separator: " ").map(String.init))

    mutating func observe(_ context: String, italianConfidence: Double = 0,
                          englishConfidence: Double = 0) -> Language {
        // Only completed words vote. Partial keystrokes and repeated host callbacks
        // cannot manufacture the consecutive evidence needed to change language.
        var tokens = TextContext.words(in: context)
        if TextContext.currentWord(in: context) != nil { tokens = Array(tokens.dropLast()) }
        let sample = tokens.suffix(8).joined(separator: " ").lowercased()
        guard sample != lastSample, !sample.isEmpty else { return dominant }
        lastSample = sample
        var it = 0.0, en = 0.0
        for token in tokens.suffix(8).map({ $0.lowercased() }) {
            if Self.italian.contains(token) { it += 3 }
            if Self.english.contains(token) { en += 3 }
            if token.contains(where: { "àèéìòù".contains($0) }) { it += 3 }
        }
        it += italianConfidence * 4
        en += englishConfidence * 4
        guard abs(it - en) >= 4 else { pending = nil; votes = 0; return dominant }
        let proposed: Language = it > en ? .italian : .english
        guard proposed != dominant else { pending = nil; votes = 0; return dominant }
        votes = proposed == pending ? votes + 1 : 1
        pending = proposed
        if votes >= 2 { dominant = proposed; pending = nil; votes = 0 }
        return dominant
    }
}


