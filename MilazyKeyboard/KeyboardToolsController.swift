import UIKit

extension KeyboardViewController {
    @objc func aiTapped() {
        if AIService.shared.hasAPIKey {
            runAI(.fix)
        } else {
            showAIPanel()
        }
    }

    @objc func menuTapped() {
        toolPanel = .menu
        keyCanvas.isHidden = true
        aiPanel.isHidden = false
        rebuildAIPanel()
    }

    func showAIPanel() {
        toolPanel = .ai
        keyCanvas.isHidden = true
        aiPanel.isHidden = false
        rebuildAIPanel()
    }

    func hideAIPanel() {
        aiPanel.isHidden = true
        keyCanvas.isHidden = false
        aiStatusLabel.text = nil
        refreshPredictions()
    }

    func rebuildAIPanel() {
        aiPanel.subviews.forEach { $0.removeFromSuperview() }

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        aiPanel.addSubview(scroll)
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        let title = UILabel()
        title.font = .systemFont(ofSize: 16.5, weight: .semibold)
        title.textAlignment = .center

        aiStatusLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        aiStatusLabel.numberOfLines = 2

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
            let items = ClipboardHistory.shared.items
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
            title.text = "Milazy Keyboard 3.1.2"
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
            scroll.leadingAnchor.constraint(equalTo: aiPanel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: aiPanel.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: aiPanel.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: aiPanel.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 4),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -6),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -20)
        ])
        updateAppearance()
        setAIPanelControls(enabled: aiTask == nil)
    }

    func makePanelRow(_ buttons: [UIButton]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillEqually
        return row
    }

    func aiPanelButton(_ title: String, action: Selector) -> UIButton {
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

    @objc func aiBack() {
        if toolPanel == .ai {
            hideAIPanel()
        } else {
            toolPanel = .ai
            aiStatusLabel.text = nil
            rebuildAIPanel()
        }
    }

    @objc func closeTools() {
        hideAIPanel()
    }

    @objc func menuEmoji() {
        hideAIPanel()
        page = .emoji
        rebuildKeys()
        refreshPredictions()
    }

    @objc func menuTranslate() {
        if AIService.shared.hasAPIKey {
            runAI(.translate)
        } else {
            showAIPanel()
        }
    }

    @objc func openClipboardPanel() {
        toolPanel = .clipboard
        rebuildAIPanel()
    }

    @objc func openSettingsPanel() {
        toolPanel = .settings
        rebuildAIPanel()
    }

    @objc func importClipboard() {
        ClipboardHistory.shared.importSystemClipboard()
        rebuildAIPanel()
    }

    @objc func clearClipboard() {
        ClipboardHistory.shared.clear()
        rebuildAIPanel()
    }

    @objc func pasteClipboardItem(_ sender: UIButton) {
        let items = ClipboardHistory.shared.items
        guard sender.tag >= 0, sender.tag < items.count else { return }
        let text = items[sender.tag]
        inputProxy.insertText(text)
        ClipboardHistory.shared.add(text)
        hideAIPanel()
        schedulePredictionRefresh()
    }

    @objc func cycleLanguage() {
        let values = KeyboardPreferences.LanguageMode.allCases
        let current = KeyboardPreferences.shared.languageMode
        let next = values[(values.firstIndex(of: current)! + 1) % values.count]
        KeyboardPreferences.shared.languageMode = next
        rebuildAIPanel()
        refreshPredictions()
    }

    @objc func cycleLayout() {
        let values = KeyboardPreferences.LayoutMode.allCases
        let current = KeyboardPreferences.shared.layoutMode
        let next = values[(values.firstIndex(of: current)! + 1) % values.count]
        KeyboardPreferences.shared.layoutMode = next
        rebuildAIPanel()
        view.setNeedsLayout()
    }

    @objc func cycleHitbox() {
        let values = KeyboardPreferences.HitboxMode.allCases
        let current = KeyboardPreferences.shared.hitboxMode
        KeyboardPreferences.shared.hitboxMode = values[(values.firstIndex(of: current)! + 1) % values.count]
        rebuildAIPanel()
    }

    @objc func togglePopups() {
        KeyboardPreferences.shared.keyPopups.toggle()
        hidePreview()
        rebuildAIPanel()
    }

    @objc func toggleHaptics() {
        KeyboardPreferences.shared.haptics.toggle()
        rebuildAIPanel()
    }

    @objc func toggleSound() {
        KeyboardPreferences.shared.sound.toggle()
        rebuildAIPanel()
    }

    @objc func cycleGIFProvider() {
        let values = GIFService.Provider.allCases
        let current = GIFService.shared.provider
        GIFService.shared.provider = values[(values.firstIndex(of: current)! + 1) % values.count]
        rebuildAIPanel()
    }

    @objc func pasteGIFKey() {
        guard let key = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            aiStatusLabel.text = "Copy a provider API key first."
            return
        }
        GIFService.shared.saveKey(key, for: GIFService.shared.provider)
        rebuildAIPanel()
    }

    @objc func aiGIF() {
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

        let context = inputProxy.documentContextBeforeInput ?? ""
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

    @objc func aiPasteKey() {
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

    @objc func aiChangeKey() {
        AIService.shared.clearAPIKey()
        rebuildAIPanel()
    }

    @objc func aiClipboard() {
        openClipboardPanel()
    }

    @objc func aiFix() { runAI(.fix) }
    @objc func aiRewrite() { runAI(.rewrite) }
    @objc func aiTranslate() { runAI(.translate) }
    @objc func aiTone() { runAI(.tone) }

    func runAI(_ action: AIAction) {
        guard aiTask == nil else { return }
        if aiPanel.isHidden { showAIPanel() }
        guard hasFullAccess else {
            aiStatusLabel.text = "Enable Allow Full Access in iOS Settings first."
            return
        }
        guard AIService.shared.hasAPIKey else {
            aiStatusLabel.text = "Paste a Gemini API key first."
            return
        }
        let selected = inputProxy.selectedText
        let before = inputProxy.documentContextBeforeInput
        let after = inputProxy.documentContextAfterInput
        let source = selected.flatMap { $0.isEmpty ? nil : $0 } ?? before ?? ""
        guard !source.isEmpty else { aiStatusLabel.text = "Type something first."; return }
        let document = inputProxy.documentIdentifier
        let revision = inputRevision
        aiStatusLabel.text = "Thinking…"
        setAIPanelControls(enabled: false)
        aiTask = Task { [weak self] in
            let replacement = await AIService.shared.transform(source, action: action)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.aiTask = nil
                self.setAIPanelControls(enabled: true)
                guard self.inputRevision == revision,
                      self.inputProxy.documentIdentifier == document,
                      self.inputProxy.documentContextBeforeInput == before,
                      self.inputProxy.documentContextAfterInput == after,
                      self.inputProxy.selectedText == selected else {
                    self.aiStatusLabel.text = "Text changed. Tap Fix again for the current text."
                    return
                }
                guard let replacement, !replacement.isEmpty else {
                    self.aiStatusLabel.text = "Gemini request failed. Check the key and connection."
                    return
                }
                if selected?.isEmpty != false {
                    for _ in source { self.inputProxy.deleteBackward() }
                }
                self.inputProxy.insertText(replacement)
                self.undoCorrection = nil
                self.capitalization.reset()
                self.didInsertText()
                self.hideAIPanel()
            }
        }
    }

    func setAIPanelControls(enabled: Bool) {
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
