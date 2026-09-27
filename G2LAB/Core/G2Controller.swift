import Foundation

@MainActor
final class G2Controller: ObservableObject {
    @Published var status = "DISCONNECTED"
    @Published var linkReady = false
    @Published var leftReady = false
    @Published var rightReady = false
    @Published var captionsEnabled = false
    @Published var micActive = false
    @Published var pcmActive = false
    @Published var micLevel = 0.0
    @Published var captionText = ""
    @Published var menuVisible = false
    @Published var lastInput = "—"
    @Published var micPackets = 0
    @Published var validAudioPackets = 0
    @Published var invalidAudioPackets = 0
    @Published var logs: [String] = []

    let models: WhisperModelManager

    private let direct = DirectG2Transport()
    private var decoder: G2LC3Decoder?
    private var hudTask: Task<Void, Never>?
    private var pendingHUDText: String?

    init(models: WhisperModelManager) {
        self.models = models
        wireTransport()
        wireWhisper()
        log("G2 ACCESS v0.5.0 • native menu + downloadable Whisper")
    }

    deinit {
        hudTask?.cancel()
    }

    func connect() {
        status = "CONNECTING"
        log("CONNECT: starting direct dual-lens G2 transport")
        direct.start()
    }

    func disconnect() {
        stopCaptions()
        menuVisible = false
        direct.stop()
        status = "DISCONNECTED"
        linkReady = false
        leftReady = false
        rightReady = false
    }

    func toggleCaptions() async {
        if captionsEnabled {
            stopCaptions()
        } else {
            await startCaptions()
        }
    }

    func startCaptions() async {
        guard linkReady else {
            captionText = "Connect the G2 first."
            return
        }
        guard models.selectedModelInstalled else {
            captionText = "Download an offline Whisper model first."
            log("CAPTIONS: blocked — selected model is not installed")
            return
        }

        decoder = G2LC3Decoder()
        guard decoder != nil else {
            captionText = "LC3 decoder could not start."
            log("CAPTIONS: LC3 decoder init failed")
            return
        }

        let ready = await models.startSession()
        guard ready else {
            captionText = models.lastError ?? "Whisper model failed to load."
            log("CAPTIONS: Whisper model not ready")
            return
        }

        captionsEnabled = true
        menuVisible = false
        captionText = "Listening…"
        direct.setMicEnabled(true)
        direct.showCaption("Listening • \(models.selectedLanguageName)")
        log("CAPTIONS: START \(models.selectedModel.title) / \(models.selectedLanguageName)")
    }

    func stopCaptions() {
        guard captionsEnabled || micActive else { return }
        captionsEnabled = false
        micActive = false
        pcmActive = false
        direct.setMicEnabled(false)
        models.stopSession()
        decoder = nil
        hudTask?.cancel()
        hudTask = nil
        pendingHUDText = nil
        log("CAPTIONS: STOP")
    }

    func openMenu() {
        guard linkReady else {
            log("MENU: blocked — G2 link not verified")
            return
        }
        menuVisible = true
        direct.openNativeMenu(title: "G2 ACCESS", items: menuItems)
        log("MENU: requested native firmware list")
    }

    func closeMenu() {
        menuVisible = false
        direct.closeNativeMenu()
    }

    func hudTest() {
        guard linkReady else { return }
        menuVisible = false
        direct.showCaption("G2 ACCESS\nHUD OK ✓\nNative BLE link verified")
        log("HUD TEST: queued")
    }

    func clearHUD() {
        direct.clearDisplay()
        menuVisible = false
    }

    private var menuItems: [String] {
        [
            captionsEnabled ? "Stop Live Captions" : "Start Live Captions",
            "Model: \(shortModelName)",
            "HUD Test",
            "Close"
        ]
    }

    private var shortModelName: String {
        switch models.selectedModelID {
        case "openai_whisper-tiny": return "Tiny"
        case "openai_whisper-base": return "Base"
        case "openai_whisper-small": return "Small"
        default: return "Large v3"
        }
    }

    private func wireWhisper() {
        models.onLog = { [weak self] line in
            self?.log(line)
        }
        models.onTranscript = { [weak self] text in
            guard let self, self.captionsEnabled else { return }
            self.captionText = text
            self.queueHUD(text)
        }
    }

