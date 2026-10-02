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
    private var vocabulary = CorrectionIndex.fallback
    private var spellingCache: [String: (valid: Bool, guesses: [String])] = [:]
    private var lastLanguageSample = ""
    private var language = BilingualLanguageState()
    private var lexicon: [(String, String)] = []
    private var validWords: [KeyboardPreferences.LanguageMode: Set<String>] = [:]
    private var workerIndex: CorrectionIndex
    private var uiIndex: CorrectionIndex
    private var pendingRequest: DispatchWorkItem?
    private var pendingSave: DispatchWorkItem?
    private var document: UUID?
    private var rejected: Set<String> = []
    private var uiSpellings: [String: (valid: Bool, guesses: [String])] = [:]
    private final class Ticket {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    }
    private var currentTicket: Ticket?

    init(vocabulary supplied: SpellVocabulary? = nil, defaults: UserDefaults = .standard) {
        let model = LocalLanguageModel(defaults: defaults)
        self.model = model
        let vocabulary = supplied ?? CorrectionIndex.fallback
        self.vocabulary = vocabulary
        let index = CorrectionIndex(personal: model.snapshot(), mode: .automatic, vocabulary: vocabulary)
        workerIndex = index
        uiIndex = index
        worker.async {
            guard supplied == nil, let directory = Bundle.main.resourceURL else { return }
            if let loaded = SpellVocabulary.load(directory: directory) {
                self.vocabulary = loaded
                self.rebuildIndex(mode: .automatic)
            }
        }
    }

    func localCorrection(for word: String, previous: String?,
                         mode: KeyboardPreferences.LanguageMode) -> String? {
        guard uiIndex.mode == mode, !rejected.contains(word.lowercased()) else { return nil }
        let key = mode.rawValue + ":" + word.lowercased()
        if let intentional = uiIndex.intentionalReplacement(for: word) { return intentional }
        if uiSpellings[key]?.valid == true && uiIndex.dictionaryFrequency(of: word) == 0 { return nil }
        return uiIndex.correction(for: word, previous: previous,
                                  systemGuesses: uiSpellings[key]?.guesses ?? [])
    }

    func installLexicon(_ entries: [(String, String)], mode: KeyboardPreferences.LanguageMode) {
        worker.async { self.lexicon = entries; self.rebuildIndex(mode: mode) }
    }

    func learn(word: String, previous: String?, mode: KeyboardPreferences.LanguageMode,
               selectedFrom: String? = nil, rejectedCorrection: Bool = false) {
        if rejectedCorrection { rejected.insert(word.lowercased()) }
        worker.async {
            if rejectedCorrection { self.model.rejectCorrection(for: word) }
            else { self.model.learn(word: word, previous: previous, confirmed: selectedFrom != nil) }
            if let selectedFrom { self.model.learnCorrection(from: selectedFrom, to: word) }
            self.rebuildIndex(mode: mode)
            self.scheduleSave()
        }
    }

    private func rebuildIndex(mode: KeyboardPreferences.LanguageMode) {
        let index = CorrectionIndex(personal: model.snapshot(), mode: mode,
                                    lexicon: lexicon, validSystemWords: validWords[mode] ?? [], vocabulary: vocabulary)
        workerIndex = index
        DispatchQueue.main.async {
            let retired = self.uiIndex
            self.uiIndex = index
            // Large old personal snapshots are released on the worker.
            self.worker.async { withExtendedLifetime(retired) {} }
        }
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

    func cancel() {
        currentTicket?.cancel()
        pendingRequest?.cancel()
        pendingRequest = nil
    }

    func request(context: String, document: UUID, mode: KeyboardPreferences.LanguageMode,
                 completion: @escaping (Result) -> Void) {
        cancel()
        let ticket = Ticket()
        currentTicket = ticket
        let request = DispatchWorkItem { [weak self] in
            guard let self, !ticket.isCancelled else { return }
            if self.document != document {
                self.language = BilingualLanguageState()
                self.lastLanguageSample = ""
                self.document = document
            }
            if self.workerIndex.mode != mode { self.rebuildIndex(mode: mode) }
            guard let result = self.predict(context: context, mode: mode, ticket: ticket) else { return }
            DispatchQueue.main.async {
                guard !ticket.isCancelled else { return }
                completion(result)
            }
        }
        pendingRequest = request
        worker.asyncAfter(deadline: .now() + 0.015, execute: request)
    }

    private func predict(context: String, mode: KeyboardPreferences.LanguageMode, ticket: Ticket) -> Result? {
        let completed = context.last?.isWhitespace == true
            ? context : String(context.dropLast(TextContext.currentWord(in: context)?.count ?? 0))
        if completed != lastLanguageSample {
            lastLanguageSample = completed
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = [.italian, .english]
            recognizer.processString(String(completed.suffix(240)))
            let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
            _ = language.observe(context, italianConfidence: hypotheses[.italian] ?? 0,
                                 englishConfidence: hypotheses[.english] ?? 0)
        }
        guard !ticket.isCancelled else { return nil }
        let automatic = language.dominant
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

        let cacheKey = mode.rawValue + ":" + source.lowercased()
        if let cached = spellingCache[cacheKey] {
            validInEither = cached.valid
            for (index, word) in cached.guesses.enumerated() { add(word, 130 - Double(index * 3)) }
            guesses = cached.guesses.map { ($0, 130) }
        } else {
            let available = UITextChecker.availableLanguages
            var cachedGuesses: [String] = []
            for (position, language) in languages.enumerated() {
                guard !ticket.isCancelled else { return nil }
                let prefix = language == .italian ? "it" : "en"
                guard let identifier = available.first(where: { $0 == language.rawValue })
                    ?? available.first(where: { $0.hasPrefix(prefix) }) else { continue }
                let misspelled = checker.rangeOfMisspelledWord(in: source, range: range,
                    startingAt: 0, wrap: false, language: identifier)
                if misspelled.location == NSNotFound { validInEither = true }
                else {
                    let values = checker.guesses(forWordRange: misspelled, in: source,
                                                 language: identifier) ?? []
                    for (index, word) in values.prefix(6).enumerated() {
                        add(word, 130 - Double(index * 3 + position * 2))
                        if !cachedGuesses.contains(word) { cachedGuesses.append(word) }
                    }
                }
                let completions = checker.completions(forPartialWordRange: range, in: source,
                                                      language: identifier) ?? []
                for (index, word) in completions.prefix(4).enumerated() {
                    add(word, 115 - Double(index * 3 + position * 2))
                }
            }
            spellingCache[cacheKey] = (validInEither, Array(cachedGuesses.prefix(8)))
            if spellingCache.count > 512 { spellingCache = [cacheKey: spellingCache[cacheKey]!] }
            let spelling = spellingCache[cacheKey]!
            guesses = spelling.guesses.map { ($0, 130) }
            DispatchQueue.main.async {
                self.uiSpellings[cacheKey] = spelling
                if self.uiSpellings.count > 512 { self.uiSpellings = [cacheKey: spelling] }
            }
        }
        if validInEither {
            // Only publish a small exact-word set; the immutable corpus is shared.
            validWords[mode, default: []].insert(source.lowercased())
            if validWords[mode, default: []].count > 4096 { validWords[mode] = [source.lowercased()] }
            workerIndex.markValid(source)
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
        let protected = workerIndex.protects(source)
        if protected { add(source, 210) }
        workerIndex.dominant = primary
        guard !ticket.isCancelled else { return nil }
        let correction = workerIndex.correction(for: source, previous: previous,
                                                systemGuesses: guesses.map { $0.0 })
        if let correction { add(correction, 185) }
        let ranked = scores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        var choices = ranked.prefix(2).compactMap { display[$0.key] }
        if !choices.contains(source) { choices.append(source) }
        else if let third = ranked.dropFirst(2).first.flatMap({ display[$0.key] }) { choices.append(third) }
        return Result(context: context, choices: Array(choices.prefix(3)),
                      correction: correction, language: primary)
    }
}
