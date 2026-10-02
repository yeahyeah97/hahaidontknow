import UIKit
import NaturalLanguage

// Spellchecker, recognition, ranking and persistence are confined to one worker.
// The UI receives immutable snapshots and never waits for a worker.
final class PredictionEngine {
    struct Result {
        let context: String
        let choices: [String]
        let correction: String?
        let language: BilingualLanguageState.Language
    }
    private let worker = DispatchQueue(label: "milazy.prediction", qos: .userInitiated)
    private let model: LocalLanguageModel
    private let checker = UITextChecker()
    private var language = BilingualLanguageState()
    private var lexicon: [(String, String)] = []
    private var validWords: [KeyboardPreferences.LanguageMode: Set<String>] = [:]
    private var workerIndex: CorrectionIndex
    private var uiIndex: CorrectionIndex
    private var pendingRequest: DispatchWorkItem?
    private var pendingSave: DispatchWorkItem?
    private var document: UUID?
    private var rejected: Set<String> = []

    init() {
        let model = LocalLanguageModel()
        self.model = model
        let index = CorrectionIndex(personal: model.snapshot(), mode: .automatic)
        workerIndex = index
        uiIndex = index
    }

    func localCorrection(for word: String, previous: String?,
                         mode: KeyboardPreferences.LanguageMode) -> String? {
        guard uiIndex.mode == mode, !rejected.contains(word.lowercased()) else { return nil }
        return uiIndex.correction(for: word, previous: previous)
    }

    func installLexicon(_ entries: [(String, String)], mode: KeyboardPreferences.LanguageMode) {
        worker.async { self.lexicon = entries; self.rebuildIndex(mode: mode) }
    }

    func learn(word: String, previous: String?, mode: KeyboardPreferences.LanguageMode,
               selectedFrom: String? = nil, rejectedCorrection: Bool = false) {
        if rejectedCorrection { rejected.insert(word.lowercased()) }
        worker.async {
            if rejectedCorrection { self.model.rejectCorrection(for: word) }
            else { self.model.learn(word: word, previous: previous) }
            if let selectedFrom { self.model.learnCorrection(from: selectedFrom, to: word) }
            self.rebuildIndex(mode: mode)
            self.scheduleSave()
        }
    }

    private func rebuildIndex(mode: KeyboardPreferences.LanguageMode) {
        let index = CorrectionIndex(personal: model.snapshot(), mode: mode,
                                    lexicon: lexicon, validSystemWords: validWords[mode] ?? [])
        workerIndex = index
        DispatchQueue.main.async { self.uiIndex = index }
    }

    private func scheduleSave() {
        guard pendingSave == nil else { return }
        let save = DispatchWorkItem { self.model.persist(); self.pendingSave = nil }
        pendingSave = save
        worker.asyncAfter(deadline: .now() + 0.35, execute: save)
    }

    func flushLearning() {
        worker.async {
            self.pendingSave?.cancel()
            self.pendingSave = nil
            self.model.persist()
        }
    }

    func cancel() { pendingRequest?.cancel(); pendingRequest = nil }

