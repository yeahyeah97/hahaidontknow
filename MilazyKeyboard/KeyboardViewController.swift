import UIKit
import NaturalLanguage

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    private enum Page { case letters, numbers, symbols, emoji }
    fileprivate enum KeyRole { case normal, shift, delete, mode, emoji, space, returnKey }

    private let predictionBar = UIStackView()
    private let aiButton = UIButton(type: .system)
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

    var enableInputClicksWhenVisible: Bool { true }

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
        syncAutoCapitalization()
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

        aiButton.translatesAutoresizingMaskIntoConstraints = false
        aiButton.setTitle("AI", for: .normal)
        aiButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        aiButton.layer.cornerRadius = 8
        aiButton.addTarget(self, action: #selector(aiTapped), for: .touchUpInside)
        aiButton.accessibilityLabel = "Deaf AI"
        view.addSubview(aiButton)

        keyCanvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyCanvas)

        aiPanel.translatesAutoresizingMaskIntoConstraints = false
        aiPanel.isHidden = true
        view.addSubview(aiPanel)

        aiStatusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        aiStatusLabel.textAlignment = .center
        aiStatusLabel.numberOfLines = 2

        NSLayoutConstraint.activate([
            predictionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            predictionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            predictionBar.topAnchor.constraint(equalTo: view.topAnchor),
            predictionBar.heightAnchor.constraint(equalToConstant: 35),

            aiButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            aiButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            aiButton.widthAnchor.constraint(equalToConstant: 30),
            aiButton.heightAnchor.constraint(equalToConstant: 24),

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
            let lc = lhs.learningKey.map {
                TouchLearningModel.shared.adjustedCenter(for: $0, frame: lhs.frame)
            } ?? CGPoint(x: lhs.frame.midX, y: lhs.frame.midY)

            let rc = rhs.learningKey.map {
                TouchLearningModel.shared.adjustedCenter(for: $0, frame: rhs.frame)
            } ?? CGPoint(x: rhs.frame.midX, y: rhs.frame.midY)

            let ldx = point.x - lc.x
            let ldy = point.y - lc.y
            let rdx = point.x - rc.x
            let rdy = point.y - rc.y

            var lscore = ldx * ldx + 0.22 * ldy * ldy
            var rscore = rdx * rdx + 0.22 * rdy * rdy

            // Bigger invisible hitbox than the visible cap.
            // This deliberately overlaps neighboring caps a little.
            let lComfort = lhs.frame.insetBy(dx: -8.5, dy: -9.0)
            let rComfort = rhs.frame.insetBy(dx: -8.5, dy: -9.0)
            if lComfort.contains(point) { lscore -= 42 }
            if rComfort.contains(point) { rscore -= 42 }

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
        guard page != .emoji else { return }

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
        aiButton.setTitleColor(dark ? .white : .label, for: .normal)
        aiButton.backgroundColor = dark ? UIColor.white.withAlphaComponent(0.10) : UIColor.black.withAlphaComponent(0.08)
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
        UIDevice.current.playInputClick()
        keyHaptic.impactOccurred(intensity: 0.32)
        keyHaptic.prepare()
    }

    private func syncAutoCapitalization() {
        guard page == .letters,
              textDocumentProxy.autocapitalizationType != .none else { return }

        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let shouldShift = context.isEmpty
            || context.hasSuffix("\n")
            || context.hasSuffix(". ")
            || context.hasSuffix("! ")
            || context.hasSuffix("? ")

        if shouldShift && !shifted {
            shifted = true
            refreshLetterCaps()
        }
    }

    private func canInsertDoubleSpacePeriod(in context: String) -> Bool {
        guard context.hasSuffix(" ") else { return false }
        let beforeSpace = context.dropLast()
        guard let last = beforeSpace.last else { return false }
        return last.isLetter || last.isNumber
    }

    @objc private func characterKey(_ sender: UIButton) {
        guard var value = sender.currentTitle else { return }
        if page == .letters && !shifted { value = value.lowercased() }
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

        if let current = committed,
           let correction = cachedCorrection,
           correction.word.caseInsensitiveCompare(current) == .orderedSame,
           correction.replacement.caseInsensitiveCompare(current) != .orderedSame {
            replaceCurrentWord(with: correction.replacement)
            committed = correction.replacement
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
            guard let title = button.currentTitle,
                  title.count == 1,
                  title.rangeOfCharacter(from: .letters) != nil else { continue }
            button.setTitle(shifted ? title.uppercased() : title.lowercased(), for: .normal)
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
                if typedFrequency > 1 {
                    self.cachedCorrection = nil
                } else {
                    self.cachedCorrection = primary.0.map { (sourceWord, $0) }
                }
                self.setPredictions(choices)
            }
        }
    }

    private func preferredLanguage(for text: String) -> String {
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
        if currentWord() != nil { replaceCurrentWord(with: value) }
        else { textDocumentProxy.insertText(value) }
        schedulePredictionRefresh()
    }

    private func replaceCurrentWord(with replacement: String) {
        guard let word = currentWord() else { return }
        for _ in word { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(replacement)
    }

    @objc private func aiTapped() {
        showAIPanel()
    }

    @objc private func showAITools(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        showAIPanel()
    }

    private func showAIPanel() {
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

        let title = UILabel()
        title.text = "Deaf AI · Gemini"
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textAlignment = .center

        let top = UIStackView(arrangedSubviews: [title, aiStatusLabel])
        top.axis = .vertical
        top.spacing = 4

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false

        aiPanel.addSubview(content)
        content.addArrangedSubview(top)

        if !hasFullAccess {
            aiStatusLabel.text = "Enable Allow Full Access in iOS Settings to use Gemini AI."
            content.addArrangedSubview(aiPanelButton("Back", action: #selector(aiBack)))
        } else if !AIService.shared.hasAPIKey {
            aiStatusLabel.text = "Copy your Gemini API key, then tap Paste Gemini Key."
            content.addArrangedSubview(aiPanelButton("Paste Gemini Key", action: #selector(aiPasteKey)))
            content.addArrangedSubview(aiPanelButton("Back", action: #selector(aiBack)))
        } else {
            aiStatusLabel.text = "AI only runs when you tap one of these actions."

            let row1 = UIStackView(arrangedSubviews: [
                aiPanelButton("Fix", action: #selector(aiFix)),
                aiPanelButton("Rewrite", action: #selector(aiRewrite))
            ])
            row1.axis = .horizontal
            row1.spacing = 8
            row1.distribution = .fillEqually

            let row2 = UIStackView(arrangedSubviews: [
                aiPanelButton("Translate EN ↔ IT", action: #selector(aiTranslate)),
                aiPanelButton("Tone", action: #selector(aiTone))
            ])
            row2.axis = .horizontal
            row2.spacing = 8
            row2.distribution = .fillEqually

            let row3 = UIStackView(arrangedSubviews: [
                aiPanelButton("Clipboard", action: #selector(aiClipboard)),
                aiPanelButton("Change Key", action: #selector(aiChangeKey)),
                aiPanelButton("Back", action: #selector(aiBack))
            ])
            row3.axis = .horizontal
            row3.spacing = 8
            row3.distribution = .fillEqually

            content.addArrangedSubview(row1)
            content.addArrangedSubview(row2)
            content.addArrangedSubview(row3)
        }

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: aiPanel.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: aiPanel.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: aiPanel.topAnchor, constant: 8)
        ])
        updateAppearance()
    }

    private func aiPanelButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(white: 0.27, alpha: 1)
        button.layer.cornerRadius = 8
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func aiBack() {
        hideAIPanel()
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
        if let value = UIPasteboard.general.string {
            textDocumentProxy.insertText(value)
            hideAIPanel()
        } else {
            aiStatusLabel.text = "Clipboard is empty."
        }
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
            if frame.insetBy(dx: -14, dy: -9).contains(point) {
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
            let lc = lhs.learningKey.map {
                TouchLearningModel.shared.adjustedCenter(for: $0, frame: lhs.frame)
            } ?? CGPoint(x: lhs.frame.midX, y: lhs.frame.midY)

            let rc = rhs.learningKey.map {
                TouchLearningModel.shared.adjustedCenter(for: $0, frame: rhs.frame)
            } ?? CGPoint(x: rhs.frame.midX, y: rhs.frame.midY)

            let ldx = point.x - lc.x
            let ldy = point.y - lc.y
            let rdx = point.x - rc.x
            let rdy = point.y - rc.y

            var lscore = ldx * ldx + 0.22 * ldy * ldy
            var rscore = rdx * rdx + 0.22 * rdy * rdy

            // ~8.5pt horizontal and 9pt vertical invisible expansion.
            if lhs.frame.insetBy(dx: -8.5, dy: -9).contains(point) { lscore -= 42 }
            if rhs.frame.insetBy(dx: -8.5, dy: -9).contains(point) { rscore -= 42 }

            return lscore < rscore
        }
    }
}

