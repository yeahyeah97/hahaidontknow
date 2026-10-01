import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Page { case letters, numbers, symbols, emoji }
    fileprivate enum KeyRole { case normal, shift, delete, mode, emoji, space, returnKey }

    private let predictionBar = UIStackView()
    private let keyCanvas = UIView()
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
        preferredContentSize = CGSize(width: 0, height: 330)
        view.clipsToBounds = false
        buildChrome()
        rebuildKeys()
        updateAppearance()
        refreshPredictions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let referenceWidth: CGFloat = 428
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
            button.titleLabel?.font = .systemFont(ofSize: 17)
            button.addTarget(self, action: #selector(usePrediction(_:)), for: .touchUpInside)
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = UIColor.separator.withAlphaComponent(0.32)
                separator.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(separator)
                NSLayoutConstraint.activate([
                    separator.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                    separator.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    separator.widthAnchor.constraint(equalToConstant: 0.5),
                    separator.heightAnchor.constraint(equalToConstant: 49)
                ])
            }
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
            predictionBar.heightAnchor.constraint(equalToConstant: 56),

            keyCanvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyCanvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyCanvas.topAnchor.constraint(equalTo: view.topAnchor, constant: 76.33),
            keyCanvas.heightAnchor.constraint(equalToConstant: 213)
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
            addKey(title, CGRect(x: 0.67 + CGFloat(i) * step, y: 0, width: normalW, height: keyH), #selector(characterKey(_:)))
        }

        for (i, title) in letterRows[1].enumerated() {
            addKey(title, CGRect(x: 22 + CGFloat(i) * step, y: 56, width: normalW, height: keyH), #selector(characterKey(_:)))
        }

        addKey("⇧", CGRect(x: 0.67, y: 112, width: 50, height: keyH), #selector(toggleShift), role: .shift)
        for (i, title) in letterRows[2].enumerated() {
            addKey(title, CGRect(x: 65.33 + CGFloat(i) * step, y: 112, width: normalW, height: keyH), #selector(characterKey(_:)))
        }
        addKey("⌫", CGRect(x: 377.33, y: 112, width: 50.33, height: keyH), #selector(backspaceDown), role: .delete)

        buildBottomRow(modeTitle: "123", spaceTitle: "")
    }

    private func buildNumbers(symbols: Bool) {
        let rows = symbols ? symbolRows : numberRows
        let normalW: CGFloat = 37.33
        let keyH: CGFloat = 45
        let step: CGFloat = 43.33

        for (i, title) in rows[0].enumerated() {
            addKey(title, CGRect(x: 0.67 + CGFloat(i) * step, y: 0, width: normalW, height: keyH), #selector(characterKey(_:)))
        }
        for (i, title) in rows[1].enumerated() {
            addKey(title, CGRect(x: 0.67 + CGFloat(i) * step, y: 56, width: normalW, height: keyH), #selector(characterKey(_:)))
        }

        addKey(symbols ? "123" : "#+=", CGRect(x: 0.67, y: 112, width: 50, height: keyH), #selector(toggleSymbols), role: .mode)
        let punctuationW: CGFloat = 54.67
        let punctuationX: [CGFloat] = [65.33, 126, 186.67, 247.33, 308]
        for (i, title) in rows[2].enumerated() {
            addKey(title, CGRect(x: punctuationX[i], y: 112, width: punctuationW, height: keyH), #selector(characterKey(_:)))
        }
        addKey("⌫", CGRect(x: 377.33, y: 112, width: 50.33, height: keyH), #selector(backspaceDown), role: .delete)

        buildBottomRow(modeTitle: "ABC", spaceTitle: "space")
    }

    private func buildEmoji() {
        let keyH: CGFloat = 45
        let normalW: CGFloat = 37.33
        let step: CGFloat = 43.33

        for row in 0..<3 {
            for (i, title) in emojiRows[row].enumerated() {
                addKey(title, CGRect(x: 0.67 + CGFloat(i) * step, y: CGFloat(row) * 56, width: normalW, height: keyH), #selector(characterKey(_:)))
            }
        }
        buildBottomRow(modeTitle: "ABC", spaceTitle: "space")
    }

    private func buildBottomRow(modeTitle: String, spaceTitle: String) {
        let y: CGFloat = 168
        let h: CGFloat = 45
        addKey(modeTitle, CGRect(x: 0.67, y: y, width: 48, height: h), #selector(toggleNumbers), role: .mode)
        addKey("☺", CGRect(x: 54.67, y: y, width: 48, height: h), #selector(emojiDown), role: .emoji)
        addKey(spaceTitle, CGRect(x: 108.67, y: y, width: 210.67, height: h), #selector(spaceDown), role: .space)
        addKey("↵", CGRect(x: 325.33, y: y, width: 102.33, height: h), #selector(returnDown), role: .returnKey)
    }

    private func addKey(_ title: String, _ frame: CGRect, _ action: Selector, role: KeyRole = .normal) {
        let button = TouchKey(type: .system)
        button.setTitle(title, for: .normal)
        button.referenceRole = role
        button.titleLabel?.font = .systemFont(ofSize: title.count == 1 ? 21 : 16)
        button.layer.cornerRadius = 5.5
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
        let background = dark ? UIColor(white: 31.0 / 255.0, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1)
        let keyColor = dark ? UIColor(white: 72.0 / 255.0, alpha: 1) : .white
        view.backgroundColor = background
        predictionBar.backgroundColor = background

        for button in predictionButtons {
            button.setTitleColor(dark ? .white : .label, for: .normal)
        }

        let returnType = textDocumentProxy.returnKeyType
        let blueReturn = returnType != .default
        for (button, _) in laidOutKeys {
            if button.referenceRole == .returnKey && blueReturn {
                button.backgroundColor = UIColor.systemBlue
                button.setTitleColor(.white, for: .normal)
            } else {
                button.backgroundColor = keyColor
                button.setTitleColor(dark ? .white : .black, for: .normal)
            }
        }
    }

    @objc private func characterKey(_ sender: UIButton) {
        guard var value = sender.currentTitle else { return }
        if page == .letters && !shifted { value = value.lowercased() }
        textDocumentProxy.insertText(value)
        if page == .letters && shifted {
            shifted = false
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
        if let current = currentWord(),
           let correction = cachedCorrection,
           correction.word.caseInsensitiveCompare(current) == .orderedSame,
           correction.replacement.caseInsensitiveCompare(current) != .orderedSame {
            replaceCurrentWord(with: correction.replacement)
        }
        textDocumentProxy.insertText(" ")
        shifted = false
        schedulePredictionRefresh()
    }

    @objc private func returnDown() {
        textDocumentProxy.insertText("\n")
        shifted = true
        schedulePredictionRefresh()
    }

    @objc private func toggleShift() {
        shifted.toggle()
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

    private func refreshPredictions() {
        guard page == .letters else {
            setPredictions(["", "", ""])
            cachedCorrection = nil
            return
        }

        guard let word = currentWord(), !word.isEmpty else {
            setPredictions(["I", "The", "You"])
            cachedCorrection = nil
            return
        }

        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let language = preferredLanguage(for: context)
        let generation = predictionGeneration
        let sourceWord = word

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let checker = UITextChecker()
            let ns = sourceWord as NSString
            let range = NSRange(location: 0, length: ns.length)
            let misspelled = checker.rangeOfMisspelledWord(in: sourceWord, range: range, startingAt: 0, wrap: false, language: language)
            let guesses = misspelled.location != NSNotFound
                ? (checker.guesses(forWordRange: misspelled, in: sourceWord, language: language) ?? [])
                : []
            let correction = guesses.first
            let completions = checker.completions(forPartialWordRange: range, in: sourceWord, language: language) ?? []

            var choices: [String] = []
            if let correction, correction.caseInsensitiveCompare(sourceWord) != .orderedSame {
                choices.append(correction)
            }
            choices.append(sourceWord)
            for item in (guesses.dropFirst() + completions)
            where !choices.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
                choices.append(item)
                if choices.count == 3 { break }
            }
            while choices.count < 3 { choices.append("") }

            DispatchQueue.main.async {
                guard let self, self.predictionGeneration == generation, self.currentWord() == sourceWord else { return }
                self.cachedCorrection = correction.map { (sourceWord, $0) }
                self.setPredictions(Array(choices.prefix(3)))
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
        let sheet = UIAlertController(title: "Milazy AI", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Fix", style: .default) { _ in self.runAI(.fix) })
        sheet.addAction(UIAlertAction(title: "Rewrite", style: .default) { _ in self.runAI(.rewrite) })
        sheet.addAction(UIAlertAction(title: "Translate", style: .default) { _ in self.runAI(.translate) })
        sheet.addAction(UIAlertAction(title: "Tone", style: .default) { _ in self.runAI(.tone) })
        sheet.addAction(UIAlertAction(title: "Clipboard", style: .default) { _ in
            if let value = UIPasteboard.general.string { self.textDocumentProxy.insertText(value) }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    private func runAI(_ action: AIAction) {
        guard hasFullAccess else { return }
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        guard !context.isEmpty else { return }
        Task {
            guard let replacement = await AIService.shared.transform(context, action: action) else { return }
            await MainActor.run {
                for _ in context { self.textDocumentProxy.deleteBackward() }
                self.textDocumentProxy.insertText(replacement)
                self.schedulePredictionRefresh()
            }
        }
    }
}

final class TouchKey: UIButton {
    fileprivate var referenceRole: KeyboardViewController.KeyRole = .normal

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -3, dy: -4).contains(point)
    }
}