    func request(context: String, document: UUID, mode: KeyboardPreferences.LanguageMode,
                 completion: @escaping (Result) -> Void) {
        cancel()
        let request = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.document != document {
                self.language = BilingualLanguageState()
                self.document = document
            }
            if self.workerIndex.mode != mode { self.rebuildIndex(mode: mode) }
            let result = self.predict(context: context, mode: mode)
            DispatchQueue.main.async { completion(result) }
        }
        pendingRequest = request
        worker.asyncAfter(deadline: .now() + 0.015, execute: request)
    }

    private func predict(context: String, mode: KeyboardPreferences.LanguageMode) -> Result {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.italian, .english]
        recognizer.processString(String(context.suffix(240)))
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        let automatic = language.observe(context, italianConfidence: hypotheses[.italian] ?? 0,
                                         englishConfidence: hypotheses[.english] ?? 0)
        let primary: BilingualLanguageState.Language = mode == .italian ? .italian :
            (mode == .english ? .english : automatic)
        let languages = mode == .automatic
            ? [primary, primary == .italian ? .english : .italian] : [primary]
        let personal = model.snapshot()
        let previous = TextContext.previousWord(in: context)
        guard let source = TextContext.currentWord(in: context) else {
            var choices = personal.nextWords(after: previous, limit: 3)
            let fallback = primary == .italian ? ["Ciao", "Non", "Io"] : ["I", "The", "You"]
            for value in fallback where !choices.contains(value) { choices.append(value) }
            return Result(context: context, choices: Array(choices.prefix(3)),
                          correction: nil, language: primary)
        }
        let range = NSRange(location: 0, length: source.utf16.count)
        var scores: [String: Double] = [source.lowercased(): 105]
        var display: [String: String] = [source.lowercased(): source]
        var guesses: [(String, Double)] = []
        var validInEither = false
        func add(_ word: String, _ base: Double) {
            let key = word.lowercased()
            let score = base + Double(personal.frequency(of: key)) * 2
                + Double(personal.contextFrequency(key, previous: previous)) * 6
            scores[key] = max(scores[key] ?? -Double.infinity, score)
            display[key] = TextContext.matchCase(word, source: source)
        }

        let available = UITextChecker.availableLanguages
        for (position, language) in languages.enumerated() {
            let prefix = language == .italian ? "it" : "en"
            guard let identifier = available.first(where: { $0 == language.rawValue })
                ?? available.first(where: { $0.hasPrefix(prefix) }) else { continue }
            let misspelled = checker.rangeOfMisspelledWord(in: source, range: range,
                startingAt: 0, wrap: false, language: identifier)
            let bonus = position == 0 ? 8.0 : 0
            if misspelled.location == NSNotFound { validInEither = true }
            else {
                let values = checker.guesses(forWordRange: misspelled, in: source,
                                             language: identifier) ?? []
                for (index, word) in values.prefix(6).enumerated() {
                    let distance = CorrectionIndex.editDistance(source.lowercased(), word.lowercased())
                    let score = 120 + bonus - Double(index * 4 + distance * 16)
                    add(word, score)
                    if distance <= 1 { guesses.append((word, score)) }
                }
            }
            let completions = checker.completions(forPartialWordRange: range, in: source,
                                                  language: identifier) ?? []
            for (index, word) in completions.prefix(6).enumerated() {
                add(word, 110 + bonus - Double(index * 3))
            }
        }
        if validInEither {
            validWords[mode, default: []].insert(source.lowercased())
            if validWords[mode, default: []].count > 4096 { validWords[mode] = [source.lowercased()] }
            workerIndex.markValid(source)
            let index = workerIndex
            DispatchQueue.main.async { self.uiIndex = index }
            add(source, 160)
        }
        for word in personal.completions(prefix: source, previous: previous) { add(word, 165) }
        for (from, to) in lexicon.prefix(4096) {
            if from.lowercased() == source.lowercased() { add(to, 190) }
            else if to.lowercased().hasPrefix(source.lowercased()) { add(to, 170) }
        }
        for (word, count) in personal.corrections(for: source).prefix(5) {
            add(word, 195 + Double(min(count, 20) * 4))
        }
        let protected = personal.frequency(of: source) >= 2 || workerIndex.keeps(source)
        if protected { add(source, 210) }
        var correction = workerIndex.correction(for: source, previous: previous)
        if validInEither { correction = nil }
        if !protected && !validInEither && correction == nil && source.count >= 5
            && source.count <= 32 && source.first?.isUppercase != true
            && !source.contains(where: { $0.isNumber }) {
            let ranked = guesses.sorted { $0.1 > $1.1 }
            if let best = ranked.first {
                let other = ranked.first { $0.0.lowercased() != best.0.lowercased() }
                if other == nil || best.1 - other!.1 >= 8 {
                    correction = TextContext.matchCase(best.0, source: source)
                }
            }
        }
        if let correction { add(correction, 185) }
        let ranked = scores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        var choices = ranked.prefix(2).compactMap { display[$0.key] }
        if !choices.contains(source) { choices.append(source) }
        else if let third = ranked.dropFirst(2).first.flatMap({ display[$0.key] }) { choices.append(third) }
        return Result(context: context, choices: Array(choices.prefix(3)),
                      correction: correction, language: primary)
    }
}

