import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Page { case letters, numbers, symbols }

    private let root = UIStackView()
    private let predictionBar = UIStackView()
    private let keyArea = UIStackView()
    private var page: Page = .letters
    private var shifted = true
    private var predictionButtons: [UIButton] = []
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

    override func viewDidLoad() {
        super.viewDidLoad()
        build()
        rebuildKeys()
        updateAppearance()
        refreshPredictions()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateAppearance()
        refreshPredictions()
    }

    private func build() {
        root.axis = .vertical
        root.spacing = 7
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        predictionBar.axis = .horizontal
        predictionBar.distribution = .fillEqually
        predictionBar.spacing = 0
        predictionBar.heightAnchor.constraint(equalToConstant: 44).isActive = true

        for index in 0..<3 {
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.font = .systemFont(ofSize: 17)
            button.addTarget(self, action: #selector(usePrediction(_:)), for: .touchUpInside)
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
                separator.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(separator)
                NSLayoutConstraint.activate([
                    separator.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                    separator.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    separator.widthAnchor.constraint(equalToConstant: 0.5),
                    separator.heightAnchor.constraint(equalToConstant: 26)
                ])
            }
            predictionButtons.append(button)
            predictionBar.addArrangedSubview(button)
        }

        let aiGesture = UILongPressGestureRecognizer(target: self, action: #selector(showAITools(_:)))
        predictionBar.addGestureRecognizer(aiGesture)

        keyArea.axis = .vertical
        keyArea.spacing = 7
        keyArea.distribution = .fillEqually

        root.addArrangedSubview(predictionBar)
        root.addArrangedSubview(keyArea)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])
    }

    private func rebuildKeys() {
        keyArea.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rows = page == .letters ? letterRows : (page == .numbers ? numberRows : symbolRows)

        for (index, row) in rows.enumerated() {
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 6
            stack.distribution = .fillEqually

            if page == .letters && index == 2 {
                let shift = makeKey(shifted ? "⇧" : "⇧", #selector(toggleShift))
                shift.widthAnchor.constraint(equalToConstant: 43).isActive = true
                stack.addArrangedSubview(shift)
                addSpacer(3, to: stack)
            } else if page != .letters && index == 2 {
                let toggle = makeKey(page == .numbers ? "#+=" : "123", #selector(toggleSymbols))
                toggle.widthAnchor.constraint(equalToConstant: 48).isActive = true
                stack.addArrangedSubview(toggle)
                addSpacer(3, to: stack)
            }

            row.forEach { stack.addArrangedSubview(makeKey($0, #selector(characterKey(_:)))) }

            if index == 2 {
                addSpacer(3, to: stack)
                let delete = makeKey("⌫", #selector(backspaceDown))
                delete.widthAnchor.constraint(equalToConstant: 43).isActive = true
                stack.addArrangedSubview(delete)
            }

            keyArea.addArrangedSubview(stack)
        }

        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.spacing = 6

        let mode = makeKey(page == .letters ? "123" : "ABC", #selector(toggleNumbers))
        mode.widthAnchor.constraint(equalToConstant: 52).isActive = true

        let emoji = makeKey("☺", #selector(emojiHint))
        emoji.widthAnchor.constraint(equalToConstant: 42).isActive = true

        let space = makeKey(page == .letters ? "Italiano e English" : "space", #selector(spaceDown))
        space.titleLabel?.font = .systemFont(ofSize: 16)

        let enter = makeKey("↵", #selector(returnDown))
        enter.widthAnchor.constraint(equalToConstant: 82).isActive = true

        [mode, emoji, space, enter].forEach { bottom.addArrangedSubview($0) }
        keyArea.addArrangedSubview(bottom)
        updateAppearance()
    }

    private func addSpacer(_ width: CGFloat, to stack: UIStackView) {
        let spacer = UIView()
        spacer.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(spacer)
    }

    private func makeKey(_ title: String, _ action: Selector) -> TouchKey {
        let button = TouchKey(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: title.count == 1 ? 21 : 16)
        button.layer.cornerRadius = 6
        button.addTarget(self, action: action, for: .touchDown)
        if action == #selector(backspaceDown) {
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(backspaceHold(_:)))
            hold.minimumPressDuration = 0.32
            button.addGestureRecognizer(hold)
        }
        return button
    }

    private func updateAppearance() {
        let dark = textDocumentProxy.keyboardAppearance == .dark || traitCollection.userInterfaceStyle == .dark
        view.backgroundColor = dark ? UIColor(white: 0.11, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1)
        predictionBar.backgroundColor = .clear

        for button in predictionButtons {
            button.setTitleColor(dark ? .white : .label, for: .normal)
        }
        for case let button as TouchKey in allSubviews(keyArea) {
            button.backgroundColor = dark ? UIColor(white: 0.28, alpha: 1) : .white
            button.setTitleColor(dark ? .white : .black, for: .normal)
        }
    }

    private func allSubviews(_ view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }

    @objc private func characterKey(_ sender: UIButton) {
        guard var value = sender.currentTitle else { return }
        if page == .letters && !shifted { value = value.lowercased() }
        textDocumentProxy.insertText(value)
        if page == .letters && shifted {
            shifted = false
            rebuildKeys()
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
        rebuildKeys()
    }

    @objc private func toggleNumbers() {
        page = page == .letters ? .numbers : .letters
        rebuildKeys()
    }

    @objc private func toggleSymbols() {
        page = page == .symbols ? .numbers : .symbols
        rebuildKeys()
    }

    @objc private func emojiHint() {
        advanceToNextInputMode()
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
        guard let word = currentWord(), word.count >= 1 else {
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
            let correction = checker.correction(forWordRange: range, in: sourceWord, language: language)
            let completions = checker.completions(forPartialWordRange: range, in: sourceWord, language: language) ?? []
            var choices: [String] = []
            if let correction, correction.caseInsensitiveCompare(sourceWord) != .orderedSame {
                choices.append(correction)
            }
            choices.append(sourceWord)
            for item in completions where !choices.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
                choices.append(item)
                if choices.count == 3 { break }
            }
            while choices.count < 3 { choices.append("") }

            DispatchQueue.main.async {
                guard let self, self.predictionGeneration == generation, self.currentWord() == sourceWord else { return }
                if let correction { self.cachedCorrection = (sourceWord, correction) }
                else { self.cachedCorrection = nil }
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
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -3, dy: -4).contains(point)
    }
}
