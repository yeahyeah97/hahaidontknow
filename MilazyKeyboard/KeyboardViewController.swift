import UIKit

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    private enum Page { case letters, numbers, symbols, emoji }
    enum KeyRole { case normal, shift, delete, mode, emoji, space, returnKey }

    private let predictionBar = UIStackView()
    private let aiButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let keyCanvas = KeyCanvasView()
    private let aiPanel = UIView()
    private let aiStatusLabel = UILabel()
    private var page: Page = .letters
    private var shifted = true
    private var capitalization = CapitalizationState()
    private var knownContext: String?
    private var knownDocument: UUID?
    private var lastShiftTap: TimeInterval = 0
    private var predictionButtons: [UIButton] = []
    private var laidOutKeys: [(TouchKey, CGRect)] = []
    private let predictionEngine = PredictionEngine()
    private var predictionResult: PredictionEngine.Result?
    private var predictionContext: String?
    private var undoCorrection: (source: String, replacement: String, context: String, document: UUID)?
    private var spaceBadge: UILabel?
    private var predictionGeneration = 0
    private var backspaceTimer: Timer?
    private var lastSpaceTap: TimeInterval = 0
    private let keyHaptic = UIImpactFeedbackGenerator(style: .light)
    private var keyPreview: KeyPreviewView?
    private enum ToolPanel { case ai, menu, clipboard, settings }
    private var toolPanel: ToolPanel = .ai

    var enableInputClicksWhenVisible: Bool { KeyboardPreferences.shared.sound }

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
        preferredContentSize = CGSize(width: 0, height: 248)
        let height = view.heightAnchor.constraint(equalToConstant: 248)
        height.priority = .defaultHigh
        height.isActive = true
        view.clipsToBounds = false
        keyHaptic.prepare()
        buildChrome()
        rebuildKeys()
        syncAutoCapitalization()
        updateAppearance()
        requestSupplementaryLexicon { [weak self] lexicon in
            DispatchQueue.main.async {
                guard let self else { return }
                self.predictionEngine.installLexicon(
                    lexicon.entries.map { ($0.userInput, $0.documentText) },
                    mode: KeyboardPreferences.shared.languageMode
                )
                self.refreshPredictions()
            }
        }
        refreshPredictions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let referenceWidth: CGFloat = 440
        let sx = keyCanvas.bounds.width / referenceWidth
        let sy = min(1, max(0, keyCanvas.bounds.height / 213))
        let layout = KeyboardPreferences.shared.layoutMode
        for (button, reference) in laidOutKeys {
            var frame = CGRect(
                x: reference.minX * sx,
                y: reference.minY * sy,
                width: reference.width * sx,
                height: reference.height * sy
            )
            if button.referenceRole == .normal {
                switch layout {
                case .ios: break
                case .wide: frame = frame.insetBy(dx: -1.3, dy: -0.5)
                case .compact: frame = frame.insetBy(dx: 1.4, dy: 0.5)
                }
            }
            button.frame = frame.integral
        }
        keyCanvas.cacheLayout()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let context = textDocumentProxy.documentContextBeforeInput
        if knownDocument != textDocumentProxy.documentIdentifier || context != knownContext {
            capitalization.reset()
            predictionResult = nil
            undoCorrection = nil
        }
        knownDocument = textDocumentProxy.documentIdentifier
        knownContext = context
        updateReturnKey()
        updateAppearance()
        syncAutoCapitalization()
        refreshLetterCaps()
        refreshPredictions()
    }

    private func buildChrome() {
        aiButton.translatesAutoresizingMaskIntoConstraints = false
        aiButton.setTitle("Deaf AI", for: .normal)
        aiButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        aiButton.layer.cornerRadius = 9
        aiButton.addTarget(self, action: #selector(aiTapped), for: .touchUpInside)
        aiButton.accessibilityLabel = "Deaf AI Fix"
        view.addSubview(aiButton)

        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.setImage(UIImage(systemName: "square.grid.2x2.fill"), for: .normal)
        menuButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold),
            forImageIn: .normal
        )
        menuButton.layer.cornerRadius = 9
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        menuButton.accessibilityLabel = "Tools"
        view.addSubview(menuButton)

        predictionBar.axis = .horizontal
        predictionBar.distribution = .fillEqually
        predictionBar.spacing = 0
        predictionBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(predictionBar)

        for index in 0..<3 {
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.font = .systemFont(ofSize: 17.5)
            button.addTarget(self, action: #selector(usePrediction(_:)), for: .touchUpInside)
            predictionButtons.append(button)
            predictionBar.addArrangedSubview(button)
        }

        keyCanvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyCanvas)

        aiPanel.translatesAutoresizingMaskIntoConstraints = false
        aiPanel.isHidden = true
        view.addSubview(aiPanel)

        aiStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        aiStatusLabel.textAlignment = .center
        aiStatusLabel.numberOfLines = 2

        NSLayoutConstraint.activate([
            aiButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            aiButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            aiButton.widthAnchor.constraint(equalToConstant: 58),
            aiButton.heightAnchor.constraint(equalToConstant: 27),

            menuButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            menuButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            menuButton.widthAnchor.constraint(equalToConstant: 38),
            menuButton.heightAnchor.constraint(equalToConstant: 27),

            predictionBar.leadingAnchor.constraint(equalTo: aiButton.trailingAnchor, constant: 4),
            predictionBar.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -4),
            predictionBar.topAnchor.constraint(equalTo: view.topAnchor),
            predictionBar.heightAnchor.constraint(equalToConstant: 35),

            keyCanvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyCanvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyCanvas.topAnchor.constraint(equalTo: predictionBar.bottomAnchor),
            keyCanvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            aiPanel.leadingAnchor.constraint(equalTo: keyCanvas.leadingAnchor),
            aiPanel.trailingAnchor.constraint(equalTo: keyCanvas.trailingAnchor),
            aiPanel.topAnchor.constraint(equalTo: keyCanvas.topAnchor),
            aiPanel.bottomAnchor.constraint(equalTo: keyCanvas.bottomAnchor)
        ])
    }

    private func rebuildKeys() {
        keyCanvas.subviews.forEach { $0.removeFromSuperview() }
        laidOutKeys.removeAll()
        spaceBadge = nil

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
        syncAutoCapitalization()
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
        if role == .normal && page != .emoji {
            button.learningKey = title.lowercased()
        }

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

        if role == .normal {
            button.onFingerBegan = { [weak self] key, original in
                self?.showPreview(for: key, text: original)
            }
            button.onFingerMoved = { [weak self] key, point, original in
                guard let self else { return }
                self.showPreview(for: key, text: original)
            }
            button.onFingerEnded = { [weak self] key, point, original in
                self?.hidePreview()
                // A touch-down character is final. Word correction happens on Space.
            }
            button.onFingerCancelled = { [weak self] in
                self?.hidePreview()
            }
        }

        if role == .delete {
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(backspaceHold(_:)))
            hold.minimumPressDuration = 0.32
            button.addGestureRecognizer(hold)
        }

        if role == .space && page == .letters {
            let badge = UILabel()
            badge.text = "IT EN"
            badge.font = .systemFont(ofSize: 12, weight: .medium)
            badge.textColor = UIColor.secondaryLabel
            badge.textAlignment = .center
            badge.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(badge)
            spaceBadge = badge
            NSLayoutConstraint.activate([
                badge.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                badge.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: -1)
            ])
        }

        keyCanvas.addSubview(button)
        laidOutKeys.append((button, frame))
    }

    private func showPreview(for key: TouchKey, text: String) {
        guard page != .emoji, KeyboardPreferences.shared.keyPopups else { return }

        let preview: KeyPreviewView
        if let existing = keyPreview {
            preview = existing
        } else {
            preview = KeyPreviewView()
            keyPreview = preview
            view.addSubview(preview)
        }

        preview.text = text
        let keyFrame = keyCanvas.convert(key.frame, to: view)
        let width: CGFloat = 54
        let height: CGFloat = 62
        let x = min(max(keyFrame.midX - width / 2, 2), view.bounds.width - width - 2)
        let y = max(1, keyFrame.minY - 30)
        preview.frame = CGRect(x: x, y: y, width: width, height: height)
        preview.isHidden = false
        view.bringSubviewToFront(preview)
    }

    private func hidePreview() {
        keyPreview?.isHidden = true
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
        aiButton.setTitleColor(.white, for: .normal)
        aiButton.backgroundColor = UIColor(red: 0.33, green: 0.20, blue: 0.56, alpha: 1)
        menuButton.tintColor = dark ? .white : .label
        menuButton.backgroundColor = dark ? UIColor.white.withAlphaComponent(0.10) : UIColor.black.withAlphaComponent(0.08)
        aiStatusLabel.textColor = dark ? UIColor.white.withAlphaComponent(0.86) : UIColor.label.withAlphaComponent(0.86)
        aiPanel.backgroundColor = .clear

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

    private func playKeyFeedback() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let prefs = KeyboardPreferences.shared
            if prefs.sound { UIDevice.current.playInputClick() }
            if prefs.haptics {
                self.keyHaptic.impactOccurred(intensity: 0.28)
                self.keyHaptic.prepare()
            }
        }
    }

    private func syncAutoCapitalization() {
        guard page == .letters else { return }
        let mode: CapitalizationState.Mode
        switch textDocumentProxy.autocapitalizationType {
        case .none: mode = .none
        case .words: mode = .words
        case .allCharacters: mode = .allCharacters
        default: mode = .sentences
        }
        shifted = capitalization.uppercase(
            context: textDocumentProxy.documentContextBeforeInput, mode: mode, current: shifted
        )
        refreshLetterCaps()
    }

    private func didInsertText() {
        knownDocument = textDocumentProxy.documentIdentifier
        knownContext = textDocumentProxy.documentContextBeforeInput
        syncAutoCapitalization()
        schedulePredictionRefresh()
    }

    private var allowsAutocorrection: Bool {
        guard textDocumentProxy.autocorrectionType != .no else { return false }
        switch textDocumentProxy.keyboardType {
        case .URL, .emailAddress, .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad:
            return false
        default: return true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        backspaceTimer?.invalidate()
        backspaceTimer = nil
        predictionEngine.cancel()
        predictionEngine.flushLearning()
        hidePreview()
    }

    private func canInsertDoubleSpacePeriod(in context: String) -> Bool {
        guard context.hasSuffix(" ") else { return false }
        let beforeSpace = context.dropLast()
        guard let last = beforeSpace.last else { return false }
        return last.isLetter || last.isNumber
    }

    @objc private func characterKey(_ sender: UIButton) {
        // The displayed title is the single source of truth for insertion.
        guard let value = sender.currentTitle, !value.isEmpty else { return }
        textDocumentProxy.insertText(value)
        undoCorrection = nil
        lastSpaceTap = 0
        if page == .letters { capitalization.consumedLetter() }
        didInsertText()
        playKeyFeedback()
    }

    @objc private func backspaceDown() {
        if let undo = undoCorrection,
           undo.document == textDocumentProxy.documentIdentifier,
           undo.context == textDocumentProxy.documentContextBeforeInput {
            for _ in undo.replacement + " " { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(undo.source)
            predictionEngine.learn(word: undo.source, previous: nil,
                mode: KeyboardPreferences.shared.languageMode, rejectedCorrection: true)
        } else { textDocumentProxy.deleteBackward() }
        undoCorrection = nil
        capitalization.reset()
        didInsertText()
        playKeyFeedback()
    }

    @objc private func backspaceHold(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            backspaceTimer?.invalidate()
            textDocumentProxy.deleteBackward()
            playKeyFeedback()
            didInsertText()

            backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.textDocumentProxy.deleteBackward()
                self.didInsertText()
                self.playKeyFeedback()
            }
        case .ended, .cancelled, .failed:
            backspaceTimer?.invalidate()
            backspaceTimer = nil
            schedulePredictionRefresh()
        default:
            break
        }
    }

    @objc private func spaceDown() {
        let now = Date.timeIntervalSinceReferenceDate
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let mode = KeyboardPreferences.shared.languageMode
        undoCorrection = nil
        if now - lastSpaceTap < 0.48, canInsertDoubleSpacePeriod(in: context) {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            lastSpaceTap = 0
            capitalization.reset()
            didInsertText()
            playKeyFeedback()
            return
        }

        let previous = TextContext.previousWord(in: context)
        let source = TextContext.currentWord(in: context)
        var committed = source
        var applied: String?
        if allowsAutocorrection, let source {
            let cached = predictionResult.flatMap { $0.context == context ? $0.correction : nil }
            let replacement = cached ?? predictionEngine.localCorrection(
                for: source, previous: previous, mode: mode
            )
            if let replacement, replacement.lowercased() != source.lowercased() {
                replaceCurrentWord(with: replacement)
                committed = replacement
                applied = replacement
            }
        }
        textDocumentProxy.insertText(" ")
        lastSpaceTap = now
        capitalization.reset()
        didInsertText()
        if let source, let applied, let after = textDocumentProxy.documentContextBeforeInput {
            undoCorrection = (source, applied, after, textDocumentProxy.documentIdentifier)
        }
        if let committed {
            // Automatically applied guesses never teach source -> replacement mappings.
            predictionEngine.learn(word: committed, previous: previous, mode: mode)
        }
        playKeyFeedback()
    }

    @objc private func returnDown() {
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let word = TextContext.currentWord(in: context)
        textDocumentProxy.insertText("\n")
        undoCorrection = nil
        capitalization.reset()
        didInsertText()
        if let word {
            predictionEngine.learn(word: word, previous: TextContext.previousWord(in: context),
                                   mode: KeyboardPreferences.shared.languageMode)
        }
        playKeyFeedback()
    }

    @objc private func toggleShift() {
        let now = Date.timeIntervalSinceReferenceDate
        capitalization.toggle(currentlyUppercase: shifted, lock: now - lastShiftTap < 0.32)
        lastShiftTap = now
        syncAutoCapitalization()
        playKeyFeedback()
    }

    private func refreshLetterCaps() {
        guard page == .letters else { return }
        for (button, _) in laidOutKeys {
            if button.referenceRole == .shift {
                button.setImage(UIImage(systemName: shifted ? "shift.fill" : "shift"), for: .normal)
                continue
            }
            guard let base = button.learningKey,
                  base.count == 1,
                  base.rangeOfCharacter(from: .letters) != nil else { continue }
            button.setTitle(shifted ? base.uppercased() : base.lowercased(), for: .normal)
        }
    }

    @objc private func toggleNumbers() {
        playKeyFeedback()
        page = page == .letters ? .numbers : .letters
        rebuildKeys()
        refreshPredictions()
    }

    @objc private func toggleSymbols() {
        playKeyFeedback()
        page = page == .symbols ? .numbers : .symbols
        rebuildKeys()
        refreshPredictions()
    }

    @objc private func emojiDown() {
        playKeyFeedback()
        page = page == .emoji ? .letters : .emoji
        rebuildKeys()
        refreshPredictions()
    }

    private func schedulePredictionRefresh() {
        predictionGeneration += 1
        predictionResult = nil
        predictionContext = nil
        setPredictions(["", "", ""])
        predictionEngine.cancel()
        let generation = predictionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            guard let self, self.predictionGeneration == generation else { return }
            self.refreshPredictions()
        }
    }

    private func currentWord() -> String? {
        textDocumentProxy.documentContextBeforeInput.flatMap { TextContext.currentWord(in: $0) }
    }

    private func words(in text: String) -> [String] { TextContext.words(in: text) }

    private func refreshPredictions() {
        predictionGeneration += 1
        predictionResult = nil
        predictionContext = nil
        predictionEngine.cancel()
        guard page == .letters, let context = textDocumentProxy.documentContextBeforeInput else {
            setPredictions(["", "", ""])
            return
        }
        let generation = predictionGeneration
        let document = textDocumentProxy.documentIdentifier
        let mode = KeyboardPreferences.shared.languageMode
        predictionEngine.request(context: context, document: document, mode: mode) { [weak self] result in
            guard let self, self.predictionGeneration == generation,
                  self.page == .letters, self.textDocumentProxy.documentIdentifier == document,
                  self.textDocumentProxy.documentContextBeforeInput == result.context,
                  KeyboardPreferences.shared.languageMode == mode else { return }
            self.predictionResult = result
            self.predictionContext = result.context
            self.setPredictions(result.choices)
            self.spaceBadge?.text = mode == .automatic ? "IT EN" :
                (mode == .italian ? "IT" : "EN")
        }
    }

    private func setPredictions(_ values: [String]) {
        for (index, button) in predictionButtons.enumerated() {
            button.setTitle(index < values.count ? values[index] : "", for: .normal)
        }
    }

    @objc private func usePrediction(_ sender: UIButton) {
        guard let value = sender.currentTitle, !value.isEmpty,
              let context = textDocumentProxy.documentContextBeforeInput,
              predictionContext == context else { return }
        let before = currentWord()
        let previous = TextContext.previousWord(in: context)
        if before != nil { replaceCurrentWord(with: value) }
        else { textDocumentProxy.insertText(value) }
        undoCorrection = nil
        didInsertText()
        predictionEngine.learn(word: value, previous: previous,
            mode: KeyboardPreferences.shared.languageMode, selectedFrom: before)
    }

    private func replaceCurrentWord(with replacement: String) {
        guard let word = currentWord() else { return }
        for _ in word { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(replacement)
    }

    @objc private func aiTapped() {
        if AIService.shared.hasAPIKey {
            runAI(.fix)
        } else {
            showAIPanel()
        }
    }

    @objc private func menuTapped() {
        toolPanel = .menu
        keyCanvas.isHidden = true
        aiPanel.isHidden = false
        rebuildAIPanel()
    }

    private func showAIPanel() {
        toolPanel = .ai
        keyCanvas.isHidden = true
        aiPanel.isHidden = false
        rebuildAIPanel()
    }

    private func hideAIPanel() {
        aiPanel.isHidden = true
        keyCanvas.isHidden = false
        aiStatusLabel.text = nil
        refreshPredictions()
    }

    private func rebuildAIPanel() {
        aiPanel.subviews.forEach { $0.removeFromSuperview() }

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        aiPanel.addSubview(content)

        let title = UILabel()
        title.font = .systemFont(ofSize: 16.5, weight: .semibold)
        title.textAlignment = .center

        aiStatusLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        aiStatusLabel.numberOfLines = 1

        let top = UIStackView(arrangedSubviews: [title, aiStatusLabel])
        top.axis = .vertical
        top.spacing = 2
        content.addArrangedSubview(top)

        switch toolPanel {
        case .ai:
            title.text = "Deaf AI · Gemini"

            if !hasFullAccess {
                aiStatusLabel.text = "Allow Full Access is required for AI, GIF and clipboard."
                content.addArrangedSubview(aiPanelButton("Back", action: #selector(aiBack)))
            } else if !AIService.shared.hasAPIKey {
                aiStatusLabel.text = "Copy your Gemini key, then paste it here."
                content.addArrangedSubview(aiPanelButton("Paste Gemini Key", action: #selector(aiPasteKey)))
                content.addArrangedSubview(makePanelRow([
                    aiPanelButton("Clipboard", action: #selector(openClipboardPanel)),
                    aiPanelButton("Settings", action: #selector(openSettingsPanel)),
                    aiPanelButton("Back", action: #selector(aiBack))
                ]))
            } else {
                aiStatusLabel.text = "Semantic Fix + rewrite tools"

                content.addArrangedSubview(makePanelRow([
                    aiPanelButton("Fix", action: #selector(aiFix)),
                    aiPanelButton("Rewrite", action: #selector(aiRewrite))
                ]))
                content.addArrangedSubview(makePanelRow([
                    aiPanelButton("Translate EN ↔ IT", action: #selector(aiTranslate)),
                    aiPanelButton("Tone", action: #selector(aiTone))
                ]))
                content.addArrangedSubview(makePanelRow([
                    aiPanelButton("Clipboard", action: #selector(openClipboardPanel)),
                    aiPanelButton("GIF", action: #selector(aiGIF)),
                    aiPanelButton("Settings", action: #selector(openSettingsPanel))
                ]))
                content.addArrangedSubview(makePanelRow([
                    aiPanelButton("Change Key", action: #selector(aiChangeKey)),
                    aiPanelButton("Back", action: #selector(aiBack))
                ]))
            }

        case .menu:
            title.text = "Milazy Tools"
            aiStatusLabel.text = "Emoji · GIF · Clipboard · Translate · Language · Layout · Hitbox · Settings"

            content.addArrangedSubview(makePanelRow([
                aiPanelButton("Emoji", action: #selector(menuEmoji)),
                aiPanelButton("GIF", action: #selector(aiGIF)),
                aiPanelButton("Appunti", action: #selector(openClipboardPanel)),
                aiPanelButton("Traduttore", action: #selector(menuTranslate))
            ]))
            content.addArrangedSubview(makePanelRow([
                aiPanelButton("Lingua", action: #selector(cycleLanguage)),
                aiPanelButton("Layout", action: #selector(cycleLayout)),
                aiPanelButton("Hitbox", action: #selector(cycleHitbox)),
                aiPanelButton("Impostazioni", action: #selector(openSettingsPanel))
            ]))
            content.addArrangedSubview(aiPanelButton("Chiudi", action: #selector(closeTools)))

        case .clipboard:
            title.text = "Clipboard History"
            ClipboardHistory.shared.importSystemClipboard()
            let items = Array(ClipboardHistory.shared.items.prefix(4))
            aiStatusLabel.text = items.isEmpty ? "Copy text, then reopen Clipboard." : "\(ClipboardHistory.shared.items.count) saved locally"

            for pairStart in stride(from: 0, to: items.count, by: 2) {
                var buttons: [UIButton] = []
                for index in pairStart..<min(pairStart + 2, items.count) {
                    let text = items[index]
                    let label = String(text.replacingOccurrences(of: "\n", with: " ").prefix(24))
                    let button = aiPanelButton(label, action: #selector(pasteClipboardItem(_:)))
                    button.tag = index
                    buttons.append(button)
                }
                content.addArrangedSubview(makePanelRow(buttons))
            }

            content.addArrangedSubview(makePanelRow([
                aiPanelButton("Import Current", action: #selector(importClipboard)),
                aiPanelButton("Clear", action: #selector(clearClipboard)),
                aiPanelButton("Back", action: #selector(aiBack))
            ]))

        case .settings:
            title.text = "Milazy Keyboard 3.0"
            aiStatusLabel.text = "Typing engine settings"

            let prefs = KeyboardPreferences.shared
            content.addArrangedSubview(makePanelRow([
                aiPanelButton("Language: \(prefs.languageMode.title)", action: #selector(cycleLanguage)),
                aiPanelButton("Layout: \(prefs.layoutMode.title)", action: #selector(cycleLayout))
            ]))
            content.addArrangedSubview(makePanelRow([
                aiPanelButton("Hitbox: \(prefs.hitboxMode.title)", action: #selector(cycleHitbox)),
                aiPanelButton("Popups: \(prefs.keyPopups ? "On" : "Off")", action: #selector(togglePopups))
            ]))
            content.addArrangedSubview(makePanelRow([
                aiPanelButton("Haptic: \(prefs.haptics ? "On" : "Off")", action: #selector(toggleHaptics)),
                aiPanelButton("Sound: \(prefs.sound ? "On" : "Off")", action: #selector(toggleSound))
            ]))

            let gif = GIFService.shared
            content.addArrangedSubview(makePanelRow([
                aiPanelButton("GIF: \(gif.provider.title)", action: #selector(cycleGIFProvider)),
                aiPanelButton(gif.hasKey ? "Change GIF Key" : "Paste GIF Key", action: #selector(pasteGIFKey)),
                aiPanelButton("Back", action: #selector(aiBack))
            ]))
        }

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: aiPanel.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: aiPanel.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: aiPanel.topAnchor, constant: 4)
        ])
        updateAppearance()
    }

    private func makePanelRow(_ buttons: [UIButton]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillEqually
        return row
    }

    private func aiPanelButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(white: 0.27, alpha: 1)
        button.layer.cornerRadius = 8
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func aiBack() {
        if toolPanel == .ai {
            hideAIPanel()
        } else {
            toolPanel = .ai
            aiStatusLabel.text = nil
            rebuildAIPanel()
        }
    }

    @objc private func closeTools() {
        hideAIPanel()
    }

    @objc private func menuEmoji() {
        hideAIPanel()
        page = .emoji
        rebuildKeys()
        refreshPredictions()
    }

    @objc private func menuTranslate() {
        if AIService.shared.hasAPIKey {
            runAI(.translate)
        } else {
            showAIPanel()
        }
    }

    @objc private func openClipboardPanel() {
        toolPanel = .clipboard
        rebuildAIPanel()
    }

    @objc private func openSettingsPanel() {
        toolPanel = .settings
        rebuildAIPanel()
    }

    @objc private func importClipboard() {
        ClipboardHistory.shared.importSystemClipboard()
        rebuildAIPanel()
    }

    @objc private func clearClipboard() {
        ClipboardHistory.shared.clear()
        rebuildAIPanel()
    }

    @objc private func pasteClipboardItem(_ sender: UIButton) {
        let items = ClipboardHistory.shared.items
        guard sender.tag >= 0, sender.tag < items.count else { return }
        let text = items[sender.tag]
        textDocumentProxy.insertText(text)
        ClipboardHistory.shared.add(text)
        hideAIPanel()
        schedulePredictionRefresh()
    }

    @objc private func cycleLanguage() {
        let values = KeyboardPreferences.LanguageMode.allCases
        let current = KeyboardPreferences.shared.languageMode
        let next = values[(values.firstIndex(of: current)! + 1) % values.count]
        KeyboardPreferences.shared.languageMode = next
        rebuildAIPanel()
        refreshPredictions()
    }

    @objc private func cycleLayout() {
        let values = KeyboardPreferences.LayoutMode.allCases
        let current = KeyboardPreferences.shared.layoutMode
        let next = values[(values.firstIndex(of: current)! + 1) % values.count]
        KeyboardPreferences.shared.layoutMode = next
        rebuildAIPanel()
        view.setNeedsLayout()
    }

    @objc private func cycleHitbox() {
        let values = KeyboardPreferences.HitboxMode.allCases
        let current = KeyboardPreferences.shared.hitboxMode
        KeyboardPreferences.shared.hitboxMode = values[(values.firstIndex(of: current)! + 1) % values.count]
        rebuildAIPanel()
    }

    @objc private func togglePopups() {
        KeyboardPreferences.shared.keyPopups.toggle()
        hidePreview()
        rebuildAIPanel()
    }

    @objc private func toggleHaptics() {
        KeyboardPreferences.shared.haptics.toggle()
        rebuildAIPanel()
    }

    @objc private func toggleSound() {
        KeyboardPreferences.shared.sound.toggle()
        rebuildAIPanel()
    }

    @objc private func cycleGIFProvider() {
        let values = GIFService.Provider.allCases
        let current = GIFService.shared.provider
        GIFService.shared.provider = values[(values.firstIndex(of: current)! + 1) % values.count]
        rebuildAIPanel()
    }

    @objc private func pasteGIFKey() {
        guard let key = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            aiStatusLabel.text = "Copy a provider API key first."
            return
        }
        GIFService.shared.saveKey(key, for: GIFService.shared.provider)
        rebuildAIPanel()
    }

    @objc private func aiGIF() {
        guard hasFullAccess else {
            aiStatusLabel.text = "Full Access is required."
            return
        }
        guard GIFService.shared.hasKey else {
            toolPanel = .settings
            aiStatusLabel.text = "Add a GIF provider key first."
            rebuildAIPanel()
            return
        }

        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let queryWords = words(in: context).suffix(3)
        let query = queryWords.joined(separator: " ")
        guard !query.isEmpty else {
            aiStatusLabel.text = "Type a GIF search word first."
            return
        }

        aiStatusLabel.text = "Finding GIF…"
        setAIPanelControls(enabled: false)

        Task {
            let data = await GIFService.shared.firstGIFData(query: query)
            await MainActor.run {
                self.setAIPanelControls(enabled: true)
                guard let data else {
                    self.aiStatusLabel.text = "No GIF found / provider error."
                    return
                }
                UIPasteboard.general.setData(data, forPasteboardType: "com.compuserve.gif")
                self.aiStatusLabel.text = "GIF copied — paste it into the chat."
            }
        }
    }

    @objc private func aiPasteKey() {
        guard let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            aiStatusLabel.text = "Clipboard is empty. Copy the Gemini API key first."
            return
        }
        guard AIService.shared.saveAPIKey(value) else {
            aiStatusLabel.text = "Could not save that key."
            return
        }
        aiStatusLabel.text = "Gemini key saved."
        rebuildAIPanel()
    }

    @objc private func aiChangeKey() {
        AIService.shared.clearAPIKey()
        rebuildAIPanel()
    }

    @objc private func aiClipboard() {
        openClipboardPanel()
    }

    @objc private func aiFix() { runAI(.fix) }
    @objc private func aiRewrite() { runAI(.rewrite) }
    @objc private func aiTranslate() { runAI(.translate) }
    @objc private func aiTone() { runAI(.tone) }

    private func runAI(_ action: AIAction) {
        guard hasFullAccess else {
            aiStatusLabel.text = "Enable Allow Full Access in iOS Settings first."
            return
        }
        guard AIService.shared.hasAPIKey else {
            aiStatusLabel.text = "Paste a Gemini API key first."
            rebuildAIPanel()
            return
        }

        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        guard !context.isEmpty else {
            aiStatusLabel.text = "Type something first."
            return
        }

        aiStatusLabel.text = "Thinking…"
        setAIPanelControls(enabled: false)

        Task {
            let replacement = await AIService.shared.transform(context, action: action)
            await MainActor.run {
                self.setAIPanelControls(enabled: true)

                guard let replacement, !replacement.isEmpty else {
                    self.aiStatusLabel.text = "Gemini request failed. Check the API key and connection."
                    return
                }

                for _ in context {
                    self.textDocumentProxy.deleteBackward()
                }
                self.textDocumentProxy.insertText(replacement)
                self.hideAIPanel()
                self.schedulePredictionRefresh()
            }
        }
    }

    private func setAIPanelControls(enabled: Bool) {
        func visit(_ view: UIView) {
            if let button = view as? UIButton {
                button.isEnabled = enabled
                button.alpha = enabled ? 1.0 : 0.45
            }
            view.subviews.forEach(visit)
        }
        visit(aiPanel)
    }
}



