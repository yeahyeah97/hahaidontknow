import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Page { case letters, numbers, symbols, emoji }
    fileprivate enum KeyRole { case normal, shift, delete, mode, emoji, space, returnKey }

    private let predictionBar = UIStackView()
    private let keyCanvas = KeyCanvasView()
    private var page: Page = .letters
    private var shifted = true
    private var predictionButtons: [UIButton] = []
    private var laidOutKeys: [(TouchKey, CGRect)] = []
    private var cachedCorrection: (word: String, replacement: String)?
    private var predictionGeneration = 0

    private let letterRows = [
        ["Q","W","E","R","T","Y","U","I","O","P"],
        ["A","S","D","F","G","H","J","K","L"],
        ["Z","X","C","V","B","N","M"]
    ]
    private let numberRows = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["-","/",":",";","(",")","€","&","@","\""],
        [".",",","?","!","'"]
    ]
    private let symbolRows = [
        ["[","]","{","}","#","%","^","*","+","="],
        ["_","\\","|","~","<",">","$","£","¥","•"],
        [".",",","?","!","'"]
    ]
    private let emojiRows = [
        ["😀","😂","🥹","😍","🥰","😎","😭","😡","👍","❤️"],
        ["🤣","😊","😉","😘","🤔","😴","🤯","🙏","🔥","✨"],
        ["😅","😇","🙂","🙃","😋","😜","🤓","🥳","💀","💯"]
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 0, height: 255)
        let nativeHeight = view.heightAnchor.constraint(equalToConstant: 255)
        nativeHeight.priority = .required
        nativeHeight.isActive = true
        view.clipsToBounds = true
        buildChrome()
        rebuildKeys()
        updateAppearance()
        refreshPredictions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let referenceWidth: CGFloat = 440
        let sx = keyCanvas.bounds.width / referenceWidth
        for (button, reference) in laidOutKeys {
            button.frame = CGRect(
                x: reference.minX * sx,
                y: reference.minY,
                width: reference.width * sx,
                height: reference.height
            ).integral
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateReturnKey()
        updateAppearance()
        refreshPredictions()
    }

    private func buildChrome() {
        predictionBar.axis = .horizontal
        predictionBar.distribution = .fillEqually
        predictionBar.spacing = 0
        predictionBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(predictionBar)

        for index in 0..<3 {
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.font = .systemFont(ofSize: 17.5)
            button.titleEdgeInsets = UIEdgeInsets(top: -9, left: 0, bottom: 9, right: 0)
            button.addTarget(self, action: #selector(usePrediction(_:)), for: .touchUpInside)
            predictionButtons.append(button)
            predictionBar.addArrangedSubview(button)
        }

        let aiGesture = UILongPressGestureRecognizer(target: self, action: #selector(showAITools(_:)))
        predictionBar.addGestureRecognizer(aiGesture)

        keyCanvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyCanvas)

        NSLayoutConstraint.activate([
            predictionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            predictionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            predictionBar.topAnchor.constraint(equalTo: view.topAnchor),
            predictionBar.heightAnchor.constraint(equalToConstant: 35),

            keyCanvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyCanvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyCanvas.topAnchor.constraint(equalTo: predictionBar.bottomAnchor),
            keyCanvas.heightAnchor.constraint(equalToConstant: 213),
            keyCanvas.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
    }

    private func rebuildKeys() {
        keyCanvas.subviews.forEach { $0.removeFromSuperview() }
        laidOutKeys.removeAll()

        switch page {
        case .letters:
            buildLetters()
        case .numbers:
            buildNumbers(symbols: false)
        case .symbols:
            buildNumbers(symbols: true)
        case .emoji:
            buildEmoji()
        }
        updateReturnKey()
        updateAppearance()
        view.setNeedsLayout()
    }

    private func buildLetters() {
        let normalW: CGFloat = 37.33
        let keyH: CGFloat = 45
        let step: CGFloat = 43.33

        for (i, title) in letterRows[0].enumerated() {
            addKey(title, CGRect(x: 6.67 + CGFloat(i) * step, y: 0, width: normalW, height: keyH), #selector(characterKey(_:)))
        }

        for (i, title) in letterRows[1].enumerated() {
            addKey(title, CGRect(x: 28 + CGFloat(i) * step, y: 56, width: normalW, height: keyH), #selector(characterKey(_:)))
        }

        addKey("⇧", CGRect(x: 6.67, y: 112, width: 50, height: keyH), #selector(toggleShift), role: .shift)
        for (i, title) in letterRows[2].enumerated() {
            addKey(title, CGRect(x: 71.33 + CGFloat(i) * step, y: 112, width: normalW, height: keyH), #selector(characterKey(_:)))
        }
        addKey("⌫", CGRect(x: 383.33, y: 112, width: 50.33, height: keyH), #selector(backspaceDown), role: .delete)

        buildBottomRow(modeTitle: "123", spaceTitle: "")
    }

    private func buildNumbers(symbols: Bool) {
        let rows = symbols ? symbolRows : numberRows
        let normalW: CGFloat = 37.33
        let keyH: CGFloat = 45
        let step: CGFloat = 43.33

        for (i, title) in rows[0].enumerated() {
            addKey(title, CGRect(x: 6.67 + CGFloat(i) * step, y: 0, width: normalW, height: keyH), #selector(characterKey(_:)))
        }
        for (i, title) in rows[1].enumerated() {
            addKey(title, CGRect(x: 6.67 + CGFloat(i) * step, y: 56, width: normalW, height: keyH), #selector(characterKey(_:)))
        }

        addKey(symbols ? "123" : "#+=", CGRect(x: 6.67, y: 112, width: 50, height: keyH), #selector(toggleSymbols), role: .mode)
        let punctuationW: CGFloat = 54.67
        let punctuationX: [CGFloat] = [71.33, 132, 192.67, 253.33, 314]
        for (i, title) in rows[2].enumerated() {
            addKey(title, CGRect(x: punctuationX[i], y: 112, width: punctuationW, height: keyH), #selector(characterKey(_:)))
        }
        addKey("⌫", CGRect(x: 383.33, y: 112, width: 50.33, height: keyH), #selector(backspaceDown), role: .delete)

        buildBottomRow(modeTitle: "ABC", spaceTitle: "space")
    }

    private func buildEmoji() {
        let keyH: CGFloat = 45
        let normalW: CGFloat = 37.33
        let step: CGFloat = 43.33

        for row in 0..<3 {
            for (i, title) in emojiRows[row].enumerated() {
                addKey(title, CGRect(x: 6.67 + CGFloat(i) * step, y: CGFloat(row) * 56, width: normalW, height: keyH), #selector(characterKey(_:)))
            }
        }
        buildBottomRow(modeTitle: "ABC", spaceTitle: "space")
    }

    private func buildBottomRow(modeTitle: String, spaceTitle: String) {
        let y: CGFloat = 168
        let h: CGFloat = 45
        addKey(modeTitle, CGRect(x: 6.67, y: y, width: 48, height: h), #selector(toggleNumbers), role: .mode)
        addKey("☺", CGRect(x: 60.67, y: y, width: 48, height: h), #selector(emojiDown), role: .emoji)
        addKey(spaceTitle, CGRect(x: 114.67, y: y, width: 210.67, height: h), #selector(spaceDown), role: .space)
        addKey("↵", CGRect(x: 331.33, y: y, width: 102.33, height: h), #selector(returnDown), role: .returnKey)
    }

    private func addKey(_ title: String, _ frame: CGRect, _ action: Selector, role: KeyRole = .normal) {
        let button = TouchKey(type: .system)
        button.setTitle(title, for: .normal)
        button.referenceRole = role

        switch role {
        case .emoji:
            button.setTitle(nil, for: .normal)
            button.setImage(UIImage(systemName: "face.smiling"), for: .normal)
            button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .regular), forImageIn: .normal)
        case .delete:
            button.setTitle(nil, for: .normal)
            button.setImage(UIImage(systemName: "delete.left"), for: .normal)
            button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .regular), forImageIn: .normal)
        case .shift:
            button.setTitle(nil, for: .normal)
            button.setImage(UIImage(systemName: shifted ? "shift.fill" : "shift"), for: .normal)
            button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .regular), forImageIn: .normal)
        default:
            break
        }
        button.titleLabel?.font = .systemFont(ofSize: title.count == 1 ? 21 : 18)
        button.layer.cornerRadius = 8
        button.addTarget(self, action: action, for: .touchDown)

        if role == .delete {
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(backspaceHold(_:)))
            hold.minimumPressDuration = 0.32
            button.addGestureRecognizer(hold)
        }

        if role == .space && page == .letters {
            let badge = UILabel()
            badge.text = "IT EN"
            badge.font = .systemFont(ofSize: 11)
            badge.textColor = UIColor.white.withAlphaComponent(0.38)
            badge.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -5),
                badge.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -4)
            ])
        }

        keyCanvas.addSubview(button)
        laidOutKeys.append((button, frame))
    }

    private func updateReturnKey() {
        guard let button = laidOutKeys.map({ $0.0 }).first(where: { $0.referenceRole == .returnKey }) else { return }
        let type = textDocumentProxy.returnKeyType
        let title: String
        switch type {
        case .done: title = "✓"
        case .go: title = "Go"
        case .google: title = "Google"
        case .join: title = "Join"
        case .next: title = "Next"
        case .route: title = "Route"
        case .search: title = "Search"
        case .send: title = "Send"
        case .yahoo: title = "Yahoo"
        case .emergencyCall: title = "Emergency"
        case .continue: title = "Continue"
        default: title = "↵"
        }
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: title.count == 1 ? 24 : 16, weight: .regular)
    }

    private func updateAppearance() {
        let dark = textDocumentProxy.keyboardAppearance == .dark || traitCollection.userInterfaceStyle == .dark
        let keyColor = dark ? UIColor(white: 67.0 / 255.0, alpha: 1) : .white
        view.backgroundColor = .clear
        inputView?.backgroundColor = .clear
        view.isOpaque = false
        inputView?.isOpaque = false
        predictionBar.backgroundColor = .clear
        keyCanvas.backgroundColor = .clear

        for button in predictionButtons {
            button.setTitleColor(dark ? .white : .label, for: .normal)
        }

        let returnType = textDocumentProxy.returnKeyType
        let blueReturn = returnType != .default
        for (button, _) in laidOutKeys {
            if button.referenceRole == .returnKey && blueReturn {
                button.backgroundColor = UIColor(red: 52.0 / 255.0, green: 120.0 / 255.0, blue: 247.0 / 255.0, alpha: 1)
                button.setTitleColor(.white, for: .normal)
                button.tintColor = .white
            } else {
                button.backgroundColor = keyColor
                button.setTitleColor(dark ? .white : .black, for: .normal)
                button.tintColor = dark ? .white : .black
            }
        }
    }

    @objc private func characterKey(_ sender: UIButton) {
        guard var value = sender.currentTitle else { return }
        if page == .letters && !shifted { value = value.lowercased() }
        textDocumentProxy.insertText(value)
        if page == .letters && shifted {
            shifted = false
            DispatchQueue.main.async { [weak self] in self?.refreshLetterCaps() }
        }
        schedulePredictionRefresh()
    }

    @objc private func backspaceDown() {
        textDocumentProxy.deleteBackward()
        schedulePredictionRefresh()
    }

    @objc private func backspaceHold(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began || gesture.state == .changed {
            textDocumentProxy.deleteBackward()
            schedulePredictionRefresh()
        }
    }

    @objc private func spaceDown() {
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let previous = previousWord(in: context)
        var committed = currentWord()

        if let current = committed,
           let correction = cachedCorrection,
           correction.word.caseInsensitiveCompare(current) == .orderedSame,
           correction.replacement.caseInsensitiveCompare(current) != .orderedSame {
            replaceCurrentWord(with: correction.replacement)
            committed = correction.replacement
        }

        if let committed {
            LocalLanguageModel.shared.learn(word: committed, previous: previous)
        }

        textDocumentProxy.insertText(" ")
        shifted = false
        schedulePredictionRefresh()
    }

    @objc private func returnDown() {
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        if let current = currentWord() {
            LocalLanguageModel.shared.learn(word: current, previous: previousWord(in: context))
        }
        textDocumentProxy.insertText("\n")
        shifted = true
        DispatchQueue.main.async { [weak self] in self?.refreshLetterCaps() }
        schedulePredictionRefresh()
    }

    @objc private func toggleShift() {
        shifted.toggle()
        refreshLetterCaps()
    }

    private func refreshLetterCaps() {
        guard page == .letters else { return }
        for (button, _) in laidOutKeys {
            if button.referenceRole == .shift {
                button.setImage(UIImage(systemName: shifted ? "shift.fill" : "shift"), for: .normal)
                continue
            }
            guard let title = button.currentTitle,
                  title.count == 1,
                  title.rangeOfCharacter(from: .letters) != nil else { continue }
            button.setTitle(shifted ? title.uppercased() : title.lowercased(), for: .normal)
        }
    }

    @objc private func toggleNumbers() {
        page = page == .letters ? .numbers : .letters
        rebuildKeys()
        refreshPredictions()
    }

    @objc private func toggleSymbols() {
        page = page == .symbols ? .numbers : .symbols
        rebuildKeys()
        refreshPredictions()
    }

    @objc private func emojiDown() {
        page = page == .emoji ? .letters : .emoji
        rebuildKeys()
        refreshPredictions()
    }

    private func schedulePredictionRefresh() {
        predictionGeneration += 1
        let generation = predictionGeneration
        DispatchQueue.main.async { [weak self] in
            guard self?.predictionGeneration == generation else { return }
            self?.refreshPredictions()
        }
    }

    private func currentWord() -> String? {
        guard let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty else { return nil }
        let separators = CharacterSet.letters.union(.decimalDigits).inverted
        return context.components(separatedBy: separators).last.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func words(in text: String) -> [String] {
        let separators = CharacterSet.letters.union(.decimalDigits).inverted
        return text.components(separatedBy: separators).filter { !$0.isEmpty }
    }

    private func previousWord(in context: String) -> String? {
        let found = words(in: context)
        guard !found.isEmpty else { return nil }
        if let current = currentWord(),
           found.last?.caseInsensitiveCompare(current) == .orderedSame,
           found.count >= 2 {
            return found[found.count - 2]
        }
        return found.last
    }

    private func matchCase(_ suggestion: String, source: String) -> String {
        guard let first = source.first, first.isUppercase else { return suggestion }
        return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
    }

    private func refreshPredictions() {
        guard page == .letters else {
            setPredictions(["", "", ""])
            cachedCorrection = nil
            return
        }

        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let previous = previousWord(in: context)

        guard let word = currentWord(), !word.isEmpty else {
            let learned = LocalLanguageModel.shared.nextWords(after: previous, limit: 3)
            let fallback = preferredLanguage(for: context) == "it_IT"
                ? ["Ciao", "Non", "Io"]
                : ["I", "The", "You"]
            var values = learned
            for item in fallback where !values.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
                values.append(item)
                if values.count == 3 { break }
            }
            while values.count < 3 { values.append("") }
            setPredictions(Array(values.prefix(3)))
            cachedCorrection = nil
            return
        }

        let language = preferredLanguage(for: context)
        let generation = predictionGeneration
        let sourceWord = word
        let learned = LocalLanguageModel.shared.completions(prefix: sourceWord, previous: previous, limit: 8)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let checker = UITextChecker()
            let ns = sourceWord as NSString
            let range = NSRange(location: 0, length: ns.length)
            let misspelled = checker.rangeOfMisspelledWord(
                in: sourceWord,
                range: range,
                startingAt: 0,
                wrap: false,
                language: language
            )
            let guesses = misspelled.location != NSNotFound
                ? (checker.guesses(forWordRange: misspelled, in: sourceWord, language: language) ?? [])
                : []
            let correction = guesses.first
            let completions = checker.completions(
                forPartialWordRange: range,
                in: sourceWord,
                language: language
            ) ?? []

            var scores: [String: Int] = [:]
            var display: [String: String] = [:]

            func add(_ value: String, score: Int) {
                guard !value.isEmpty else { return }
                let key = value.lowercased()
                scores[key] = max(scores[key, default: Int.min], score)
                display[key] = self?.matchCase(value, source: sourceWord) ?? value
            }

            for (index, value) in learned.enumerated() {
                add(value, score: 1200 - index * 30 + LocalLanguageModel.shared.frequency(of: value) * 8)
            }
            if let correction {
                add(correction, score: 1000)
            }
            add(sourceWord, score: 850 + LocalLanguageModel.shared.frequency(of: sourceWord) * 5)
            for (index, value) in guesses.dropFirst().enumerated() {
                add(value, score: 760 - index * 15)
            }
            for (index, value) in completions.enumerated() {
                add(value, score: 700 - index * 10)
            }

            let ranked = scores
                .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
                .prefix(3)
                .compactMap { display[$0.key] }

            var choices = Array(ranked)
            while choices.count < 3 { choices.append("") }

            DispatchQueue.main.async {
                guard let self,
                      self.predictionGeneration == generation,
                      self.currentWord() == sourceWord else { return }
                self.cachedCorrection = correction.map { (sourceWord, $0) }
                self.setPredictions(choices)
            }
        }
    }

    private func preferredLanguage(for text: String) -> String {
        let lower = text.lowercased()
        let italianHints = [" che ", " di ", " non ", " per ", " una ", " il ", " la ", " gli ", " sono ", " con "]
        return italianHints.contains(where: lower.contains) ? "it_IT" : "en_US"
    }

    private func setPredictions(_ values: [String]) {
        for (index, button) in predictionButtons.enumerated() {
            button.setTitle(index < values.count ? values[index] : "", for: .normal)
        }
    }

    @objc private func usePrediction(_ sender: UIButton) {
        guard let value = sender.currentTitle, !value.isEmpty else { return }
        if currentWord() != nil { replaceCurrentWord(with: value) }
        else { textDocumentProxy.insertText(value) }
        schedulePredictionRefresh()
    }

    private func replaceCurrentWord(with replacement: String) {
        guard let word = currentWord() else { return }
        for _ in word { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(replacement)
    }

    @objc private func showAITools(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        guard hasFullAccess else {
            showMessage(title: "Full Access Required", message: "Enable Allow Full Access for Milazy Keyboard in iOS Settings to use AI and clipboard features.")
            return
        }

        let sheet = UIAlertController(title: "Milazy AI", message: "AI never runs on normal keystrokes.", preferredStyle: .actionSheet)

        if AIService.shared.hasAPIKey {
            sheet.addAction(UIAlertAction(title: "Fix", style: .default) { _ in self.runAI(.fix) })
            sheet.addAction(UIAlertAction(title: "Rewrite", style: .default) { _ in self.runAI(.rewrite) })
            sheet.addAction(UIAlertAction(title: "Translate EN ↔ IT", style: .default) { _ in self.runAI(.translate) })
            sheet.addAction(UIAlertAction(title: "Tone", style: .default) { _ in self.runAI(.tone) })
        }

        sheet.addAction(UIAlertAction(
            title: AIService.shared.hasAPIKey ? "Change AI API Key" : "Set AI API Key",
            style: .default
        ) { _ in
            self.promptForAPIKey()
        })

        sheet.addAction(UIAlertAction(title: "Clipboard", style: .default) { _ in
            if let value = UIPasteboard.general.string {
                self.textDocumentProxy.insertText(value)
            }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    private func promptForAPIKey() {
        let alert = UIAlertController(
            title: "Milazy AI",
            message: "Paste your OpenAI API key. It is stored only in this keyboard's iOS Keychain.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "sk-…"
            field.isSecureTextEntry = true
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            guard let value = alert.textFields?.first?.text,
                  AIService.shared.saveAPIKey(value) else {
                self.showMessage(title: "Couldn't Save Key", message: "Enter a non-empty API key and try again.")
                return
            }
            self.showMessage(title: "Milazy AI Ready", message: "Long-press the suggestion bar anytime for Fix, Rewrite, Translate, or Tone.")
        })
        if AIService.shared.hasAPIKey {
            alert.addAction(UIAlertAction(title: "Remove Key", style: .destructive) { _ in
                AIService.shared.clearAPIKey()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func runAI(_ action: AIAction) {
        guard hasFullAccess else {
            showMessage(title: "Full Access Required", message: "Enable Allow Full Access in iOS Settings first.")
            return
        }
        guard AIService.shared.hasAPIKey else {
            promptForAPIKey()
            return
        }

        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        guard !context.isEmpty else { return }

        let originalPredictions = predictionButtons.map { $0.currentTitle ?? "" }
        setPredictions(["", "Thinking…", ""])

        Task {
            let replacement = await AIService.shared.transform(context, action: action)
            await MainActor.run {
                guard let replacement, !replacement.isEmpty else {
                    self.setPredictions(originalPredictions)
                    self.showMessage(title: "AI Request Failed", message: "Check Full Access, your API key, and your connection.")
                    return
                }

                for _ in context {
                    self.textDocumentProxy.deleteBackward()
                }
                self.textDocumentProxy.insertText(replacement)
                self.schedulePredictionRefresh()
            }
        }
    }
}

final class TouchKey: UIButton {
    fileprivate var referenceRole: KeyboardViewController.KeyRole = .normal

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }
}

final class KeyCanvasView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point) else {
            return nil
        }

        let keys = subviews.compactMap { $0 as? TouchKey }.filter {
            !$0.isHidden && $0.alpha > 0.01 && $0.isUserInteractionEnabled
        }

        let candidates = keys.filter { key in
            key.frame.insetBy(dx: -7, dy: -6).contains(point)
        }

        guard !candidates.isEmpty else {
            return super.hitTest(point, with: event)
        }

        return candidates.min { lhs, rhs in
            func score(_ key: TouchKey) -> CGFloat {
                let dx = point.x - key.frame.midX
                let dy = point.y - key.frame.midY
                let nx = dx / max(key.frame.width, 1)
                let ny = dy / max(key.frame.height, 1)
                return nx * nx + 1.8 * ny * ny
            }
            return score(lhs) < score(rhs)
        }
    }
}