    private func wireTransport() {
        direct.onLog = { [weak self] line in
            self?.log(line)
        }
        direct.onReadyChanged = { [weak self] left, right in
            guard let self else { return }
            self.leftReady = left
            self.rightReady = right
            if !left || !right, self.linkReady {
                self.linkReady = false
                self.status = "RECOVERING"
            }
        }
        direct.onLinkStateChanged = { [weak self] state in
            guard let self else { return }
            self.status = state
            if state != "VERIFIED" { self.linkReady = false }
        }
        direct.onProtocolReady = { [weak self] in
            guard let self else { return }
            self.linkReady = true
            self.status = "VERIFIED"
            self.log("G2: protocol VERIFIED")
        }
        direct.onMicSessionInterrupted = { [weak self] in
            guard let self else { return }
            self.micActive = false
            self.pcmActive = false
            self.decoder = G2LC3Decoder()
            self.log("MIC: session interrupted; LC3 state reset")
        }
        direct.onMicControlState = { [weak self] state in
            self?.log("MIC CTRL: \(state)")
        }
        direct.onAudioDiagnostics = { [weak self] total, valid, invalid in
            self?.micPackets = total
            self?.validAudioPackets = valid
            self?.invalidAudioPackets = invalid
        }
        direct.onMicPacket = { [weak self] packet in
            self?.consumeMicPacket(packet)
        }
        direct.onInputEvent = { [weak self] event in
            self?.handleInput(event)
        }
    }

    private func consumeMicPacket(_ packet: Data) {
        guard captionsEnabled, let decoder else { return }
        guard let pcm = decoder.decode(packet) else { return }
        micActive = true
        pcmActive = true
        micLevel = decoder.rms
        models.appendPCM16(pcm)
    }

    private func handleInput(_ event: DirectG2Transport.InputEvent) {
        switch event {
        case let .listSelect(name, index):
            lastInput = "SELECT \(index) @\(name)"
            log("INPUT: native list select index=\(index) name=\(name)")
            guard name == "menu-list" else { return }
            runMenuAction(index)

        case let .scroll(name, direction):
            let word = direction == 1 ? "UP" : direction == 2 ? "DOWN" : "\(direction)"
            lastInput = "SCROLL \(word) @\(name)"
            log("INPUT: native scroll \(word) @\(name)")

        case let .gesture(code):
            let word: String
            switch code {
            case 0: word = "TAP"
            case 1: word = "SCROLL UP"
            case 2: word = "SCROLL DOWN"
            case 3: word = "DOUBLE TAP"
            case 4: word = "FOREGROUND ENTER"
            case 5: word = "FOREGROUND EXIT"
            case 7: word = "SYSTEM EXIT"
            default: word = "GESTURE \(code)"
            }
            lastInput = word
            log("INPUT: \(word)")
            if code == 3, !menuVisible { openMenu() }
            if code == 7 { menuVisible = false }
        }
    }

    private func runMenuAction(_ index: Int) {
        switch index {
        case 0:
            menuVisible = false
            Task { await toggleCaptions() }

        case 1:
            cycleInstalledModel()
            direct.openNativeMenu(title: "MODEL • \(shortModelName)", items: menuItems)

        case 2:
            hudTest()

        case 3:
            closeMenu()

        default:
            log("MENU: unknown row \(index)")
        }
    }

    private func cycleInstalledModel() {
        let installed = models.models.filter { models.isInstalled($0.id) }
        guard !installed.isEmpty else {
            log("MENU: no offline model installed")
            return
        }
        let current = installed.firstIndex(where: { $0.id == models.selectedModelID }) ?? -1
        let next = installed[(current + 1) % installed.count]
        models.selectModel(next.id)
        log("MENU: model -> \(next.title)")
    }

    private func queueHUD(_ text: String) {
        pendingHUDText = text
        guard hudTask == nil else { return }
        hudTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self, !Task.isCancelled else { return }
            let value = self.pendingHUDText
            self.pendingHUDText = nil
            self.hudTask = nil
            if let value, self.captionsEnabled {
                self.direct.showCaption(value)
            }
        }
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        logs.insert("\(formatter.string(from: Date()))  \(message)", at: 0)
        if logs.count > 160 { logs.removeLast(logs.count - 160) }
    }
}
