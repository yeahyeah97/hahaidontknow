import UIKit
import NaturalLanguage

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    private enum Page { case letters, numbers, symbols, emoji }
    fileprivate enum KeyRole { case normal, shift, delete, mode, emoji, space, returnKey }

    private let predictionBar = UIStackView()
    private let aiButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let keyCanvas = KeyCanvasView()
    private let aiPanel = UIView()
    private let aiStatusLabel = UILabel()
    private var page: Page = .letters
    private var shifted = true
    private var predictionButtons: [UIButton] = []
    private var laidOutKeys: [(TouchKey, CGRect)] = []
    private var cachedCorrection: (word: String, replacement: String)?
    private var predictionGeneration = 0
    private var supplementaryEntries: [UILexiconEntry] = []
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
        view.clipsToBounds = false
        keyHaptic.prepare()
        buildChrome()
        rebuildKeys()
        updateAppearance()
        requestSupplementaryLexicon { [weak self] lexicon in
            DispatchQueue.main.async {
                self?.supplementaryEntries = lexicon.entries
                self?.refreshPredictions()
            }
        }
        refreshPredictions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let referenceWidth: CGFloat = 440
        let sx = keyCanvas.bounds.width / referenceWidth
        let layout = KeyboardPreferences.shared.layoutMode
        for (button, reference) in laidOutKeys {
            var frame = CGRect(
                x: reference.minX * sx,
                y: reference.minY,
                width: reference.width * sx,
                height: reference.height
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
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateReturnKey()
        updateAppearance()
        syncAutoCapitalization()
        refreshLetterCaps()
        refreshPredictions()
    }

    private func buildChrome() {
        aiButton.translatesAutoresizingMaskIntoConstraints = false
        aiButton.setTitle("AI", for: .normal)
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
            aiButton.widthAnchor.constraint(equalToConstant: 38),
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
            keyCanvas.heightAnchor.constraint(equalToConstant: 213),
            keyCanvas.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),

            aiPanel.leadingAnchor.constraint(equalTo: keyCanvas.leadingAnchor),
            aiPanel.trailingAnchor.constraint(equalTo: keyCanvas.trailingAnchor),
            aiPanel.topAnchor.constraint(equalTo: keyCanvas.topAnchor),
            aiPanel.bottomAnchor.constraint(equalTo: keyCanvas.bottomAnchor)
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
                let resolved = self.resolvedNormalKey(at: point, source: key) ?? key
                let display = self.destinationText(for: resolved, matchingCaseOf: original)
                self.showPreview(for: resolved, text: display)
            }
            button.onFingerEnded = { [weak self] key, point, original in
                self?.hidePreview()
                self?.finalizeOptimisticTouch(from: key, point: point, insertedText: original)
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
            badge.text = "EN IT"
            badge.font = .systemFont(ofSize: 12, weight: .medium)
            badge.textColor = UIColor.white.withAlphaComponent(0.42)
            badge.textAlignment = .center
            badge.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                badge.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: -1)
            ])
        }

        keyCanvas.addSubview(button)
        laidOutKeys.append((button, frame))
    }

    private func destinationText(for key: TouchKey, matchingCaseOf source: String) -> String {
        guard var value = key.currentTitle ?? key.learningKey else { return source }
        if source.first?.isUppercase == true {
            value = value.uppercased()
        } else if source.first?.isLowercase == true {
            value = value.lowercased()
        }
        return value
    }

    private func resolvedNormalKey(at point: CGPoint, source: TouchKey? = nil) -> TouchKey? {
        let keys = laidOutKeys.map { $0.0 }.filter {
            $0.referenceRole == .normal && !$0.isHidden && $0.alpha > 0.01
        }
        guard !keys.isEmpty else { return nil }

        // Group visual rows first so staggered rows do not steal taps too easily.
        let sorted = keys.sorted { $0.frame.midY < $1.frame.midY }
        var rows: [[TouchKey]] = []
        for key in sorted {
            if let first = rows.last?.first,
               abs(first.frame.midY - key.frame.midY) < 12 {
                rows[rows.count - 1].append(key)
            } else {
                rows.append([key])
            }
        }

        guard let chosenRow = rows.min(by: { lhs, rhs in
            let ly = lhs.map { $0.frame.midY }.reduce(0,+) / CGFloat(lhs.count)
            let ry = rhs.map { $0.frame.midY }.reduce(0,+) / CGFloat(rhs.count)
            let ldist = abs(point.y - ly)
            let rdist = abs(point.y - ry)

            // Slight vertical stickiness: if the finger is close to the source row,
            // do not jump rows just because it crossed the mathematical midpoint.
            if let source {
                let sourceY = source.frame.midY
                if abs(point.y - sourceY) < 34 {
                    if abs(ly - sourceY) < 12 { return true }
                    if abs(ry - sourceY) < 12 { return false }
                }
            }

            return ldist < rdist
        }) else { return nil }

        return chosenRow.min { lhs, rhs in
            var lscore = lhs.learningKey.map {
                TouchLearningModel.shared.probabilityScore(for: $0, point: point, frame: lhs.frame)
            } ?? hypot(point.x - lhs.frame.midX, point.y - lhs.frame.midY)

            var rscore = rhs.learningKey.map {
                TouchLearningModel.shared.probabilityScore(for: $0, point: point, frame: rhs.frame)
            } ?? hypot(point.x - rhs.frame.midX, point.y - rhs.frame.midY)

            // Bigger invisible hitbox than the visible cap.
            // This deliberately overlaps neighboring caps a little.
            let hitbox = KeyboardPreferences.shared.hitboxMode
            let lComfort = lhs.frame.insetBy(dx: -hitbox.expansionX, dy: -hitbox.expansionY)
            let rComfort = rhs.frame.insetBy(dx: -hitbox.expansionX, dy: -hitbox.expansionY)
            if lComfort.contains(point) { lscore -= hitbox.comfortBonus }
            if rComfort.contains(point) { rscore -= hitbox.comfortBonus }

            // Hysteresis: while sliding, the source key keeps a small advantage
            // until the finger has clearly entered a neighbor's zone.
            if let source {
                if lhs === source { lscore -= 34 }
                if rhs === source { rscore -= 34 }
            }

            return lscore < rscore
        }
    }

    private func finalizeOptimisticTouch(from source: TouchKey, point: CGPoint, insertedText: String) {
        guard source.referenceRole == .normal,
              let destination = resolvedNormalKey(at: point, source: source),
              destination !== source else {
            return
        }

        let replacement = destinationText(for: destination, matchingCaseOf: insertedText)
        guard replacement != insertedText else { return }

        let sourceCenter = CGPoint(x: source.frame.midX, y: source.frame.midY)
        let destinationCenter = CGPoint(x: destination.frame.midX, y: destination.frame.midY)
        let sourceDistance = hypot(point.x - sourceCenter.x, point.y - sourceCenter.y)
        let destinationDistance = hypot(point.x - destinationCenter.x, point.y - destinationCenter.y)

        // Do not flip a character on tiny release jitter. The destination has to be
        // meaningfully closer than the source, which feels much more like iOS/Gboard.
        guard destinationDistance + 4.0 < sourceDistance else { return }

        // The original key was already inserted on touch-down for minimum latency.
        // Correct only the last character if the finger clearly finishes on another cap.
        textDocumentProxy.deleteBackward()
        textDocumentProxy.insertText(replacement)

        if let key = destination.learningKey {
            TouchLearningModel.shared.record(key: key, point: point, frame: destination.frame)
        }

        schedulePredictionRefresh()
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
        let prefs = KeyboardPreferences.shared
        if prefs.sound { UIDevice.current.playInputClick() }
        if prefs.haptics {
            keyHaptic.impactOccurred(intensity: 0.28)
            keyHaptic.prepare()
        }
    }

    private func syncAutoCapitalization() {
        guard page == .letters else { return }
        if textDocumentProxy.autocapitalizationType == UITextAutocapitalizationType.none {
            if shifted {
                shifted = false
                refreshLetterCaps()
            }
            return
        }

        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let shouldShift = context.isEmpty
            || context.hasSuffix("\n")
            || context.hasSuffix(". ")
            || context.hasSuffix("! ")
            || context.hasSuffix("? ")

        if shifted != shouldShift {
            shifted = shouldShift
            refreshLetterCaps()
        }
    }

    private func bestImmediateCorrection(for source: String, context: String) -> String? {
        guard source.count >= 2,
              LocalLanguageModel.shared.frequency(of: source) <= 2 else { return nil }

        if let learned = LocalLanguageModel.shared.learnedCorrections(for: source, limit: 1).first?.0 {
            return matchCase(learned, source: source)
        }

        let primary = preferredLanguage(for: context)
        let secondary = primary == "it_IT" ? "en_US" : "it_IT"
        let checker = UITextChecker()
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)

        func firstGuess(_ language: String) -> String? {
            let misspelled = checker.rangeOfMisspelledWord(
                in: source,
                range: range,
                startingAt: 0,
                wrap: false,
                language: language
            )
            guard misspelled.location != NSNotFound else { return nil }
            return checker.guesses(forWordRange: misspelled, in: source, language: language)?.first
        }

        if let value = firstGuess(primary) {
            return matchCase(value, source: source)
        }
        if let value = firstGuess(secondary) {
            return matchCase(value, source: source)
        }
        return nil
    }

    private func canInsertDoubleSpacePeriod(in context: String) -> Bool {
        guard context.hasSuffix(" ") else { return false }
        let beforeSpace = context.dropLast()
        guard let last = beforeSpace.last else { return false }
        return last.isLetter || last.isNumber
    }

    @objc private func characterKey(_ sender: UIButton) {
        let key = sender as? TouchKey
        var value = key?.learningKey ?? sender.currentTitle ?? ""
        guard !value.isEmpty else { return }

        if page == .letters {
            value = shifted ? value.uppercased() : value.lowercased()
        }

        textDocumentProxy.insertText(value)
        playKeyFeedback()

        if page == .letters && shifted {
            shifted = false
            DispatchQueue.main.async { [weak self] in self?.refreshLetterCaps() }
        }
        schedulePredictionRefresh()
    }

    @objc private func backspaceDown() {
        textDocumentProxy.deleteBackward()
        playKeyFeedback()
        schedulePredictionRefresh()
    }

    @objc private func backspaceHold(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            backspaceTimer?.invalidate()
            textDocumentProxy.deleteBackward()
            playKeyFeedback()
            schedulePredictionRefresh()

            backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.textDocumentProxy.deleteBackward()
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

        if now - lastSpaceTap < 0.48, canInsertDoubleSpacePeriod(in: context) {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            playKeyFeedback()
            lastSpaceTap = 0
            shifted = true
            DispatchQueue.main.async { [weak self] in self?.refreshLetterCaps() }
            schedulePredictionRefresh()
            return
        }

        let previous = previousWord(in: context)
        var committed = currentWord()

        if let current = committed {
            let cached = cachedCorrection.flatMap { correction -> String? in
                guard correction.word.caseInsensitiveCompare(current) == .orderedSame,
                      correction.replacement.caseInsensitiveCompare(current) != .orderedSame else { return nil }
                return correction.replacement
            }
            let replacement = cached ?? bestImmediateCorrection(for: current, context: context)

            if let replacement,
               replacement.caseInsensitiveCompare(current) != .orderedSame {
                replaceCurrentWord(with: replacement)
                LocalLanguageModel.shared.learnCorrection(from: current, to: replacement)
                committed = replacement
            }
        }

        if let committed {
            LocalLanguageModel.shared.learn(word: committed, previous: previous)
            if LocalLanguageModel.shared.frequency(of: committed) >= 2,
               !UITextChecker.hasLearnedWord(committed) {
                UITextChecker.learnWord(committed)
            }
        }

        textDocumentProxy.insertText(" ")
        playKeyFeedback()
        lastSpaceTap = now
        shifted = false
        DispatchQueue.main.async { [weak self] in
            self?.syncAutoCapitalization()
            self?.refreshLetterCaps()
        }
        schedulePredictionRefresh()
    }

    @objc private func returnDown() {
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        if let current = currentWord() {
            LocalLanguageModel.shared.learn(word: current, previous: previousWord(in: context))
            if LocalLanguageModel.shared.frequency(of: current) >= 2,
               !UITextChecker.hasLearnedWord(current) {
                UITextChecker.learnWord(current)
            }
        }
        textDocumentProxy.insertText("\n")
        playKeyFeedback()
        shifted = true
        DispatchQueue.main.async { [weak self] in self?.refreshLetterCaps() }
        schedulePredictionRefresh()
    }

    @objc private func toggleShift() {
        shifted.toggle()
        playKeyFeedback()
        refreshLetterCaps()
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
        let primaryLanguage = preferredLanguage(for: context)
        let secondaryLanguage = primaryLanguage == "it_IT" ? "en_US" : "it_IT"

        guard let word = currentWord(), !word.isEmpty else {
            let learned = LocalLanguageModel.shared.nextWords(after: previous, limit: 3)
            let fallback = primaryLanguage == "it_IT"
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

        let generation = predictionGeneration
        let sourceWord = word
        let learned = LocalLanguageModel.shared.completions(prefix: sourceWord, previous: previous, limit: 8)
        let sourceLower = sourceWord.lowercased()
        let lexiconCandidates = supplementaryEntries.compactMap { entry -> String? in
            let input = entry.userInput
            let output = entry.documentText
            if input.lowercased() == sourceLower { return output }
            if input.lowercased().hasPrefix(sourceLower) { return input }
            if output.lowercased().hasPrefix(sourceLower) { return output }
            return nil
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let checker = UITextChecker()
            let ns = sourceWord as NSString
            let range = NSRange(location: 0, length: ns.length)

            func languageCandidates(_ language: String) -> (String?, [String], [String]) {
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
                let completions = checker.completions(
                    forPartialWordRange: range,
                    in: sourceWord,
                    language: language
                ) ?? []
                return (guesses.first, guesses, completions)
            }

            let primary = languageCandidates(primaryLanguage)
            let secondary = languageCandidates(secondaryLanguage)

            var scores: [String: Int] = [:]
            var display: [String: String] = [:]

            func add(_ value: String, score: Int) {
                guard !value.isEmpty else { return }
                let key = value.lowercased()
                scores[key] = max(scores[key, default: Int.min], score)
                display[key] = self?.matchCase(value, source: sourceWord) ?? value
            }

            // Personal vocabulary is strongest: if you use a word often, Milazy keeps it.
            for (index, value) in learned.enumerated() {
                add(value, score: 1500 - index * 30 + LocalLanguageModel.shared.frequency(of: value) * 10)
            }

            for (index, value) in lexiconCandidates.prefix(8).enumerated() {
                add(value, score: 1325 - index * 20)
            }

            for (value, count) in LocalLanguageModel.shared.learnedCorrections(for: sourceWord, limit: 5) {
                add(value, score: 1700 + count * 80)
            }

            // Exact typed word gets a strong score once learned so names/slang are not "fixed" away.
            let typedFrequency = LocalLanguageModel.shared.frequency(of: sourceWord)
            add(sourceWord, score: 950 + typedFrequency * 25)

            if let correction = primary.0 { add(correction, score: typedFrequency > 1 ? 900 : 1250) }
            for (index, value) in primary.1.dropFirst().enumerated() { add(value, score: 1080 - index * 18) }
            for (index, value) in primary.2.enumerated() { add(value, score: 1020 - index * 12) }

            if let correction = secondary.0 { add(correction, score: 820) }
            for (index, value) in secondary.1.dropFirst().enumerated() { add(value, score: 760 - index * 14) }
            for (index, value) in secondary.2.enumerated() { add(value, score: 720 - index * 10) }

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

                // Auto-correct only from the currently dominant language and never override
                // words the user has already taught Milazy repeatedly.
                if typedFrequency > 2 {
                    self.cachedCorrection = nil
                } else if let learnedFix = LocalLanguageModel.shared.learnedCorrections(for: sourceWord, limit: 1).first?.0 {
                    self.cachedCorrection = (sourceWord, self.matchCase(learnedFix, source: sourceWord))
                } else if let p = primary.0 {
                    self.cachedCorrection = (sourceWord, self.matchCase(p, source: sourceWord))
                } else if let s = secondary.0 {
                    self.cachedCorrection = (sourceWord, self.matchCase(s, source: sourceWord))
                } else {
                    self.cachedCorrection = nil
                }
                self.setPredictions(choices)
            }
        }
    }

    private func preferredLanguage(for text: String) -> String {
        switch KeyboardPreferences.shared.languageMode {
        case .italian: return "it_IT"
        case .english: return "en_US"
        case .automatic: break
        }

        let tokens = words(in: text).map { $0.lowercased() }

        let italian: Set<String> = [
            "a","ad","al","alla","anche","ancora","bene","boh","ciao","che","chi","come",
            "con","cosa","da","dai","dal","dalla","devo","di","dove","e","è","fa","fai",
            "fare","fatto","gli","hai","ho","il","io","la","le","lo","ma","mi","mia","mio",
            "ne","nel","nella","no","non","noi","ok","per","perché","più","poi","puoi","qua",
            "qui","quindi","sei","si","sì","sono","sta","stai","sto","su","te","ti","tu",
            "un","una","va","vai","voi","vorrei"
        ]
        let english: Set<String> = [
            "a","about","all","also","am","and","are","as","at","be","because","but","can",
            "come","do","for","from","go","good","have","he","hello","hey","how","i","if",
            "in","is","it","just","like","me","my","no","not","of","ok","on","or","so",
            "that","the","this","to","up","was","we","what","when","where","who","why",
            "with","you","your"
        ]

        var itScore = 0
        var enScore = 0
        for token in tokens.suffix(8) {
            if italian.contains(token) { itScore += token.count <= 2 ? 2 : 4 }
            if english.contains(token) { enScore += token.count <= 2 ? 2 : 4 }
            if token.range(of: "[àèéìòù]", options: .regularExpression) != nil { itScore += 5 }
        }

        let sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if sample.count >= 8 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(sample)
            if recognizer.dominantLanguage == .italian { itScore += 5 }
            if recognizer.dominantLanguage == .english { enScore += 5 }
        }

        // Bilingual keyboard, but when the evidence is tied prefer Italian instead of
        // always falling back to English. English takes over as soon as its evidence wins.
        return itScore >= enScore ? "it_IT" : "en_US"
    }

    private func setPredictions(_ values: [String]) {
        for (index, button) in predictionButtons.enumerated() {
            button.setTitle(index < values.count ? values[index] : "", for: .normal)
        }
    }

    @objc private func usePrediction(_ sender: UIButton) {
        guard let value = sender.currentTitle, !value.isEmpty else { return }
        let before = currentWord()
        let previous = previousWord(in: textDocumentProxy.documentContextBeforeInput ?? "")
        if let before {
            replaceCurrentWord(with: value)
            if before.caseInsensitiveCompare(value) != .orderedSame {
                LocalLanguageModel.shared.learnCorrection(from: before, to: value)
            }
        } else {
            textDocumentProxy.insertText(value)
        }
        LocalLanguageModel.shared.learn(word: value, previous: previous)
        schedulePredictionRefresh()
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

final class TouchKey: UIButton {
    fileprivate var referenceRole: KeyboardViewController.KeyRole = .normal
    fileprivate var learningKey: String?
    fileprivate var onFingerBegan: ((TouchKey, String) -> Void)?
    fileprivate var onFingerMoved: ((TouchKey, CGPoint, String) -> Void)?
    fileprivate var onFingerEnded: ((TouchKey, CGPoint, String) -> Void)?
    fileprivate var onFingerCancelled: (() -> Void)?
    private var touchStartText: String = ""

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted {
                transform = CGAffineTransform(scaleX: 0.99, y: 0.99)
                alpha = 0.86
            } else {
                UIView.animate(withDuration: 0.045, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.transform = .identity
                    self.alpha = 1
                }
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStartText = currentTitle ?? learningKey ?? ""

        if let key = learningKey,
           let touch = touches.first,
           let container = superview {
            let point = touch.location(in: container)
            let hitbox = KeyboardPreferences.shared.hitboxMode
            if frame.insetBy(dx: -max(14, hitbox.expansionX), dy: -max(9, hitbox.expansionY)).contains(point) {
                TouchLearningModel.shared.record(key: key, point: point, frame: frame)
            }
        }

        onFingerBegan?(self, touchStartText)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first, let container = superview {
            onFingerMoved?(self, touch.location(in: container), touchStartText)
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first, let container = superview {
            onFingerEnded?(self, touch.location(in: container), touchStartText)
        } else {
            onFingerCancelled?()
        }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onFingerCancelled?()
        super.touchesCancelled(touches, with: event)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }
}

final class KeyPreviewView: UIView {
    private let label = UILabel()

    var text: String {
        get { label.text ?? "" }
        set { label.text = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(white: 0.34, alpha: 1)
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)

        label.font = .systemFont(ofSize: 28, weight: .regular)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.heightAnchor.constraint(equalToConstant: 35)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        guard !keys.isEmpty else {
            return super.hitTest(point, with: event)
        }

        let sorted = keys.sorted { $0.frame.midY < $1.frame.midY }
        var rows: [[TouchKey]] = []

        for key in sorted {
            if let anchor = rows.last?.first,
               abs(anchor.frame.midY - key.frame.midY) < 12 {
                rows[rows.count - 1].append(key)
            } else {
                rows.append([key])
            }
        }

        guard let row = rows.min(by: { lhs, rhs in
            let ly = lhs.map { $0.frame.midY }.reduce(0,+) / CGFloat(lhs.count)
            let ry = rhs.map { $0.frame.midY }.reduce(0,+) / CGFloat(rhs.count)
            return abs(point.y - ly) < abs(point.y - ry)
        }) else {
            return super.hitTest(point, with: event)
        }

        // Bigger invisible target than the cap itself. Instead of hard-locking a tap
        // merely because it landed one or two pixels inside a neighboring cap, score
        // all keys in the selected row and favor the user's learned landing center.
        return row.min { lhs, rhs in
            var lscore = lhs.learningKey.map {
                TouchLearningModel.shared.probabilityScore(for: $0, point: point, frame: lhs.frame)
            } ?? hypot(point.x - lhs.frame.midX, point.y - lhs.frame.midY)

            var rscore = rhs.learningKey.map {
                TouchLearningModel.shared.probabilityScore(for: $0, point: point, frame: rhs.frame)
            } ?? hypot(point.x - rhs.frame.midX, point.y - rhs.frame.midY)

            let hitbox = KeyboardPreferences.shared.hitboxMode
            if lhs.frame.insetBy(dx: -hitbox.expansionX, dy: -hitbox.expansionY).contains(point) {
                lscore -= hitbox.comfortBonus
            }
            if rhs.frame.insetBy(dx: -hitbox.expansionX, dy: -hitbox.expansionY).contains(point) {
                rscore -= hitbox.comfortBonus
            }

            return lscore < rscore
        }
    }
}

