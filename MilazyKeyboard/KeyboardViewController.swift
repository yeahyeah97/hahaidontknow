import UIKit

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    enum Page { case letters, numbers, symbols, emoji }
    enum KeyRole { case normal, shift, delete, mode, emoji, space, returnKey }

    private let predictionBar = UIStackView()
    private let aiButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    let keyCanvas = KeyCanvasView()
    let aiPanel = UIView()
    let aiStatusLabel = UILabel()
    var page: Page = .letters
    private var shifted = true
    var capitalization = CapitalizationState()
    private var knownContext: String?
    private var knownDocument: UUID?
    private var lastShiftTap: TimeInterval = 0
    var aiTask: Task<Void, Never>?
    var inputRevision = 0
    private var predictionButtons: [UIButton] = []
    private var laidOutKeys: [(TouchKey, CGRect)] = []
    private let predictionEngine = PredictionEngine()
    private var predictionResult: PredictionEngine.Result?
    private var predictionContext: String?
    var undoCorrection: (source: String, replacement: String, context: String, document: UUID)?
    private var spaceBadge: UILabel?
    private var predictionGeneration = 0
    private var backspaceTimer: Timer?
    private var lastSpaceTap: TimeInterval = 0
    private let keyHaptic = UIImpactFeedbackGenerator(style: .light)
    private var keyPreview: KeyPreviewView?
    enum ToolPanel { case ai, menu, clipboard, settings }
    var toolPanel: ToolPanel = .ai

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
            inputRevision += 1
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

    func rebuildKeys() {
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

    func updateAppearance() {
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

    private func syncAutoCapitalization(context: String? = nil) {
        guard page == .letters else { return }
        let mode: CapitalizationState.Mode
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: mode = .none
        case .words: mode = .words
        case .allCharacters: mode = .allCharacters
        default: mode = .sentences
        }
        shifted = capitalization.uppercase(
            context: context ?? textDocumentProxy.documentContextBeforeInput, mode: mode, current: shifted
        )
        refreshLetterCaps()
    }

    func didInsertText(expectedContext: String? = nil) {
        inputRevision += 1
        knownDocument = textDocumentProxy.documentIdentifier
        knownContext = textDocumentProxy.documentContextBeforeInput
        syncAutoCapitalization(context: expectedContext)
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
        aiTask?.cancel()
        aiTask = nil
        setAIPanelControls(enabled: true)
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
        let before = textDocumentProxy.documentContextBeforeInput
        textDocumentProxy.insertText(value)
        undoCorrection = nil
        lastSpaceTap = 0
        if page == .letters {
            capitalization.consumedLetter()
            shifted = false
        }
        didInsertText(expectedContext: before.map { $0 + value })
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

    func schedulePredictionRefresh() {
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

    func words(in text: String) -> [String] { TextContext.words(in: text) }

    func refreshPredictions() {
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

}



