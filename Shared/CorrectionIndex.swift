import Foundation

// A small original vocabulary supplements UITextChecker. It supplies immediate
// conservative decisions when the last asynchronous spellcheck has not finished.
struct CorrectionIndex {
    private static let italian = """
    a ad al alla allo alle ai agli anche ancora andare anno anni amico amica amici
    amore arrivare aspetta aspettare abbiamo bene buongiorno buonasera casa ciao che
    chi chiamare chiamato chiamo ci città come comprare con cosa cose così da dai dal
    dalla delle devo devi deve devono dire di dopo dove e è essere era ero ero eri
    erano fa fai fare fatto farò figlio figlia fine forse grazie già giorno giorni
    gli hai ha hanno ho il io la le lo loro lui lei lavoro lavorare ma mangiare
    mamma me meglio mi mia mie mio miei molto mondo ne nel nella niente no non noi
    oggi ok ora papà per perché però piacere piace più poi posso puoi può possiamo
    potrei prima problema qua qui quando quanto questo questa questi quello quella
    quindi ragazzo ragazza ragazzi ragazze resto sapere sei siamo siete sì si sono
    spero speriamo sta stai stanno stato stasera sto su subito te telefono tempo ti
    tra tu tutto tutti tua tuo un una uno va vai vado venire viene vengo vedere
    visto vita voglio vuole vorrei voi ieri domani mattina sera notte messaggio
    scuola università pranzo cena parlare scrivere hai bisogno paura felice forte
    chiusa chiuso aperta aperto porta armadio pacchi perde perso sconfitta
    """
    private static let english = """
    a about after again all also am an and another any are as ask at away back be
    because been before being best better big book both but buy by call called can
    cannot car case chat city close closed come coming could day days did do does
    doing done don't down each easy else even ever every fact family feel few find
    first fix food for found friend friends from get give go going good got great
    had happy has have he hello help her here him his home hope how i if in into
    is isn't it it's just keep know last late later leave left let life like little
    live long look lot love made make many may me mean message might more morning
    most mother much must my name need never new next nice night no not nothing now
    of off ok on once one only open or other our out over people phone place please
    possible probably put question read really right said same say school see send
    she should since small so some someone something soon sorry start stay still
    stop sure take talk tell text than thank thanks that the their them then there
    these they thing think this those through time to today together tomorrow too
    try two under until up us use very wait want was way we well were what when
    where which while who why will wish with without work world would write wrong
    yes yesterday yet you your you're lose lost afraid strong door package
    """
    private static let commonTypos = [
        "teh": "the", "thsi": "this", "thier": "their", "dont": "don't",
        "youre": "you're", "woudl": "would", "helo": "hello", "becuase": "because",
        "ciaoo": "ciao", "perche": "perché", "graziee": "grazie",
        "qunado": "quando", "qaundo": "quando", "buongirono": "buongiorno"
    ]

    private var vocabulary: Set<String>
    private var protectedWords: Set<String>
    private var signatures: [String: Set<String>] = [:]
    private var explicit: [String: String]
    private var learned: [String: String] = [:]
    private var personal: LocalLanguageModel.Snapshot
    private var validSystemWords: Set<String>
    let mode: KeyboardPreferences.LanguageMode

    init(personal: LocalLanguageModel.Snapshot, mode: KeyboardPreferences.LanguageMode,
         lexicon: [(String, String)] = [], validSystemWords: Set<String> = []) {
        self.personal = personal
        self.mode = mode
        self.validSystemWords = validSystemWords
        let raw = mode == .italian ? Self.italian : (mode == .english ? Self.english : Self.italian + " " + Self.english)
        let baseWords = Set(raw.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        vocabulary = baseWords
        protectedWords = Set(personal.words.filter { $0.value >= 2 }.keys)
        explicit = Self.commonTypos.filter { baseWords.contains($0.value) }
        for (input, output) in lexicon {
            if !input.isEmpty, !output.isEmpty {
                protectedWords.insert(output.lowercased())
                if input.lowercased() != output.lowercased() { explicit[input.lowercased()] = output }
                if !output.contains(where: { $0.isWhitespace }) { vocabulary.insert(output.lowercased()) }
            }
        }
        for (key, count) in personal.corrections.sorted(by: { $0.value > $1.value }) {
            let pair = key.components(separatedBy: "\u{1F}")
            if pair.count == 2, count > 0, learned[pair[0]] == nil { learned[pair[0]] = pair[1] }
        }
        // Keep all learned names protected, but cap the fuzzy index to limit
        // keyboard-extension memory. Long-tail names need no fuzzy signatures.
        vocabulary.formUnion(personal.words.filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }.prefix(512).map { $0.key })
        for word in vocabulary where word.count <= 32 {
            for signature in Self.deletions(word) { signatures[signature, default: []].insert(word) }
        }
    }

    static func deletions(_ word: String) -> Set<String> {
        let chars = Array(word)
        guard chars.count <= 32 else { return [] }
        var values: Set<String> = [word]
        for index in chars.indices {
            var copy = chars
            copy.remove(at: index)
            values.insert(String(copy))
        }
        return values
    }

    func keeps(_ word: String) -> Bool {
        let lower = word.lowercased()
        return vocabulary.contains(lower) || protectedWords.contains(lower) || validSystemWords.contains(lower)
    }

    func correction(for source: String, previous: String?) -> String? {
        let lower = source.lowercased()
        guard (3...32).contains(source.count), !source.contains(where: { $0.isNumber }),
              !protectedWords.contains(lower) else { return nil }
        // User selections and system text replacements are intentional even if the
        // source is a valid abbreviation. Repeatedly kept words remain protected.
        if let replacement = learned[lower] {
            return TextContext.matchCase(replacement, source: source)
        }
        if let replacement = explicit[lower] { return TextContext.matchCase(replacement, source: source) }
        guard !keeps(source), source.first?.isUppercase != true else { return nil }
        var candidates: Set<String> = []
        for signature in Self.deletions(lower) {
            candidates.formUnion(signatures[signature] ?? [])
            if candidates.count > 64 { return nil }
        }
        let scored: [(String, Double)] = candidates.compactMap { word in
            guard word != lower, Self.editDistance(lower, word) <= 1 else { return nil }
            let score = Double(personal.frequency(of: word)) * 2
                + Double(personal.contextFrequency(word, previous: previous)) * 6
            return (word, score)
        }
        let ranked = scored.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1
        }
        guard let best = ranked.first else { return nil }
        // Preserve short slang and ambiguous typos. Never guess arbitrarily on ties.
        guard lower.count >= 5 || best.1 >= 4 else { return nil }
        if ranked.count > 1 && best.1 - ranked[1].1 < 3 { return nil }
        return TextContext.matchCase(best.0, source: source)
    }

    mutating func markValid(_ word: String) {
        validSystemWords.insert(word.lowercased())
    }

    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= 2, max(a.count, b.count) <= 40 else { return 99 }
        var previous = Array(0...b.count)
        var beforePrevious = previous
        for i in a.indices {
            var row = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                row[j + 1] = min(row[j] + 1, previous[j + 1] + 1,
                                 previous[j] + (a[i] == b[j] ? 0 : 1))
                if i > 0 && j > 0 && a[i] == b[j - 1] && a[i - 1] == b[j] {
                    row[j + 1] = min(row[j + 1], beforePrevious[j - 1] + 1)
                }
            }
            beforePrevious = previous
            previous = row
        }
        return previous[b.count]
    }
}


